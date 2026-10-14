#include <filesystem>
#include <format>
#include <fstream>
#include <optional>

#include "error/reporting.h"
#include "front_end/front_end.h"
#include "front_end/mlir_generation.h"
#include "front_end/type_checking.h"
#include "front_end/work.h"
#include "lexer/lexer.h"
#include "parser/parser.h"
#include "util/logger.h"

namespace hemera {

#define INFO_ALLOC (executor.global_data->info_allocator)

	WorkTarget::WorkTarget(WorkTargetType type, WorkTargetValue value)
		: type{ type }
		, value{ value }
	{}
	WorkTarget::WorkTarget(const WorkTarget&) = default;
	WorkTarget::WorkTarget(WorkTarget&&) = default;
	WorkTarget& WorkTarget::operator=(const WorkTarget&) = default;
	WorkTarget& WorkTarget::operator=(WorkTarget&&) = default;

	Work::Work(WorkType type, WorkTarget&& target)
		: dependency_count{ 0 }
		, type{ type }
		, work_target{ std::move(target) }
	{}

	Dependency::Dependency(WorkTarget&& dependency, Work* owner)
		: dependency{ std::move(dependency) }
		, owner{ owner }
	{}
	Dependency::Dependency(const Dependency&) = default;
	Dependency::Dependency(Dependency&&) = default;
	Dependency& Dependency::operator=(const Dependency&) = default;
	Dependency& Dependency::operator=(Dependency&&) = default;

	void work_execution(WorkThreadData& executor, WorkTarget& target) {
		//TODO(ches) do this
		if (static_cast<void*>(&executor) == static_cast<void*>(&target)) {}//TODO(ches) remove this
	}
	
	void work_if_else(WorkThreadData& executor, WorkTarget& target) {
		//TODO(ches) do this
		if (static_cast<void*>(&executor) == static_cast<void*>(&target)) {}//TODO(ches) remove this
	}

	void work_function_code_generation(WorkThreadData& executor, FunctionInfo* function) {
		mlir_process_function(executor.program_info, function);
	}

	// The text of a string literal, without the quotes the lexer keeps.
	static std::string string_literal_text(InternedString literal) {
		std::string text(literal->begin(), literal->end());
		if (text.size() >= 2 && text.front() == '"' && text.back() == '"') {
			return text.substr(1, text.size() - 2);
		}
		return text;
	}

	static std::optional<BuiltinPackage> builtin_location(std::string_view segment) {
		if (segment == "base") {
			return BuiltinPackage::BASE;
		}
		if (segment == "std") {
			return BuiltinPackage::STD;
		}
		if (segment == "user") {
			return BuiltinPackage::USER;
		}
		if (segment == "vendor") {
			return BuiltinPackage::VENDOR;
		}
		return {};
	}

	/*
	 * The folder an import refers to (docs/packages.md, Imports). A built-in location, optionally
	 * followed by subfolders, names the folder containing the package, which is the folder named
	 * after the import. Anything else is relative to the importing package's folder and names the
	 * package's folder itself. No location means std.
	 */
	static std::filesystem::path import_folder(const Options& options,
		const std::filesystem::path& package_folder, const ImportInfo& import) {

		std::string location = import.location == nullptr
			? std::string("std")
			: string_literal_text(import.location);

		const bool explicitly_relative = location == "." || location == ".."
			|| location.starts_with("./") || location.starts_with("../");

		if (!explicitly_relative) {
			const size_t slash = location.find('/');
			std::optional<BuiltinPackage> builtin = builtin_location(location.substr(0, slash));
			if (builtin) {
				auto iter = options.builtin_paths.find(builtin.value());
				std::filesystem::path folder = iter == options.builtin_paths.end()
					? std::filesystem::path(location.substr(0, slash))
					: iter->second;
				if (slash != std::string::npos) {
					folder /= location.substr(slash + 1);
				}
				return folder / *import.name;
			}
		}
		return package_folder / location;
	}
	
	void work_import(WorkThreadData& executor, WorkTarget& target) {
		LOG_ASSERT(target.type == WorkTargetType::PACKAGE);
		// We expect the path to be a full canonical path at this point
		
		InternedString package_path_text = target.value.name;
		LOG_ASSERT(package_path_text != nullptr);
		std::filesystem::path package_path(*package_path_text);

		std::error_code error;
		if (!std::filesystem::is_directory(package_path, error)) {
			report_error(ErrorCode::E4005, *package_path_text, 0, 0);
			return;
		}
		PackageInfo* package_info = nullptr;

		{
			std::scoped_lock<std::mutex> lock(executor.program_info->packages_mutex);

			MyMap<InternedString, PackageInfo*>& packages = executor.program_info->packages;
			auto iter = packages.find(package_path_text);
			if (iter != packages.end()) {
				// Already imported, by this or another import of the same package
				return;
			}
			package_info = INFO_ALLOC->new_object<PackageInfo>();
			packages.insert(std::make_pair(package_path_text, package_info));
			package_info->full_path = package_path_text;
		}
		
		{
			std::scoped_lock<std::mutex> lock(package_info->files_mutex);

			std::filesystem::directory_iterator files(package_path, error);
			if (error) {
				report_error(ErrorCode::E4005, *package_path_text, 0, 0, error.message());
				return;
			}
			for (const auto& entry : files) {
				if (!entry.is_regular_file(error)) {
					continue;
				}
				if (entry.path().extension() != ".hsc") {
					continue;
				}

				InternedString file_name = intern(entry.path().filename().string());
				
				FileInfo* file_info = INFO_ALLOC->new_object<FileInfo>();
				package_info->files.insert(std::make_pair(file_name, file_info));

				executor.create_work(
					WorkType::PARSE,
					WorkTarget{
						WorkTargetType::FILE,
						WorkTargetValue{.file_location = {package_path_text, file_name } }
					}
				);
			}
		}
	}
	
	void work_parse(WorkThreadData& executor, WorkTarget& target) {
		const FileLocation& location = target.value.file_location;
		LOG_ASSERT(location.file_name != nullptr);

		if (location.package_path == nullptr) {
			std::string details = std::format("Missing package path for {}",
				*location.package_path);
			report_error(ErrorCode::E4000, *location.file_name, 0, 0,
				details);
			return;
		}

		PackageInfo* package_info = nullptr;

		{
			std::scoped_lock<std::mutex> lock(executor.program_info->packages_mutex);

			auto iter = executor.program_info->packages.find(location.package_path);
			if (iter == executor.program_info->packages.end()) {
				std::string details = std::format("Unknown package {}",
					*location.package_path);
				report_error(ErrorCode::E4000, *location.file_name, 0, 0,
					details);
				return;
			}
			package_info = iter->second;
		}
		
		FileInfo* file_info = nullptr;

		{
			std::scoped_lock<std::mutex> lock(package_info->files_mutex);

			auto iter = package_info->files.find(location.file_name);
			if (iter == package_info->files.end()) {
				std::string details = std::format(
					"Missing files entr for {}.{}", *location.package_path,
					*location.file_name);
				report_error(ErrorCode::E4000, *location.file_name, 0, 0,
					details);
				return;
			}
			file_info = iter->second;
		}

		std::filesystem::path dir_path = std::filesystem::path(*location.package_path);
		std::error_code directory_error;
		if (!std::filesystem::is_directory(dir_path, directory_error)) {
			std::string details = std::format(
				"Package {}'s path '{}' is not a valid directory",
				*location.package_path, dir_path.generic_string());
			report_error(ErrorCode::E4000, *location.file_name, 0, 0,
				details);
			return;
		}

		std::string file_path = dir_path.append(*location.file_name).generic_string();
		std::ifstream file(file_path);

		if (!file.is_open()) {
			report_error(ErrorCode::E4000, file_path, 0, 0);
			return;
		}

		Allocator<> token_alloc;
		lexer::lex(file, file_info->tokens, token_alloc, file_path);

		file_info->ast_root = hemera::parser::file(file_path, file_info->tokens, 
			executor.program_info->node_alloc);
		
		// Whether the previous top-level node was an #if or #else_if, which #else_if and #else must follow
		bool after_if_chain = false;

		for (ast::Node* child : file_info->ast_root->children) {
			if (child->node_type != ast::NodeType::DIRECTIVE) {
				after_if_chain = false;
			}
			if (child->node_type == ast::NodeType::PACKAGE) {
				InternedString package_name = child->value.value;

				std::scoped_lock<std::mutex> lock(package_info->files_mutex);
				if (package_info->self_reported_name == nullptr) {
					package_info->self_reported_name = package_name;
				}
				else if (*package_info->self_reported_name != *package_name) {
					std::string details = std::format(
						"We previously saw {} but now see {}",
						*package_info->self_reported_name, *package_name);
					report_error(ErrorCode::E4006, file_path,
						child->value.line_number, child->value.column_number,
						details);
					return;
				}
				continue;
			}
			if (child->node_type == ast::NodeType::IMPORT) {
				LOG_ASSERT(child->children.size() % 2 == 1);
				
				ImportInfo* import = INFO_ALLOC->new_object<ImportInfo>();

				{
					std::scoped_lock<std::mutex> lock(file_info->imports_mutex);
					file_info->imports.push_back(import);
				}

				import->node = child;
				import->name = child->children[0]->value.value;

				for (size_t i = 1; i < child->children.size(); ++i) {
					if (ast::NodeType::KEYWORD_AS == child->children[i]->node_type) {
						++i;
						import->alias = child->children[i]->value.value;
						continue;
					}
					if (ast::NodeType::KEYWORD_FROM == child->children[i]->node_type) {
						++i;
							import->location = child->children[i]->value.value;
						continue;
					}
				}

				std::error_code error;
				std::filesystem::path folder = std::filesystem::weakly_canonical(
					import_folder(*executor.global_data->options,
						std::filesystem::path(*location.package_path), *import),
					error);
				if (error || !std::filesystem::is_directory(folder, error)) {
					report_error(ErrorCode::E4005, file_path,
						child->value.line_number, child->value.column_number,
						folder.string());
					continue;
				}
				import->resolved_path = intern(folder.string());
				executor.create_work(WorkType::IMPORT,
					WorkTarget{ WorkTargetType::PACKAGE, { .name = import->resolved_path } });

				continue;
			}
			if (child->node_type == ast::NodeType::DEFINITION) {
				executor.create_work(WorkType::TYPE_CHECK,
					WorkTarget(WorkTargetType::DEFINITION,
						{ .node_location = { location, child } })
				);
				continue;
			}
			if (child->node_type == ast::NodeType::DIRECTIVE) {
				InternedString value = child->value.value;
				const bool continues_if_chain = after_if_chain;
				after_if_chain = false;

				if (value->compare("#if") == 0) {
					//TODO(ches) evaluate the chain with IF_ELSE work, including imports inside it
					after_if_chain = true;
				}
				else if (value->compare("#else_if") == 0 || value->compare("#else") == 0) {
					if (!continues_if_chain) {
						std::string details = std::format("{} without an #if", *value);

						report_error(ErrorCode::E4002, file_path,
							child->value.line_number,
							child->value.column_number,
							details);
					}
					after_if_chain = value->compare("#else_if") == 0;
				}
				else if (value->compare("#run") == 0) {
					ast::Node* expr = child->children[0];

					executor.create_work(WorkType::EXECUTION,
						WorkTarget(WorkTargetType::EXPRESSION,
							{ .node_location = { location, expr } })
					);
				}
				else {
					std::string details = std::string(*value);

					report_error(ErrorCode::E4002, *location.file_name,
						child->value.line_number,
						child->value.column_number,
						details);
				}

				continue;
			}

			std::string details = std::format("Did not expect {}",
				*child->value.value);

			report_error(ErrorCode::E4001, *location.file_name, 
				child->value.line_number, 
				child->value.column_number,
				details);
		}
	}

	void work_type_check(WorkThreadData& executor, WorkTarget& target) {
		switch (target.type) {
			case WorkTargetType::DEFINITION:
				type_check_definition(executor, target.value.node_location.file,
					nullptr, target.value.node_location.node);
				break;
			case WorkTargetType::EXPRESSION:
				type_check_expression(executor, target.value.node_location.file,
					nullptr, target.value.node_location.node);
				break;
			case WorkTargetType::FILE:
				LOG_ERROR("Trying to type check a file");
				break;
			case WorkTargetType::FUNCTION:
			{
				FunctionInfo* function = target.value.function;
				FileLocation file_location{
					function->package != nullptr ? function->package->full_path : nullptr,
					function->file != nullptr ? function->file->full_path : nullptr,
				};
				type_check_function(executor, file_location, nullptr, function);
				break;
			}
			case WorkTargetType::PACKAGE:
				LOG_ERROR("Trying to type check a package");
				break;
		}
	}
}
