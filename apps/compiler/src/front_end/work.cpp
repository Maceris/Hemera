#include <algorithm>
#include <filesystem>
#include <format>
#include <fstream>
#include <optional>
#include <sstream>
#include <unordered_set>

#include "error/reporting.h"
#include "front_end/base_sources.h"
#include "front_end/checking.h"
#include "front_end/documentation.h"
#include "front_end/front_end.h"
#include "front_end/names.h"
#include "front_end/walk.h"
#include "front_end/work.h"
#include "middle_end/code_values.h"
#include "middle_end/generate.h"
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
	 * Runs compile-time code (docs/compilation.md, Compile-Time Execution) once everything it reaches is
	 * checked, waiting for what isn't yet, then wakes what needs its value.
	 */
	static void run_when_checked(WorkThreadData& executor, Evaluation* evaluation) {
		// Again while everything it was waiting for got checked meanwhile
		while (true) {
			std::vector<Declaration*> unchecked;
			const bool ran = run_evaluation(executor.program_info, *executor.global_data->options, *evaluation, unchecked);
			if (unchecked.empty()) {
				finish_evaluation(executor, evaluation, ran);
				return;
			}
			for (Declaration* declaration : unchecked) {
				Progress progress = wait_for_declaration(executor, evaluation, declaration);
				if (Progress::PARKED == progress) {
					return;
				}
				if (Progress::FAILED == progress) {
					// It has errors, which were reported
					finish_evaluation(executor, evaluation, false);
					return;
				}
			}
		}
	}

	/*
	 * Compile-time code: a constant's value that checking needs, or a #run at the top of a file, which is
	 * checked first and runs while the program is checked (docs/directives.md).
	 */
	void work_execution(WorkThreadData& executor, WorkTarget& target) {
		if (WorkTargetType::EVALUATION == target.type) {
			run_when_checked(executor, target.value.evaluation);
			return;
		}
		const NodeLocation& at = target.value.node_location;
		NameRegistry& names = executor.program_info->names;
		Evaluation* evaluation = nullptr;
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			std::unique_ptr<Evaluation>& slot = names.evaluations[at.node];
			if (slot == nullptr) {
				slot = std::make_unique<Evaluation>();
				slot->node = at.node;
				slot->file_path = file_path_of(at.file.package_path, at.file.file_name);
				slot->queued = true;
			}
			evaluation = slot.get();
		}
		if (evaluation->checked == nullptr) {
			auto checked = std::make_shared<CheckedBody>();
			Progress progress = check_top_level_run(executor, at.file, at.node, checked.get());
			if (Progress::PARKED == progress) {
				return;
			}
			if (Progress::FAILED == progress) {
				finish_evaluation(executor, evaluation, false);
				return;
			}
			evaluation->checked = checked;
		}
		run_when_checked(executor, evaluation);
	}
	
	static void process_top_level_nodes(WorkThreadData& executor, const FileLocation& location,
		FileInfo* file_info, const MyVector<ast::Node*>& nodes, size_t start);

	/*
	 * A top-level #insert (docs/compilation.md, Code Values): its code, run once at compile time, copied for
	 * this place and processed as if written there, like the branch an #if picks. It holds declarations,
	 * and #run, #assert, #if and #insert, which are what goes at the top level.
	 */
	static Progress insert_at_top_level(WorkThreadData& executor, IfChain* chain, FileInfo* file_info,
		const std::string& file_path) {
		ast::Node* insert = chain->branches.front();
		const ast::Node* tree = nullptr;
		Progress progress = code_at_top_level(executor, chain, file_info, tree);
		if (progress != Progress::DONE) {
			return progress;
		}
		ProgramInfo* program = executor.program_info;
		const std::shared_ptr<const ast::Origin> origin = program->made_nodes.origin(insert);
		const ast::InsertionSite site{ origin != nullptr ? origin->file : file_path, insert->value.line_number,
			insert->value.column_number };
		const ast::Node* inserted = copy_to_insert(program->made_nodes, program->quotes, tree, site, origin.get());
		if (inserted == nullptr) {
			return Progress::FAILED;
		}
		show_inserted(executor.global_data->options, site, inserted, program->quotes);
		if (ast::NodeType::BLOCK != inserted->node_type && !is_code_list(inserted)) {
			report_at(ErrorCode::E4014, file_path, &program->made_nodes, inserted,
				"#insert at the top level puts declarations there: quote them with #code { ... }");
			return Progress::FAILED;
		}
		for (const ast::Node* item : inserted->children) {
			const bool declares = ast::NodeType::DEFINITION == item->node_type
				|| (ast::NodeType::DIRECTIVE == item->node_type && item->value.value != nullptr
					&& (*item->value.value == "#run" || *item->value.value == "#assert" || *item->value.value == "#insert"
						|| *item->value.value == "#if" || *item->value.value == "#else_if" || *item->value.value == "#else"));
			if (!declares) {
				report_at(ErrorCode::E4014, file_path, &program->made_nodes, item,
					"only declarations, #run, #assert, #if and #insert go at the top level");
				return Progress::FAILED;
			}
		}
		process_top_level_nodes(executor, chain->file, file_info, inserted->children, 0);
		return Progress::DONE;
	}

	/*
	 * Evaluates an #if chain's conditions in order and processes the branch it picks. Waiting for a
	 * constant parks the whole chain, which starts over when woken; nothing is processed until a
	 * branch is picked.
	 */
	static Progress decide_if_chain(WorkThreadData& executor, IfChain* chain) {
		FileInfo* file_info = find_file(executor.program_info, chain->file.package_path,
			chain->file.file_name);
		const std::string file_path = file_path_of(chain->file.package_path, chain->file.file_name);
		if (!chain->branches.empty() && chain->branches.front()->value.value->compare("#insert") == 0) {
			return insert_at_top_level(executor, chain, file_info, file_path);
		}

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
	 * Why an import's location can't be used, as a message for E4042, or nothing if it can. Control characters are
	 * never part of one: on Windows some are dropped when a path is opened, so ".\x01." could be checked as one name
	 * and opened as "..".
	 */
	static std::optional<std::string> location_text_problem(std::string_view location) {
		if (location.empty()) {
			return "the location is empty";
		}
		for (const char c : location) {
			const auto byte = static_cast<unsigned char>(c);
			if (byte < 0x20 || byte == 0x7f) {
				return std::format("it holds the control character U+{:04X}", static_cast<unsigned>(byte));
			}
			if (c == '\\') {
				return "it uses '\\', but locations separate folders with '/'";
			}
		}
		return {};
	}

	/*
	 * Why the path after a location's prefix, like "os/uefi" in "std:os/uefi", can't be used, or nothing if it can.
	 * Each folder must be a plain name: not empty, "." or "..", and not ending in '.' or ' ', which Windows drops when
	 * opening a path (so "..." or ".. " would act as ".."). This is only for clear errors; the folder found is still
	 * checked to be inside the location after links are followed (resolve_import).
	 */
	static std::optional<std::string> prefixed_path_problem(std::string_view prefix, std::string_view path) {
		if (path.empty()) {
			return std::format("\"{}:\" names no package; add its folder, like \"{}:io\"", prefix, prefix);
		}
		size_t start = 0;
		while (start <= path.size()) {
			const size_t slash = std::min(path.find('/', start), path.size());
			const std::string_view folder = path.substr(start, slash - start);
			if (folder.empty()) {
				return std::format("\"{}\" has an empty folder name", path);
			}
			if (folder == "." || folder == "..") {
				return std::format("\"{}\" can't use \"{}\" inside {}", path, folder, prefix);
			}
			if (folder.back() == '.' || folder.back() == ' ' || folder.front() == ' ') {
				return std::format("\"{}\" has the folder \"{}\", which starts with a space or ends with '.' or a space",
					path, folder);
			}
			if (folder.find(':') != std::string_view::npos) {
				return std::format("\"{}\" has a second ':'", path);
			}
			start = slash + 1;
		}
		return {};
	}

	// Whether path is root or inside it, both already canonical: the same folders, then maybe more.
	static bool is_within(const std::filesystem::path& path, const std::filesystem::path& root) {
		auto path_part = path.begin();
		for (auto root_part = root.begin(); root_part != root.end(); ++root_part, ++path_part) {
			if (root_part->empty() && std::next(root_part) == root.end()) {
				// A root ending in a separator has an empty last part
				return true;
			}
			if (path_part == path.end() || *path_part != *root_part) {
				return false;
			}
		}
		return true;
	}

	static bool base_has_package(std::string_view folder);
	static std::string_view base_folder(InternedString package_path);

	/*
	 * Where an import's package is (docs/packages.md, Imports): a package of base, by its folder in base, or the
	 * canonical path of a folder on disk.
	 */
	struct ImportPlace {
		bool from_base = false;
		std::string folder;
	};

	/*
	 * Finds the package an import names, or reports why it can't (E4042, E4005) and gives nothing.
	 *
	 * A location starting with a built-in location's name and ':', like "std:os/uefi", is that package's folder inside
	 * the built-in location; no location is the std package named after the import. Anything else is a folder relative
	 * to the importing package's own. The folder a prefixed location finds must stay inside its built-in location after
	 * every link is followed; the path it gives is the one every later step uses, so what was checked is what's read.
	 */
	static std::optional<ImportPlace> resolve_import(const Options& options, const FileLocation& importer,
		const ImportInfo& import, const std::string& file_path, const ast::Node* node) {

		const auto invalid = [&](const std::string& why) -> std::optional<ImportPlace> {
			report_error(ErrorCode::E4042, file_path, node->value.line_number, node->value.column_number, why);
			return {};
		};
		const auto missing = [&](const std::string& what) -> std::optional<ImportPlace> {
			report_error(ErrorCode::E4005, file_path, node->value.line_number, node->value.column_number, what);
			return {};
		};

		const std::string location = import.location == nullptr
			? "std:" + std::string(std::string_view(*import.name))
			: string_literal_text(import.location);
		if (auto problem = location_text_problem(location)) {
			return invalid(*problem);
		}

		const size_t colon = location.find(':');
		if (colon != std::string::npos) {
			const std::string prefix = location.substr(0, colon);
			const std::string path = location.substr(colon + 1);
			std::optional<BuiltinPackage> builtin = builtin_location(prefix);
			if (!builtin) {
				return invalid(std::format("\"{}\" isn't a built-in location; those are base, std, user and vendor, "
					"and a relative folder's location has no ':'", prefix));
			}
			if (auto problem = prefixed_path_problem(prefix, path)) {
				return invalid(*problem);
			}
			if (builtin.value() == BuiltinPackage::BASE) {
				if (!base_has_package(path)) {
					return missing(location);
				}
				return ImportPlace{ true, path };
			}

			auto iter = options.builtin_paths.find(builtin.value());
			std::error_code error;
			const std::filesystem::path root = std::filesystem::weakly_canonical(
				iter == options.builtin_paths.end() ? std::filesystem::path(prefix) : iter->second, error);
			if (error) {
				return missing(location);
			}
			const std::filesystem::path folder = std::filesystem::weakly_canonical(root / path, error);
			if (error || !std::filesystem::is_directory(folder, error)) {
				return missing(std::format("{} ({})", location, (root / path).string()));
			}
			if (!is_within(folder, root)) {
				return invalid(std::format("\"{}\" leads to {}, outside {} at {}", location, folder.string(), prefix,
					root.string()));
			}
			return ImportPlace{ false, folder.string() };
		}

		// Relative to a package of base, like "./x86_64" in base/intrinsics, is in base too
		if (is_base_package(importer.package_path)) {
			std::string folder = (std::filesystem::path(std::string(base_folder(importer.package_path))) / location)
				.lexically_normal().generic_string();
			while (folder.ends_with("/")) {
				folder.pop_back();
			}
			if (folder.starts_with("..") || !base_has_package(folder)) {
				return missing(std::format("base/{}", folder));
			}
			return ImportPlace{ true, folder };
		}

		std::error_code error;
		const std::filesystem::path folder = std::filesystem::weakly_canonical(
			std::filesystem::path(*importer.package_path) / location, error);
		if (error || !std::filesystem::is_directory(folder, error)) {
			return missing(folder.string());
		}
		return ImportPlace{ false, folder.string() };
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

	/*
	 * The file --test adds to the root package (docs/testing.md): an entry, TEST_ENTRY, that runs the package's #test
	 * functions and reports them to standard output, its exit code 0 if every one passed and 1 otherwise. Its package
	 * statement names the package as another of its files does.
	 */
	static constexpr std::string_view TEST_ENTRY_FILE = "<hemera --test>.hsc";

	// Whether a package is the one --test adds its entry to: the root, when the build is one of its tests.
	static bool gets_test_entry(WorkThreadData& executor, InternedString package_path) {
		const Options* options = executor.global_data->options;
		return options != nullptr && options->test && std::string_view(*package_path) == options->input.string();
	}

	/*
	 * The name a package's files give it: the first line of one of its .hsc files that starts "package ". Empty if
	 * none does, which leaves the generated file without a package statement, an error that says so.
	 */
	static std::string package_name_in(const std::filesystem::path& folder) {
		std::error_code error;
		for (const auto& entry : std::filesystem::directory_iterator(folder, error)) {
			if (entry.path().extension() != ".hsc") {
				continue;
			}
			std::ifstream file(entry.path(), std::ios::binary);
			std::string line;
			while (std::getline(file, line)) {
				if (line.starts_with("package ")) {
					std::string name = line.substr(std::string_view("package ").size());
					while (!name.empty() && std::isspace(static_cast<unsigned char>(name.back()))) {
						name.pop_back();
					}
					return name;
				}
			}
		}
		return {};
	}

	// The source of the file --test adds, with its filter written in as a string literal.
	// Text as a string literal's contents: its quotes and backslashes escaped.
	static std::string escaped(std::string_view text) {
		std::string result;
		for (char character : text) {
			if (character == '"' || character == '\\') {
				result += '\\';
			}
			result += character;
		}
		return result;
	}

	static std::string test_entry_source(const Options& options) {
		const std::string package_name = package_name_in(options.input);
		// A fuzzing build's entry fuzzes the one test, its input the counters' coverage guides
		if (!options.fuzz.empty()) {
			return std::format(
				"{}"
				"import fuzzing from \"std:fuzzing\"\n"
				"\n"
				"{} :: fn() -> int {{\n"
				"    options :: fuzzing.FuzzOptions.{{seconds = {}, runs = {}, folder = \"{}\", seed = {}}}\n"
				"    return fuzzing.fuzz({}, \"{}\", options)\n"
				"}}\n", package_name.empty() ? std::string() : std::format("package {}\n\n", package_name), TEST_ENTRY,
				options.fuzz_seconds, options.fuzz_runs, escaped(options.fuzz_folder), options.fuzz_seed, options.fuzz,
				escaped(options.fuzz));
		}
		const std::string seed = options.test_seeded ? std::format("{}", options.test_seed) : "null";
		return std::format(
			"{}"
			"import compiler from \"base:compiler\"\n"
			"import testing from \"std:testing\"\n"
			"\n"
			"{} :: fn() -> int {{\n"
			"    tests :: #insert testing.tests_of(compiler.load_package(\".\"))\n"
			"    options :: testing.RunOptions.{{filter = \"{}\", tags = \"{}\", seed = {}, runs = {}}}\n"
			"    return if testing.run(tests, testing.STANDARD_OUTPUT, options) == 0 {{ 0 }} else {{ 1 }}\n"
			"}}\n", package_name.empty() ? std::string() : std::format("package {}\n\n", package_name), TEST_ENTRY,
			escaped(options.test_filter), escaped(options.test_tags), seed, options.test_runs);
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
			std::vector<InternedString> file_names;
			for (const auto& entry : files) {
				if (entry.is_regular_file(error) && entry.path().extension() == ".hsc") {
					file_names.push_back(intern(entry.path().filename().string()));
				}
			}
			if (gets_test_entry(executor, package_path_text)) {
				file_names.push_back(intern(std::string(TEST_ENTRY_FILE)));
			}
			for (InternedString file_name : file_names) {
				
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

		std::optional<ImportPlace> place = resolve_import(*executor.global_data->options, location, *import,
			file_path, child);
		if (!place) {
			return;
		}
		if (place->from_base) {
			// Base is the interface to what the compiler provides, so nothing is read from files
			import->resolved_path = intern(std::string(BASE_PACKAGE_PREFIX) + place->folder);
			// builtin's names are the compiler's own, so it has nothing to load
			if (!is_compiler_provided(import->resolved_path)) {
				executor.create_work(WorkType::IMPORT,
					WorkTarget{ WorkTargetType::PACKAGE, { .name = import->resolved_path } });
			}
		}
		else {
			import->resolved_path = intern(place->folder);
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
				else if (value->compare("#insert") == 0) {
					// Like an #if chain: names the package doesn't declare yet may come from it
					IfChain* chain = INFO_ALLOC->new_object<IfChain>();
					chain->file = location;
					chain->branches.push_back(child);
					begin_if_chain(executor, chain);
					executor.create_work(WorkType::IF_ELSE,
						WorkTarget(WorkTargetType::EXPRESSION, { .if_chain = chain }));
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

			// What the parser set aside after an error, already reported, isn't checked
			if (ast::NodeType::ERROR == child->node_type) {
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

		if (*location.file_name == TEST_ENTRY_FILE && gets_test_entry(executor, location.package_path)) {
			std::istringstream file(test_entry_source(*executor.global_data->options));
			parse_and_process(executor, location, package_info, file_info, file, file_path_of(location.package_path, location.file_name));
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
		/*
		 * Binary, so the lexer sees the file's own bytes, and its offsets are the file's (the lexer takes CRLF). An
		 * overlay's bytes are read in its place, still reported as this file.
		 */
		const Options* options = executor.global_data->options;
		const std::string* overlay = options != nullptr ? find_overlay(*options, file_path) : nullptr;
		std::ifstream file(overlay != nullptr ? *overlay : file_path, std::ios::binary);

		if (!file.is_open()) {
			report_error(ErrorCode::E4000, file_path, 0, 0);
			return;
		}
		parse_and_process(executor, location, package_info, file_info, file, file_path);
	}

	/*
	 * A package's ALLOWED_WARNINGS, the warnings not shown in it (docs/compilation.md, Allowing and Denying Warnings),
	 * from whichever of its files declares it, usually package_info.hsc. Its value is read as written, so it's an
	 * array of string literals, like string.["hemera:W2001", "fonts:*"]: anything else is an error (E4046).
	 */
	static void read_allowed_warnings(const FileLocation& location, ast::Node* root, const std::string& file_path) {
		for (ast::Node* child : root->children) {
			if (ast::NodeType::DEFINITION != child->node_type || child->children.empty()
				|| child->children[0]->value.value == nullptr || *child->children[0]->value.value != "ALLOWED_WARNINGS") {
				continue;
			}
			ast::Node* value = definition_value(child);
			std::vector<std::string> patterns;
			// An array literal holds its elements in a LIST
			ast::Node* elements = value != nullptr && ast::NodeType::ARRAY_LITERAL == value->node_type && value->children.size() == 1
				&& ast::NodeType::LIST == value->children[0]->node_type ? value->children[0] : nullptr;
			bool written_out = elements != nullptr;
			if (written_out) {
				for (ast::Node* element : elements->children) {
					if (ast::NodeType::LITERAL == element->node_type && TokenType::LITERAL_STRING == element->value.type) {
						patterns.push_back(ast::string_value(element));
					}
					else {
						written_out = false;
					}
				}
			}
			const std::string_view wrong = !written_out ? "an array of string literals"
				: std::any_of(patterns.begin(), patterns.end(), [](const std::string& pattern) { return !is_warning_pattern(pattern); })
				? "warnings written prefix:code, like hemera:W2001, prefix:* or *" : "";
			if (!wrong.empty()) {
				report_error(ErrorCode::E4046, file_path, child->value.line_number, child->value.column_number,
					std::format("ALLOWED_WARNINGS lists the warnings not shown in the package, as {}", wrong));
				continue;
			}
			allow_warnings_in_package(std::string(*location.package_path), std::move(patterns));
		}
	}

	// Lexes and parses a file's text, checks its package name, and processes its top-level nodes.
	static void parse_and_process(WorkThreadData& executor, const FileLocation& location,
		PackageInfo* package_info, FileInfo* file_info, std::istream& file, const std::string& file_path) {

		Allocator<> token_alloc;
		// With its comments, whose documentation comments are kept for reflection, and the rest dropped
		lexer::lex(file, file_info->tokens, token_alloc, file_path, true);
		keep_documentation(file_path, file_info->tokens, file_info->comments, executor.program_info->check_documentation);

		file_info->ast_root = hemera::parser::file(file_path, file_info->tokens,
			executor.program_info->node_alloc, &executor.program_info->quotes);
		read_allowed_warnings(location, file_info->ast_root, file_path);

		// The names it uses, which is all that's read of its tokens after this; then the tokens go
		std::unordered_set<InternedString> seen;
		for (const Token& token : file_info->tokens) {
			if (TokenType::IDENTIFIER == token.type && token.value != nullptr && seen.insert(token.value).second) {
				file_info->names.push_back({ token.value, token.line_number, token.column_number });
			}
		}
		MyVector<Token>(file_info->tokens.get_allocator()).swap(file_info->tokens);

		for (ast::Node* child : file_info->ast_root->children) {
			if (child->node_type != ast::NodeType::PACKAGE) {
				continue;
			}
			// The name is the package statement's identifier; the PACKAGE node itself has no text
			if (child->children.empty() || child->children[0]->value.value == nullptr) {
				continue;
			}
			InternedString package_name = child->children[0]->value.value;
			// hemera is the prefix of the compiler's own codes, like hemera:E4015, so no package is named it
			if (*package_name == COMPILER_PREFIX) {
				report_error(ErrorCode::E4044, file_path, child->children[0]->value.line_number,
					child->children[0]->value.column_number,
					std::format("{} is the prefix of the compiler's own diagnostics, like {}:E4015", COMPILER_PREFIX, COMPILER_PREFIX));
			}

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
				// Done, with or without errors: compile-time code that calls it can go on
				if (check_body(executor, target.value.declaration) != Progress::PARKED) {
					finish_body(executor, target.value.declaration);
				}
				break;
			case WorkTargetType::TYPE_DEFAULTS:
				check_type_defaults(executor, target.value.declaration);
				break;
			case WorkTargetType::ASSERT:
				check_top_level_assert(executor, target.value.node_location.file, target.value.node_location.node);
				break;
			case WorkTargetType::EXPRESSION:
				LOG_ERROR("Trying to type check an expression, which is IF_ELSE or EXECUTION work");
				break;
			case WorkTargetType::EVALUATION:
				LOG_ERROR("Trying to type check compile-time code, which is EXECUTION work");
				break;
			case WorkTargetType::FILE:
				LOG_ERROR("Trying to type check a file");
				break;
			case WorkTargetType::FUNCTION:
				LOG_ERROR("Trying to type check a FunctionInfo; a function's body is checked as BODY work");
				break;
			case WorkTargetType::PACKAGE:
				LOG_ERROR("Trying to type check a package");
				break;
		}
	}
}
