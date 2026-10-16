#include <filesystem>
#include <format>
#include <fstream>
#include <optional>
#include <sstream>

#include "error/reporting.h"
#include "front_end/base_sources.h"
#include "front_end/checking.h"
#include "front_end/front_end.h"
#include "front_end/mlir_generation.h"
#include "front_end/names.h"
#include "front_end/walk.h"
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

	/*
	 * A #run at the top of a file, which runs while the program is checked (docs/directives.md). Compile-time
	 * code only runs once the program is checked so far (docs/compilation.md, Compile-Time Execution), so
	 * it's reported rather than skipped.
	 */
	void work_execution(WorkThreadData& executor, WorkTarget& target) {
		(void)executor;
		const NodeLocation& at = target.value.node_location;
		report_error(ErrorCode::E4024, file_path_of(at.file.package_path, at.file.file_name),
			at.node->value.line_number, at.node->value.column_number,
			"#run at the top of a file isn't supported yet: compile-time code runs in constants and functions so far");
	}
	
	static void process_top_level_nodes(WorkThreadData& executor, const FileLocation& location,
		FileInfo* file_info, const MyVector<ast::Node*>& nodes, size_t start);

	/*
	 * Evaluates an #if chain's conditions in order and processes the branch it picks. Waiting for a
	 * constant parks the whole chain, which starts over when woken; nothing is processed until a
	 * branch is picked.
	 */
	static Progress decide_if_chain(WorkThreadData& executor, IfChain* chain) {
		FileInfo* file_info = find_file(executor.program_info, chain->file.package_path,
			chain->file.file_name);
		const std::string file_path = file_path_of(chain->file.package_path, chain->file.file_name);

		for (ast::Node* branch : chain->branches) {
			const bool is_else = branch->value.value->compare("#else") == 0;
			if (!is_else) {
				if (branch->children.empty()) {
					return Progress::FAILED;
				}
				ConstantValue condition;
				Progress progress = evaluate_condition(executor, chain, file_info, branch->children[0],
					condition);
				if (progress != Progress::DONE) {
					return progress;
				}
				if (ConstantValue::Kind::BOOLEAN != condition.kind) {
					report_error(ErrorCode::E4010, file_path, branch->value.line_number,
						branch->value.column_number, "an #if condition must be true or false");
					return Progress::FAILED;
				}
				if (!condition.boolean) {
					continue;
				}
			}
			process_top_level_nodes(executor, chain->file, file_info, branch->children,
				is_else ? 0 : 1);
			return Progress::DONE;
		}
		return Progress::DONE;
	}

	void work_if_else(WorkThreadData& executor, WorkTarget& target) {
		IfChain* chain = target.value.if_chain;
		if (decide_if_chain(executor, chain) != Progress::PARKED) {
			end_if_chain(executor, chain);
		}
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
	
	static void list_package_files(WorkThreadData& executor, InternedString package_path_text,
		PackageInfo* package_info);
	static void list_base_package_files(WorkThreadData& executor, InternedString package_path_text,
		PackageInfo* package_info);

	void work_import(WorkThreadData& executor, WorkTarget& target) {
		LOG_ASSERT(target.type == WorkTargetType::PACKAGE);
		// We expect the path to be a full canonical path at this point
		
		InternedString package_path_text = target.value.name;
		LOG_ASSERT(package_path_text != nullptr);
		std::filesystem::path package_path(*package_path_text);

		const bool from_base = is_base_package(package_path_text);
		std::error_code error;
		if (!from_base && !std::filesystem::is_directory(package_path, error)) {
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
		begin_file_work(executor, package_path_text);
		if (from_base) {
			list_base_package_files(executor, package_path_text, package_info);
		}
		else {
			list_package_files(executor, package_path_text, package_info);
		}
		end_file_work(executor, package_path_text);
	}

	// The folder under base of a package from base, like "runtime" for "<base>/runtime".
	static std::string_view base_folder(InternedString package_path) {
		return std::string_view(*package_path).substr(BASE_PACKAGE_PREFIX.size());
	}

	// Creates a PARSE work for each source file of a package from base, which the compiler holds.
	static void list_base_package_files(WorkThreadData& executor, InternedString package_path_text,
		PackageInfo* package_info) {

		std::scoped_lock<std::mutex> lock(package_info->files_mutex);
		for (const EmbeddedFile& embedded : embedded_base_files()) {
			if (embedded.folder != base_folder(package_path_text)) {
				continue;
			}
			/*
			 * builtin.hsc and constants.hsc describe the compiler's own names; builtin's other files,
			 * like its generic types and views, are compiled like any package's
			 */
			if (is_compiler_provided(package_path_text)
				&& (embedded.file_name == "builtin.hsc" || embedded.file_name == "constants.hsc")) {
				continue;
			}
			InternedString file_name = intern(std::string(embedded.file_name));
			FileInfo* file_info = INFO_ALLOC->new_object<FileInfo>();
			package_info->files.insert(std::make_pair(file_name, file_info));

			begin_file_work(executor, package_path_text);
			executor.create_work(
				WorkType::PARSE,
				WorkTarget{
					WorkTargetType::FILE,
					WorkTargetValue{.file_location = {package_path_text, file_name } }
				}
			);
		}
	}

	// Whether base has a package in folder, like "runtime" or "intrinsics/x86_64".
	static bool base_has_package(std::string_view folder) {
		for (const EmbeddedFile& embedded : embedded_base_files()) {
			if (embedded.folder == folder) {
				return true;
			}
		}
		return false;
	}

	// Creates a PARSE work for each source file in a package.
	static void list_package_files(WorkThreadData& executor, InternedString package_path_text,
		PackageInfo* package_info) {

		std::filesystem::path package_path(*package_path_text);
		std::error_code error;
		
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

				begin_file_work(executor, package_path_text);
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
	
	// Records an import, and starts loading its package unless the compiler provides it (base).
	static void process_import(WorkThreadData& executor, const FileLocation& location,
		FileInfo* file_info, ast::Node* child) {

		const std::string file_path = file_path_of(location.package_path, location.file_name);

		ImportInfo* import = INFO_ALLOC->new_object<ImportInfo>();
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

		// Base is the interface to what the compiler provides, so nothing is read from files
		std::string location_text = import->location == nullptr
			? std::string("std")
			: string_literal_text(import->location);
		const size_t slash = location_text.find('/');
		const bool relative = location_text == "." || location_text == ".."
			|| location_text.starts_with("./") || location_text.starts_with("../");
		// From base, or relative to a package of base, like "./x86_64" in base/intrinsics
		const bool from_base = relative ? is_base_package(location.package_path)
			: location_text.substr(0, slash) == "base";
		if (from_base) {
			std::string folder;
			if (relative) {
				folder = (std::filesystem::path(std::string(base_folder(location.package_path)))
					/ location_text).lexically_normal().generic_string();
				while (folder.ends_with("/")) {
					folder.pop_back();
				}
			}
			else {
				std::string subfolders = slash == std::string::npos ? std::string() : location_text.substr(slash + 1) + "/";
				folder = subfolders + std::string(std::string_view(*import->name));
			}
			if (folder.starts_with("..") || !base_has_package(folder)) {
				report_error(ErrorCode::E4005, file_path,
					child->value.line_number, child->value.column_number,
					std::format("base/{}", folder));
				return;
			}
			import->resolved_path = intern(std::string(BASE_PACKAGE_PREFIX) + folder);
			// builtin's names are the compiler's own, so it has nothing to load
			if (!is_compiler_provided(import->resolved_path)) {
				executor.create_work(WorkType::IMPORT,
					WorkTarget{ WorkTargetType::PACKAGE, { .name = import->resolved_path } });
			}
		}
		else {
			std::error_code error;
			std::filesystem::path folder = std::filesystem::weakly_canonical(
				import_folder(*executor.global_data->options,
					std::filesystem::path(*location.package_path), *import),
				error);
			if (error || !std::filesystem::is_directory(folder, error)) {
				report_error(ErrorCode::E4005, file_path,
					child->value.line_number, child->value.column_number,
					folder.string());
				return;
			}
			import->resolved_path = intern(folder.string());
			executor.create_work(WorkType::IMPORT,
				WorkTarget{ WorkTargetType::PACKAGE, { .name = import->resolved_path } });
		}

		{
			std::scoped_lock<std::mutex> lock(file_info->imports_mutex);
			file_info->imports.push_back(import);
		}
	}

	/*
	 * Handles a file's top-level nodes from start: imports, definitions (declared now, resolved by
	 * their own work), #if chains (evaluated by their own work) and #run. Used for a whole file, and
	 * for the branch an #if chain picks.
	 */
	static void process_top_level_nodes(WorkThreadData& executor, const FileLocation& location,
		FileInfo* file_info, const MyVector<ast::Node*>& nodes, size_t start) {

		const std::string file_path = file_path_of(location.package_path, location.file_name);

		for (size_t i = start; i < nodes.size(); ++i) {
			ast::Node* child = nodes[i];

			if (child->node_type == ast::NodeType::PACKAGE) {
				continue;
			}
			if (child->node_type == ast::NodeType::IMPORT) {
				LOG_ASSERT(child->children.size() % 2 == 1);
				process_import(executor, location, file_info, child);
				continue;
			}
			if (child->node_type == ast::NodeType::DEFINITION) {
				declare(executor, location.package_path, location.file_name, file_info, child);
				executor.create_work(WorkType::TYPE_CHECK,
					WorkTarget(WorkTargetType::DEFINITION,
						{ .node_location = { location, child } })
				);
				continue;
			}
			if (child->node_type == ast::NodeType::DIRECTIVE) {
				InternedString value = child->value.value;

				if (value->compare("#if") == 0) {
					// The chain: this #if, and any #else_if and #else right after it
					IfChain* chain = INFO_ALLOC->new_object<IfChain>();
					chain->file = location;
					chain->branches.push_back(child);
					while (i + 1 < nodes.size()
						&& ast::NodeType::DIRECTIVE == nodes[i + 1]->node_type
						&& (nodes[i + 1]->value.value->compare("#else_if") == 0
							|| nodes[i + 1]->value.value->compare("#else") == 0)) {
						++i;
						chain->branches.push_back(nodes[i]);
						if (nodes[i]->value.value->compare("#else") == 0) {
							break;
						}
					}
					begin_if_chain(executor, chain);
					executor.create_work(WorkType::IF_ELSE,
						WorkTarget(WorkTargetType::EXPRESSION, { .if_chain = chain }));
				}
				else if (value->compare("#else_if") == 0 || value->compare("#else") == 0) {
					std::string details = std::format("{} without an #if", *value);

					report_error(ErrorCode::E4002, file_path,
						child->value.line_number,
						child->value.column_number,
						details);
				}
				else if (value->compare("#assert") == 0) {
					executor.create_work(WorkType::TYPE_CHECK,
						WorkTarget(WorkTargetType::ASSERT, { .node_location = { location, child } }));
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

					report_error(ErrorCode::E4002, file_path,
						child->value.line_number,
						child->value.column_number,
						details);
				}
				continue;
			}

			std::string details = std::format("Did not expect {}",
				*child->value.value);

			report_error(ErrorCode::E4001, file_path,
				child->value.line_number,
				child->value.column_number,
				details);
		}
	}

	static void parse_file(WorkThreadData& executor, const FileLocation& location);
	static void parse_and_process(WorkThreadData& executor, const FileLocation& location,
		PackageInfo* package_info, FileInfo* file_info, std::istream& file, const std::string& file_path);
	static std::string_view base_folder(InternedString package_path);

	void work_parse(WorkThreadData& executor, WorkTarget& target) {
		const FileLocation& location = target.value.file_location;
		LOG_ASSERT(location.file_name != nullptr);

		if (location.package_path == nullptr) {
			report_error(ErrorCode::E4000, *location.file_name, 0, 0, "Missing package path");
			return;
		}
		parse_file(executor, location);
		end_file_work(executor, location.package_path);
	}

	static void parse_file(WorkThreadData& executor, const FileLocation& location) {

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

		if (is_base_package(location.package_path)) {
			std::string file_path = file_path_of(location.package_path, location.file_name);
			for (const EmbeddedFile& embedded : embedded_base_files()) {
				if (embedded.folder == base_folder(location.package_path)
					&& embedded.file_name == std::string_view(*location.file_name)) {
					std::istringstream file(embedded.contents());
					parse_and_process(executor, location, package_info, file_info, file, file_path);
					return;
				}
			}
			report_error(ErrorCode::E4000, file_path, 0, 0);
			return;
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
		parse_and_process(executor, location, package_info, file_info, file, file_path);
	}

	// Lexes and parses a file's text, checks its package name, and processes its top-level nodes.
	static void parse_and_process(WorkThreadData& executor, const FileLocation& location,
		PackageInfo* package_info, FileInfo* file_info, std::istream& file, const std::string& file_path) {

		Allocator<> token_alloc;
		lexer::lex(file, file_info->tokens, token_alloc, file_path);

		file_info->ast_root = hemera::parser::file(file_path, file_info->tokens, 
			executor.program_info->node_alloc);
		
		for (ast::Node* child : file_info->ast_root->children) {
			if (child->node_type != ast::NodeType::PACKAGE) {
				continue;
			}
			// The name is the package statement's identifier; the PACKAGE node itself has no text
			if (child->children.empty() || child->children[0]->value.value == nullptr) {
				continue;
			}
			InternedString package_name = child->children[0]->value.value;

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
		}

		process_top_level_nodes(executor, location, file_info, file_info->ast_root->children, 0);
	}

	void work_type_check(WorkThreadData& executor, WorkTarget& target) {
		switch (target.type) {
			case WorkTargetType::DEFINITION:
				// Names first: everything the declaration refers to exists, and what it needs is resolved
				resolve_definition(executor, target.value.node_location.file.package_path,
					target.value.node_location.file.file_name, target.value.node_location.node);
				break;
			case WorkTargetType::INSTANCE:
				resolve_instance(executor, target.value.declaration);
				break;
			case WorkTargetType::BODY:
				check_body(executor, target.value.declaration);
				break;
			case WorkTargetType::ASSERT:
				check_top_level_assert(executor, target.value.node_location.file, target.value.node_location.node);
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
