#include <filesystem>
#include <format>
#include <fstream>

#include "error/reporting.h"
#include "front_end/front_end.h"
#include "front_end/hlir_generation.h"
#include "front_end/type_checking.h"
#include "front_end/work.h"
#include "lexer/lexer.h"
#include "parser/parser.h"
#include "util/logger.h"

namespace hemera {

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
		if ((void*)&executor == (void*)&target) {}//TODO(ches) remove this
	}
	
	void work_if_else(WorkThreadData& executor, WorkTarget& target) {
		//TODO(ches) do this
		if ((void*)&executor == (void*)&target) {}//TODO(ches) remove this
	}

	void work_function_hlir_generation(WorkThreadData& executor, FunctionInfo* function) {
		hlir_process_function(executor, function);
	}
	
	void work_import(WorkThreadData& executor, WorkTarget& target) {
		// Find the package
		// Note down package details in the package struct
		// Find the files in the package
		// Add to package structure
		// Add work for those files to be parsed
		
		//TODO(ches) do this
		if ((void*)&executor == (void*)&target) {}//TODO(ches) remove this
	}
	
	void work_parse(WorkThreadData& executor, WorkTarget& target) {
		const FileLocation& location = target.value.file_location;
		PackageInfo* package_info = nullptr;

		{
			std::scoped_lock<std::mutex> lock(executor.info->packages_mutex);

			auto iter = executor.info->packages.find(location.package_name);
			if (iter == executor.info->packages.end()) {
				LOG_ASSERT(location.file_name != nullptr);
				LOG_ASSERT(location.package_name != nullptr);

				std::string details = std::format("Unknown package {}",
					*location.package_name);
				report_error(ErrorCode::E4000, *location.file_name, 0, 0,
					details);
				return;
			}
			package_info = iter->second;
		}

		InternedString package_path = package_info->full_path;
		if (package_path == nullptr) {
			LOG_ASSERT(location.file_name != nullptr);
			LOG_ASSERT(location.package_name != nullptr);

			std::string details = std::format("Missing package path for {}",
				*location.package_name);
			report_error(ErrorCode::E4000, *location.file_name, 0, 0,
				details);
			return;
		}
		FileInfo* file_info = nullptr;

		{
			std::scoped_lock<std::mutex> lock(package_info->files_mutex);

			auto iter = package_info->files.find(location.file_name);
			if (iter == package_info->files.end()) {
				LOG_ASSERT(location.file_name != nullptr);
				LOG_ASSERT(location.package_name != nullptr);

				std::string details = std::format(
					"Missing files entr for {}.{}", *location.package_name,
					*location.file_name);
				report_error(ErrorCode::E4000, *location.file_name, 0, 0,
					details);
				return;
			}
			file_info = iter->second;
		}

		std::filesystem::path dir_path = std::filesystem::path(*package_path);
		if (!std::filesystem::exists(dir_path) 
			|| !std::filesystem::is_directory(dir_path)) {
			std::string details = std::format(
				"Pacakge {}'s path '{}' is not a valid directory",
				*location.package_name, dir_path.generic_string());
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
			executor.info->node_alloc);

		Info* info = executor.global_data->info;
		
		for (ast::Node* child : file_info->ast_root->children) {
			if (child->type == ast::NodeType::PACKAGE) {
				//TODO(ches) check it matches the pacakge
				continue;
			}
			if (child->type == ast::NodeType::IMPORT) {
				LOG_ASSERT(child->children.size() % 2 == 1);
				
				ImportInfo* import = info->info_alloc.new_object<ImportInfo>();
				
				{
					std::scoped_lock<std::mutex> lock(file_info->imports_mutex);
					file_info->imports.push_back(import);
				}

				import->name = child->children[0]->value.value;

				for (size_t i = 1; i < child->children.size(); ++i) {
					if (ast::NodeType::KEYWORD_AS == child->children[i]->type) {
						++i;
						import->alias = child->children[i]->value.value;
						continue;
					}
					if (ast::NodeType::KEYWORD_FROM == child->children[i]->type) {
						++i;
						import->location = child->children[i]->value.value;
						continue;
					}
				}

				continue;
			}
			if (child->type == ast::NodeType::DEFINITION) {
				executor.create_work(WorkType::TYPE_CHECK,
					WorkTarget(WorkTargetType::DEFINITION, { .node = child })
				);
				continue;
			}
			if (child->type == ast::NodeType::DIRECTIVE) {
				//TODO(ches) run or evaluate the directive

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
				type_check_definition(executor, target.value.node);
				break;
			case WorkTargetType::EXPRESSION:
				type_check_expression(executor, target.value.node);
				break;
			case WorkTargetType::FILE:
				LOG_ERROR("Trying to type check a package");
				break;
			case WorkTargetType::FUNCTION:
				type_check_function(executor, target.value.function);
				break;
			case WorkTargetType::PACKAGE:
				LOG_ERROR("Trying to type check a package");
				break;
		}
	}
}
