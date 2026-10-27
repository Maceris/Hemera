#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <format>
#include <set>
#include <string_view>

#include "error/reporting.h"
#include "front_end/front_end.h"
#include "front_end/names.h"
#include "front_end/checking.h"
#include "front_end/walk.h"
#include "front_end/work.h"
#include "middle_end/code_values.h"
#include "middle_end/reflection.h"
#include "util/logger.h"

namespace hemera {

	/*
	 * The names base/builtin declares (builtin.hsc and constants.hsc), which the compiler provides
	 * to every file without an import, plus the implicit context. A test checks these against base.
	 */
	static constexpr std::string_view BUILTIN_NAMES[] = {
		// Constants / Keywords
		"null", "false", "true",
		"context",
		// Booleans
		"b8", "b16", "b32", "b64", "bool",
		// Integers
		"i8", "i16", "i32", "i64", "i128", "int",
		"u8", "u16", "u32", "u64", "u128", "uint", "uintptr", "usize",
		// Floating point numbers
		"f16", "f32", "f64",
		// Complex numbers
		"c32", "c64", "c128",
		// Quaternions
		"q64", "q128", "q256",
		// Endian specific integers
		"i16be", "i32be", "i64be", "i128be", "u16be", "u32be", "u64be", "u128be",
		"i16le", "i32le", "i64le", "i128le", "u16le", "u32le", "u64le", "u128le",
		// Endian specific floating point numbers
		"f16be", "f32be", "f64be",
		"f16le", "f32le", "f64le",
		// Strings
		"char", "string", "cstring",
		// Pointers
		"ptr", "rawptr",
		"relptr8", "relptr16", "relptr32", "relptr64",
		// Vectors
		"vector", "v128", "v256", "v512",
		// Type related
		"any", "type",
		// Structs
		"Optional", "Result",
		// Functions
		"align_of", "size_of", "offset_of", "type_of", "type_info_of", "types_are_aliases", "is_secret_type",
		"max_value", "min_value", "todo",
		// Complex numbers' and quaternions' parts, conjugates and magnitudes, and any number's absolute value
		"real", "imag", "jmag", "kmag", "conj", "abs",
		// Views over raw memory (base/builtin/views.hsc)
		"view_of", "string_of",
		// Constants
		"OS", "TARGET_ARCH",
	};

	std::span<const std::string_view> builtin_names() {
		return BUILTIN_NAMES;
	}

	bool is_builtin_name(InternedString name) {
		if (name == nullptr) {
			return false;
		}
		return std::find(std::begin(BUILTIN_NAMES), std::end(BUILTIN_NAMES),
			std::string_view(*name)) != std::end(BUILTIN_NAMES);
	}

	// Pointer-like builtins, whose type arguments only need to be declared
	static bool is_pointer_like(InternedString name) {
		if (name == nullptr) {
			return false;
		}
		std::string_view text(*name);
		return text == "ptr" || text == "rawptr" || text.starts_with("relptr");
	}

	std::string file_path_of(InternedString package_path, InternedString file_name) {
		if (package_path == nullptr || file_name == nullptr) {
			return std::string();
		}
		// Base's files aren't on disk, so their paths are written the same everywhere
		if (is_base_package(package_path)) {
			return std::string(std::string_view(*package_path)) + "/" + std::string(std::string_view(*file_name));
		}
		return (std::filesystem::path(std::string_view(*package_path))
			/ std::string_view(*file_name)).string();
	}

	static bool is_text(InternedString value, std::string_view text) {
		return value != nullptr && std::string_view(*value) == text;
	}

	// = in a definition, a named argument, a field's or parameter's default. Operators have no text.
	static bool is_assign(const ast::Node* node) {
		return TokenType::OPERATOR_ASSIGN == node->value.type;
	}

	FileInfo* find_file(ProgramInfo* program_info, InternedString package_path,
		InternedString file_name) {

		PackageInfo* package = nullptr;
		{
			std::scoped_lock<std::mutex> lock(program_info->packages_mutex);
			auto iter = program_info->packages.find(package_path);
			if (iter == program_info->packages.end()) {
				return nullptr;
			}
			package = iter->second;
		}
		std::scoped_lock<std::mutex> lock(package->files_mutex);
		auto iter = package->files.find(file_name);
		return iter == package->files.end() ? nullptr : iter->second;
	}

	static WaitKey name_key(InternedString package_path, InternedString name) {
		return WaitKey{ WaitKey::Kind::NAME_DECLARED, package_path, name, nullptr, nullptr };
	}

	static WaitKey resolved_key(Declaration* declaration) {
		return WaitKey{ WaitKey::Kind::DECLARATION_RESOLVED, nullptr, nullptr, declaration, nullptr };
	}

	static WaitKey chain_key(IfChain* chain) {
		return WaitKey{ WaitKey::Kind::CHAIN_DECIDED, nullptr, nullptr, nullptr, chain };
	}

	static WaitKey body_key(Declaration* function) {
		return WaitKey{ WaitKey::Kind::BODY_CHECKED, nullptr, nullptr, function, nullptr };
	}

	static WaitKey evaluation_key(Evaluation* evaluation) {
		return WaitKey{ WaitKey::Kind::EVALUATION_DONE, nullptr, nullptr, nullptr, nullptr, evaluation };
	}

	// Moves every work waiting for key back into the queues. The registry's mutex must be held.
	static void wake_locked(GlobalThreadData& global_data, NameRegistry& names, const WaitKey& key) {
		auto iter = names.waiting.find(key);
		if (iter == names.waiting.end()) {
			return;
		}
		for (ParkedWork& parked : iter->second) {
			if (parked.owner != nullptr) {
				names.parked_resolvers.erase(parked.owner);
			}
			if (parked.owner_chain != nullptr) {
				names.parked_chains.erase(parked.owner_chain);
			}
			global_data.parked_work -= 1;
			requeue_work(global_data, parked.work);
		}
		names.waiting.erase(iter);
	}

	// The names a DEFINITION node declares, as IDENTIFIER nodes; _ is skipped.
	static std::vector<ast::Node*> defined_names(ast::Node* definition) {
		std::vector<ast::Node*> result;
		if (definition->children.empty()) {
			return result;
		}
		ast::Node* names_node = definition->children[0];
		if (ast::NodeType::LIST == names_node->node_type) {
			for (ast::Node* child : names_node->children) {
				if (ast::NodeType::IDENTIFIER == child->node_type) {
					result.push_back(child);
				}
			}
		}
		else if (ast::NodeType::IDENTIFIER == names_node->node_type) {
			result.push_back(names_node);
		}
		return result;
	}

	static bool same_name(InternedString a, InternedString b) {
		return a != nullptr && b != nullptr && *a == *b;
	}

	std::vector<Declaration*> declare(WorkThreadData& executor, InternedString package_path,
		InternedString file_name, FileInfo* file, ast::Node* definition) {

		std::vector<Declaration*> result;
		NameRegistry& names = executor.program_info->names;
		std::string file_path = file_path_of(package_path, file_name);

		for (ast::Node* name_node : defined_names(definition)) {
			InternedString name = name_node->value.value;
			bool duplicate = false;
			{
				std::scoped_lock<std::mutex> lock(names.mutex);
				auto key = std::make_pair(package_path, name);
				// Names are unique in a package, functions too: there's no overloading
				if (names.declarations.contains(key)) {
					duplicate = true;
				}
				else {
					Declaration& declaration = names.storage.emplace_back();
					declaration.name = name;
					declaration.package_path = package_path;
					declaration.file_name = file_name;
					declaration.file = file;
					declaration.node = definition;
					classify_declaration(names, &declaration);
					names.declarations[key] = &declaration;
					result.push_back(&declaration);

					wake_locked(*executor.global_data, names, name_key(package_path, name));
				}
			}
			if (duplicate) {
				report_error(ErrorCode::E4009, file_path, name_node->value.line_number,
					name_node->value.column_number, std::string(std::string_view(*name)));
			}
		}
		return result;
	}

	// Wakes every lookup waiting on a name in the package. The registry's mutex must be held.
	static void wake_package_locked(GlobalThreadData& global_data, NameRegistry& names,
		InternedString package_path) {

		std::vector<WaitKey> keys;
		for (const auto& [key, list] : names.waiting) {
			if (WaitKey::Kind::NAME_DECLARED == key.kind && key.package_path == package_path) {
				keys.push_back(key);
			}
		}
		for (const WaitKey& key : keys) {
			wake_locked(global_data, names, key);
		}
	}

	// Every file of the package is parsed. The registry's mutex must be held.
	static bool files_parsed_locked(NameRegistry& names, InternedString package_path) {
		auto iter = names.progress.find(package_path);
		return iter != names.progress.end() && iter->second.started
			&& iter->second.files_pending == 0;
	}

	void begin_file_work(WorkThreadData& executor, InternedString package_path) {
		NameRegistry& names = executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		PackageProgress& progress = names.progress[package_path];
		progress.started = true;
		progress.files_pending += 1;
	}

	void end_file_work(WorkThreadData& executor, InternedString package_path) {
		NameRegistry& names = executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		PackageProgress& progress = names.progress[package_path];
		LOG_ASSERT(progress.files_pending > 0);
		progress.files_pending -= 1;
		if (progress.files_pending == 0) {
			wake_package_locked(*executor.global_data, names, package_path);
		}
	}

	void begin_if_chain(WorkThreadData& executor, IfChain* chain) {
		NameRegistry& names = executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		names.progress[chain->file.package_path].pending_chains.push_back(chain);
	}

	void end_if_chain(WorkThreadData& executor, IfChain* chain) {
		NameRegistry& names = executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		std::vector<IfChain*>& pending = names.progress[chain->file.package_path].pending_chains;
		pending.erase(std::remove(pending.begin(), pending.end(), chain), pending.end());
		wake_locked(*executor.global_data, names, chain_key(chain));
	}

	// Parks the walk's work until key happens, looking up needed. The registry's mutex must be held.
	static void park_locked(Walk& walk, NameRegistry& names, const WaitKey& key, ast::Node* where,
		InternedString needed, ast::Node* reason) {

		std::list<ParkedWork>& list = names.waiting[key];
		// Code #insert put here is reported where it was written (docs/compilation.md, Code Values)
		const std::shared_ptr<const ast::Origin> origin = where != nullptr
			? walk.executor.program_info->made_nodes.origin(where) : nullptr;
		list.push_back(ParkedWork{
			walk.executor.current_work,
			key,
			walk.owner,
			walk.chain,
			needed,
			reason,
			origin != nullptr ? origin->file : walk.file_path,
			where != nullptr ? where->value.line_number : 0,
			where != nullptr ? where->value.column_number : 0,
			origin != nullptr ? inserted_note(*origin) : std::string(),
		});
		if (walk.owner != nullptr) {
			names.parked_resolvers[walk.owner] = &list.back();
		}
		if (walk.chain != nullptr) {
			names.parked_chains[walk.chain] = &list.back();
		}
		walk.executor.global_data->parked_work += 1;
	}

	// The package a file imports under local_name, or null. Compiler-provided packages (base) count.
	InternedString imported_package(FileInfo* file, InternedString local_name) {
		if (file == nullptr) {
			return nullptr;
		}
		std::scoped_lock<std::mutex> lock(file->imports_mutex);
		for (ImportInfo* import : file->imports) {
			InternedString local = import->alias != nullptr ? import->alias : import->name;
			if (local != nullptr && *local == *local_name) {
				return import->resolved_path;
			}
		}
		return nullptr;
	}

	static bool is_local(const Walk& walk, InternedString name) {
		for (InternedString local : walk.locals) {
			if (*local == *name) {
				return true;
			}
		}
		return false;
	}

	// The name an IMPORT node makes a package available under: its alias, or its name.
	static InternedString import_local_name(const ast::Node* import) {
		for (size_t i = 1; i + 1 < import->children.size(); ++i) {
			if (ast::NodeType::KEYWORD_AS == import->children[i]->node_type) {
				return import->children[i + 1]->value.value;
			}
		}
		return import->children.empty() ? nullptr : import->children[0]->value.value;
	}

	// What to look for in an undecided #if chain.
	enum class Look : uint8_t {
		/// A definition of the name.
		DEFINITION,
		/// Any import, since the imported package may declare the name.
		ANY_IMPORT,
		/// An import making a package available under the name.
		IMPORT_NAMED,
	};

	static bool is_chain_directive(const ast::Node* node) {
		return ast::NodeType::DIRECTIVE == node->node_type
			&& (is_text(node->value.value, "#if") || is_text(node->value.value, "#else_if")
				|| is_text(node->value.value, "#else"));
	}

	// Searches one branch of an #if chain, and the chains nested in it. The condition is skipped.
	static ast::Node* find_in_branch(ast::Node* branch, InternedString name, Look look) {
		const size_t start = is_text(branch->value.value, "#else") ? 0 : 1;
		for (size_t i = start; i < branch->children.size(); ++i) {
			ast::Node* child = branch->children[i];
			if (ast::NodeType::DEFINITION == child->node_type && Look::DEFINITION == look) {
				for (ast::Node* name_node : defined_names(child)) {
					if (same_name(name_node->value.value, name)) {
						return child;
					}
				}
			}
			else if (ast::NodeType::IMPORT == child->node_type
				&& (Look::ANY_IMPORT == look
					|| (Look::IMPORT_NAMED == look && same_name(import_local_name(child), name)))) {
				return child;
			}
			else if (is_chain_directive(child)) {
				ast::Node* found = find_in_branch(child, name, look);
				if (found != nullptr) {
					return found;
				}
			}
			// Code an #insert puts there may declare anything (docs/compilation.md, Code Values), but no imports
			else if (Look::DEFINITION == look && ast::NodeType::DIRECTIVE == child->node_type
				&& is_text(child->value.value, "#insert")) {
				return child;
			}
		}
		return nullptr;
	}

	// What in an undecided #if chain's branches may provide name, or null. A top-level #insert is a chain of its own.
	static ast::Node* find_in_chain(IfChain* chain, InternedString name, Look look) {
		for (ast::Node* branch : chain->branches) {
			if (is_text(branch->value.value, "#insert")) {
				return Look::DEFINITION == look ? branch : nullptr;
			}
			ast::Node* found = find_in_branch(branch, name, look);
			if (found != nullptr) {
				return found;
			}
		}
		return nullptr;
	}

	// What a lookup in one package found.
	enum class Found : uint8_t {
		DECLARATION,
		NOTHING,
		PARKED,
	};

	/*
	 * Whether package_path declares name, for good: it does, or its files are all parsed and no #if
	 * chain in it that isn't decided yet may declare it. Otherwise the walk waits for that. The
	 * registry's mutex must be held.
	 */
	static Found declared_in_locked(Walk& walk, NameRegistry& names, ast::Node* where,
		InternedString package_path, InternedString name, Declaration*& found, IfChain** pending_insert = nullptr) {

		found = nullptr;
		auto iter = names.declarations.find(std::make_pair(package_path, name));
		if (iter != names.declarations.end()) {
			found = iter->second;
			return Found::DECLARATION;
		}
		if (!files_parsed_locked(names, package_path)) {
			park_locked(walk, names, name_key(package_path, name), where, name, nullptr);
			return Found::PARKED;
		}
		/*
		 * Another chain first: if the walk's own #if may declare it too, that cycle is less telling. An
		 * #insert may declare anything, so when only inserts may, a caller that takes pending_insert gets
		 * the first, and looks elsewhere first (docs/compilation.md, Code Values).
		 */
		const std::vector<IfChain*>& pending = names.progress[package_path].pending_chains;
		IfChain* insert_chain = nullptr;
		ast::Node* insert_reason = nullptr;
		for (int pass = 0; pass < 2; ++pass) {
			for (IfChain* chain : pending) {
				if ((chain == walk.chain) != (pass == 1)) {
					continue;
				}
				ast::Node* reason = find_in_chain(chain, name, Look::DEFINITION);
				if (reason == nullptr) {
					continue;
				}
				if (is_text(reason->value.value, "#insert")) {
					if (insert_chain == nullptr) {
						insert_chain = chain;
						insert_reason = reason;
					}
					continue;
				}
				park_locked(walk, names, chain_key(chain), where, name, reason);
				return Found::PARKED;
			}
		}
		if (insert_chain != nullptr) {
			if (pending_insert != nullptr) {
				*pending_insert = insert_chain;
				return Found::NOTHING;
			}
			park_locked(walk, names, chain_key(insert_chain), where, name, insert_reason);
			return Found::PARKED;
		}
		return Found::NOTHING;
	}

	/*
	 * An #if chain in the walk's file, not decided yet, with an import that may provide name (which
	 * is where in reason), or null. Imports are per file, so only the walk's file's chains count.
	 * The registry's mutex must be held.
	 */
	static IfChain* import_chain_locked(Walk& walk, NameRegistry& names, InternedString name,
		Look look, ast::Node*& reason) {

		// Another chain first, then the walk's own
		const std::vector<IfChain*>& pending = names.progress[walk.package_path].pending_chains;
		for (int pass = 0; pass < 2; ++pass) {
			for (IfChain* chain : pending) {
				if (chain->file.file_name != walk.file_name || (chain == walk.chain) != (pass == 1)) {
					continue;
				}
				reason = find_in_chain(chain, name, look);
				if (reason != nullptr) {
					return chain;
				}
			}
		}
		reason = nullptr;
		return nullptr;
	}

	// Checks a declaration has what need asks for, parking if not. The registry's mutex must be held.
	static Progress check_locked(Walk& walk, NameRegistry& names, ast::Node* where,
		Declaration* declaration, Need need) {

		walk.bindings[where] = declaration;
		// Pointers can refer to a declared type before it's resolved, but whether a VALUE, like
		// X :: Y, is a type at all is only known once it is
		if (need == Need::DECLARED && DeclarationKind::VALUE == declaration->kind) {
			need = Need::RESOLVED;
		}
		if (need == Need::RESOLVED && declaration->failed) {
			return Progress::FAILED; // already reported
		}
		if (need == Need::RESOLVED && !declaration->resolved) {
			park_locked(walk, names, resolved_key(declaration), where, declaration->name, nullptr);
			return Progress::PARKED;
		}
		return Progress::DONE;
	}

	/*
	 * Requires name, declared in package_path, to be declared, and with need RESOLVED, resolved.
	 * Parks the walk's work if it isn't yet.
	 */
	Progress require_in(Walk& walk, ast::Node* where, InternedString package_path,
		InternedString name, Need need) {

		NameRegistry& names = walk.executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);

		Declaration* declaration = nullptr;
		Found found = declared_in_locked(walk, names, where, package_path, name, declaration);
		if (Found::DECLARATION == found) {
			return check_locked(walk, names, where, declaration, need);
		}
		if (Found::PARKED == found) {
			return Progress::PARKED;
		}
		report_at(ErrorCode::E4008, walk.file_path, &walk.executor.program_info->made_nodes, where, std::string(std::string_view(*name)));
		return Progress::FAILED;
	}

	InternedString builtin_package() {
		return intern(std::string(BUILTIN_PACKAGE));
	}

	bool is_base_package(InternedString package_path) {
		return package_path != nullptr && std::string_view(*package_path).starts_with(BASE_PACKAGE_PREFIX);
	}

	bool is_compiler_provided(InternedString package_path) {
		return package_path != nullptr
			&& std::string_view(*package_path) == std::string(BASE_PACKAGE_PREFIX) + "builtin";
	}

	/*
	 * Looks name up in the packages the walk's file imports and the builtins, which every file
	 * imports (docs/packages.md, Name Collision), once the package itself is known not to declare it.
	 * found is the declaration, or null for a builtin or a name from base. The registry's mutex must
	 * be held.
	 *
	 * An #if chain in the file that isn't decided yet may add an import. If the name is found
	 * without it, that's used, and checked again once everything is decided (check_provisional_uses):
	 * a new import declaring it too makes it ambiguous, which stops compilation anyway. If it isn't
	 * found, the walk waits for the chain.
	 */
	static Progress require_from_imports_locked(Walk& walk, NameRegistry& names, ast::Node* where,
		InternedString name, Need need, Declaration*& found_declaration, IfChain* pending_insert = nullptr) {

		const bool builtin = is_builtin_name(name);
		found_declaration = nullptr;
		std::vector<Declaration*> found;
		bool imports_base = false;
		// An imported package's #insert that may declare it, waited for only if nothing else does
		IfChain* imported_insert = nullptr;
		if (walk.file != nullptr) {
			std::vector<InternedString> packages;
			{
				std::scoped_lock<std::mutex> imports_lock(walk.file->imports_mutex);
				for (ImportInfo* import : walk.file->imports) {
					if (import->resolved_path == nullptr) {
						continue; // missing, already reported
					}
					if (is_compiler_provided(import->resolved_path)) {
						imports_base = true;
						continue;
					}
					packages.push_back(import->resolved_path);
				}
			}
			for (InternedString package : packages) {
				Declaration* declaration = nullptr;
				IfChain* insert = nullptr;
				Found result = declared_in_locked(walk, names, where, package, name, declaration, &insert);
				if (Found::PARKED == result) {
					return Progress::PARKED;
				}
				if (Found::NOTHING == result && insert != nullptr && imported_insert == nullptr) {
					imported_insert = insert;
				}
				if (Found::DECLARATION == result
					&& std::find(found.begin(), found.end(), declaration) == found.end()) {
					found.push_back(declaration);
				}
			}
		}
		/*
		 * The package's own #insert may still declare it, and its own would win over every import: wait for that
		 * before calling it ambiguous, or whether it is would depend on which was done first
		 */
		if (found.size() + (builtin ? 1 : 0) > 1 && pending_insert != nullptr) {
			park_locked(walk, names, chain_key(pending_insert), where, name, pending_insert->branches.front());
			return Progress::PARKED;
		}
		if (found.size() + (builtin ? 1 : 0) > 1) {
			// Reported now, so not again once everything is decided
			std::erase_if(names.provisional_uses, [&](const ProvisionalUse& use) {
				return use.file == walk.file && use.name == name && use.line == where->value.line_number
					&& use.column == where->value.column_number;
			});
			report_at(ErrorCode::E4012, walk.file_path, &walk.executor.program_info->made_nodes, where,
				builtin
					? std::format("{} is a builtin, and declared by an imported package; qualify it (base. for the builtin)",
						std::string_view(*name))
					: std::format("{} is declared by more than one imported package; qualify it",
						std::string_view(*name)));
			return Progress::FAILED;
		}
		ast::Node* reason = nullptr;
		IfChain* chain = import_chain_locked(walk, names, name, Look::ANY_IMPORT, reason);
		// The package's own #insert may still declare it, and its own would win: wait for that (docs/compilation.md,
		// The Top Level). Builtins and base's names don't wait, so the code an #insert runs can use them
		if (!builtin && found.size() == 1 && pending_insert != nullptr && !is_base_package(found[0]->package_path)) {
			park_locked(walk, names, chain_key(pending_insert), where, name, pending_insert->branches.front());
			return Progress::PARKED;
		}
		if (builtin || found.size() == 1) {
			if ((chain != nullptr || pending_insert != nullptr || imported_insert != nullptr) && walk.file != nullptr) {
				names.provisional_uses.push_back(ProvisionalUse{ walk.file, name, walk.file_path,
					where->value.line_number, where->value.column_number,
					pending_insert != nullptr ? walk.package_path : nullptr });
			}
			if (builtin) {
				// Optional and Result are declared by base/builtin, like any generic type, once it's loaded
				Declaration* declared = nullptr;
				Found result = declared_in_locked(walk, names, where, builtin_package(), name, declared);
				if (Found::PARKED == result) {
					return Progress::PARKED;
				}
				if (Found::DECLARATION == result) {
					found_declaration = declared;
					return check_locked(walk, names, where, declared, need);
				}
				return Progress::DONE;
			}
			found_declaration = found[0];
			return check_locked(walk, names, where, found[0], need);
		}
		if (imports_base) {
			//TODO(ches) look the name up in the base packages the compiler provides, once it has them
			return Progress::DONE;
		}
		if (chain != nullptr) {
			park_locked(walk, names, chain_key(chain), where, name, reason);
			return Progress::PARKED;
		}
		// Not imported yet: what the package's #insert, or an imported package's, puts there may declare it
		if (pending_insert != nullptr || imported_insert != nullptr) {
			IfChain* waited = pending_insert != nullptr ? pending_insert : imported_insert;
			park_locked(walk, names, chain_key(waited), where, name, waited->branches.front());
			return Progress::PARKED;
		}
		report_at(ErrorCode::E4008, walk.file_path, &walk.executor.program_info->made_nodes, where, std::string(std::string_view(*name)));
		return Progress::FAILED;
	}

	// A name a file imports a package under, used while an #insert in its package may still declare it.
	static void provisional_import_locked(Walk& walk, NameRegistry& names, ast::Node* where, InternedString name) {
		if (walk.file != nullptr) {
			names.provisional_uses.push_back(ProvisionalUse{ walk.file, name, walk.file_path,
				where->value.line_number, where->value.column_number, walk.package_path });
		}
	}

	/*
	 * A name used unqualified in the walk's own file (docs/packages.md, Name Collision): a generic
	 * parameter, a declaration in this package, an imported package, or a name declared by exactly
	 * one of the file's imports and the builtins. The package's own declaration always wins, so a
	 * name it doesn't declare yet waits while it still may.
	 */
	/*
	 * Hygiene (docs/compilation.md, Macros): a name a macro wrote is looked up from the file the macro was
	 * written in, rather than where it's put. That file's walk, or null when it's this walk's own.
	 */
	static std::unique_ptr<Walk> home_walk(Walk& walk, const ast::Node* where) {
		ProgramInfo* program = walk.executor.program_info;
		const std::shared_ptr<const ast::Origin> origin = program->made_nodes.origin(where);
		if (origin == nullptr || origin->mark == 0) {
			return nullptr;
		}
		// The file whose path that is (file_path_of), however its separators are written
		auto normal = [](std::string_view path) { return std::filesystem::path(path).lexically_normal().generic_string(); };
		const std::string wanted = normal(origin->file);
		if (wanted == normal(walk.file_path)) {
			return nullptr;
		}
		std::scoped_lock<std::mutex> lock(program->packages_mutex);
		for (const auto& [package_path, package] : program->packages) {
			std::scoped_lock<std::mutex> files_lock(package->files_mutex);
			for (const auto& [file_name, file] : package->files) {
				const std::string path = file_path_of(package_path, file_name);
				if (normal(path) == wanted) {
					return std::make_unique<Walk>(Walk{ walk.executor, package_path, file_name, file, walk.owner, nullptr, path,
						walk.locals, {}, {}, {}, {} });
				}
			}
		}
		return nullptr;
	}

	// What the home walk bound, for the walk it stands in for.
	static Progress from_home(Walk& walk, const Walk& home, Progress progress) {
		for (const auto& [node, declaration] : home.bindings) {
			walk.bindings[node] = declaration;
		}
		return progress;
	}

	Progress require(Walk& walk, ast::Node* where, InternedString name, Need need) {
		if (std::unique_ptr<Walk> home = home_walk(walk, where)) {
			return from_home(walk, *home, require(*home, where, name, need));
		}
		if (name == nullptr || is_local(walk, name)) {
			return Progress::DONE;
		}
		NameRegistry& names = walk.executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		// A type declared in the function, the innermost first
		for (auto local = walk.local_types.rbegin(); local != walk.local_types.rend(); ++local) {
			if (*local->first == *name) {
				return check_locked(walk, names, where, local->second, need);
			}
		}

		Declaration* own = nullptr;
		IfChain* pending_insert = nullptr;
		Found found = declared_in_locked(walk, names, where, walk.package_path, name, own, &pending_insert);
		if (Found::DECLARATION == found) {
			return check_locked(walk, names, where, own, need);
		}
		if (Found::PARKED == found) {
			return Progress::PARKED;
		}
		if (imported_package(walk.file, name) != nullptr) {
			if (pending_insert != nullptr) {
				provisional_import_locked(walk, names, where, name);
			}
			return Progress::DONE;
		}
		Declaration* declaration = nullptr;
		return require_from_imports_locked(walk, names, where, name, need, declaration, pending_insert);
	}

	/*
	 * Whether head, the start of a qualified name like runtime.Fiber, is the name of a package the
	 * walk's file imports, which is in package (or null): parks while the package may still declare
	 * head itself, or an #if chain in the file may still import a package under that name.
	 */
	static Progress qualifier_package(Walk& walk, ast::Node* where, InternedString head,
		InternedString& package) {

		package = nullptr;
		NameRegistry& names = walk.executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);

		Declaration* own = nullptr;
		IfChain* pending_insert = nullptr;
		Found found = declared_in_locked(walk, names, where, walk.package_path, head, own, &pending_insert);
		if (Found::PARKED == found) {
			return Progress::PARKED;
		}
		if (Found::DECLARATION == found) {
			return Progress::DONE; // the package's own, like an enum
		}
		package = imported_package(walk.file, head);
		if (package != nullptr && pending_insert != nullptr) {
			provisional_import_locked(walk, names, where, head);
		}
		if (package == nullptr && !is_text(head, "base")) {
			ast::Node* reason = nullptr;
			IfChain* chain = import_chain_locked(walk, names, head, Look::IMPORT_NAMED, reason);
			if (chain == nullptr && pending_insert != nullptr) {
				chain = pending_insert;
				reason = pending_insert->branches.front();
			}
			if (chain != nullptr) {
				park_locked(walk, names, chain_key(chain), where, head, reason);
				return Progress::PARKED;
			}
		}
		return Progress::DONE;
	}

	/*
	 * A name, possibly qualified by a package, like Fiber or runtime.Fiber. qualifier is the
	 * IDENTIFIER after the DOT_ACCESS, or null.
	 */
	Progress require_qualified(Walk& walk, ast::Node* where, InternedString head,
		ast::Node* qualifier, Need need, bool& head_was_package) {

		head_was_package = false;
		if (std::unique_ptr<Walk> home = home_walk(walk, where)) {
			return from_home(walk, *home, require_qualified(*home, where, head, qualifier, need, head_was_package));
		}
		if (qualifier != nullptr && !is_local(walk, head)) {
			InternedString package = nullptr;
			Progress progress = qualifier_package(walk, where, head, package);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (package == nullptr && is_text(head, "base")) {
				// base.Result: the builtin, even where the package or an import declares Result
				bool declared_here = false;
				{
					NameRegistry& names = walk.executor.program_info->names;
					std::scoped_lock<std::mutex> lock(names.mutex);
					declared_here = names.declarations.contains(std::make_pair(walk.package_path, head));
				}
				if (!declared_here) {
					head_was_package = true;
					if (is_builtin_name(qualifier->value.value)) {
						NameRegistry& names = walk.executor.program_info->names;
						std::scoped_lock<std::mutex> lock(names.mutex);
						Declaration* declared = nullptr;
						Found result = declared_in_locked(walk, names, qualifier, builtin_package(),
							qualifier->value.value, declared);
						if (Found::PARKED == result) {
							return Progress::PARKED;
						}
						if (Found::DECLARATION == result) {
							return check_locked(walk, names, qualifier, declared, need);
						}
						return Progress::DONE;
					}
					report_at(ErrorCode::E4008, walk.file_path, &walk.executor.program_info->made_nodes, qualifier,
						std::format("base.{}", std::string_view(*qualifier->value.value)));
					return Progress::FAILED;
				}
			}
			if (package != nullptr) {
				head_was_package = true;
				if (is_compiler_provided(package)) {
					//TODO(ches) check members of base packages against the compiler's own table
					return Progress::DONE;
				}
				return require_in(walk, qualifier, package, qualifier->value.value, need);
			}
		}
		return require(walk, where, head, need);
	}

	static Progress walk_node(Walk& walk, ast::Node* node, Need need);

	static bool is_postfix_marker(const ast::Node* node) {
		return ast::NodeType::DOT_ACCESS == node->node_type
			|| ast::NodeType::PAREN_GROUP == node->node_type
			|| ast::NodeType::ARRAY_DIMENSION == node->node_type
			|| (ast::NodeType::UNARY_OPERATOR == node->node_type
				&& TokenType::OPERATOR_DEREFERENCE == node->value.type);
	}

	// Postfix operations after a value, like .member, (arguments), [index] and ^, from start.
	static Progress walk_postfix(Walk& walk, ast::Node* node, size_t start, Need need) {
		for (size_t i = start; i < node->children.size(); ++i) {
			ast::Node* child = node->children[i];
			if (ast::NodeType::DOT_ACCESS == child->node_type) {
				++i; // the member's name isn't looked up here
				continue;
			}
			// A macro call's arguments are code it's given, looked up where the macro puts them
			if (ast::NodeType::UNARY_OPERATOR == child->node_type && TokenType::OPERATOR_NOT == child->value.type
				&& child->children.empty()) {
				break;
			}
			if (is_postfix_marker(child)) {
				continue;
			}
			// An argument or index
			Progress progress = walk_node(walk, child, need);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		return Progress::DONE;
	}

	static Progress walk_identifier(Walk& walk, ast::Node* node, Need need) {
		ast::Node* qualifier = nullptr;
		if (node->children.size() >= 2
			&& ast::NodeType::DOT_ACCESS == node->children[0]->node_type
			&& ast::NodeType::IDENTIFIER == node->children[1]->node_type) {
			qualifier = node->children[1];
		}
		bool head_was_package = false;
		Progress progress = require_qualified(walk, node, node->value.value, qualifier, need,
			head_was_package);
		if (progress != Progress::DONE) {
			return progress;
		}
		return walk_postfix(walk, node, head_was_package ? 2 : 0, need);
	}

	// Pushes the names of a declaration's generic parameters, like [T] or [T, capacity: usize].
	static Progress push_generic_parameters(Walk& walk, ast::Node* generic_tag) {
		// Every name first, since a derived parameter's expression uses the others, like element_of(C)
		for (ast::Node* parameter : generic_tag->children) {
			if (ast::NodeType::DERIVED_PARAMETER == parameter->node_type) {
				walk.locals.push_back(parameter->value.value);
			}
		}
		for (ast::Node* parameter : generic_tag->children) {
			if (ast::NodeType::DERIVED_PARAMETER == parameter->node_type) {
				for (ast::Node* child : parameter->children) {
					Progress progress = walk_node(walk, child, Need::DECLARED);
					if (progress != Progress::DONE) {
						return progress;
					}
				}
				continue;
			}
			if (ast::NodeType::COLON == parameter->node_type && !parameter->children.empty()) {
				walk.locals.push_back(parameter->children[0]->value.value);
				for (size_t i = 1; i < parameter->children.size(); ++i) {
					Progress progress = walk_node(walk, parameter->children[i], Need::DECLARED);
					if (progress != Progress::DONE) {
						return progress;
					}
				}
			}
			else {
				walk.locals.push_back(parameter->value.value);
			}
		}
		return Progress::DONE;
	}

	static Progress walk_type(Walk& walk, ast::Node* node, Need need) {
		InternedString head = node->value.value;
		ast::Node* qualifier = nullptr;
		size_t first_child = 0;
		while (first_child < node->children.size()
			&& ast::NodeType::MUTABLE == node->children[first_child]->node_type) {
			++first_child;
		}
		if (first_child + 1 < node->children.size()
			&& ast::NodeType::DOT_ACCESS == node->children[first_child]->node_type) {
			qualifier = node->children[first_child + 1];
		}

		// Views and dynamic arrays hold a pointer to their elements
		Need head_need = need;
		for (ast::Node* child : node->children) {
			if (ast::NodeType::ARRAY_DIMENSION == child->node_type
				&& (child->children.empty()
					|| ast::NodeType::RANGE_ARRAY == child->children[0]->node_type)) {
				head_need = Need::DECLARED;
			}
		}
		bool head_was_package = false;
		Progress progress = require_qualified(walk, node, head, qualifier, head_need,
			head_was_package);
		if (progress != Progress::DONE) {
			return progress;
		}

		const Need argument_need = is_pointer_like(head) ? Need::DECLARED : need;
		for (ast::Node* child : node->children) {
			if (ast::NodeType::GENERIC_TAG == child->node_type) {
				for (ast::Node* argument : child->children) {
					progress = walk_node(walk, argument, argument_need);
					if (progress != Progress::DONE) {
						return progress;
					}
				}
			}
			else if (ast::NodeType::ARRAY_DIMENSION == child->node_type) {
				for (ast::Node* size : child->children) {
					// A named constant as a size has to have its value
					progress = walk_node(walk, size, Need::RESOLVED);
					if (progress != Progress::DONE) {
						return progress;
					}
				}
			}
		}
		return Progress::DONE;
	}

	// A literal of a type, like Pair[int, string].{1, "one"} or u8.[1, 2]
	static Progress walk_literal(Walk& walk, ast::Node* node, Need need) {
		ast::Node* qualifier = nullptr;
		if (node->children.size() >= 2
			&& ast::NodeType::DOT_ACCESS == node->children[0]->node_type
			&& ast::NodeType::IDENTIFIER == node->children[1]->node_type) {
			qualifier = node->children[1];
		}
		bool head_was_package = false;
		Progress progress = require_qualified(walk, node, node->value.value, qualifier, need,
			head_was_package);
		if (progress != Progress::DONE) {
			return progress;
		}
		for (ast::Node* child : node->children) {
			if (ast::NodeType::GENERIC_TAG == child->node_type) {
				for (ast::Node* argument : child->children) {
					progress = walk_node(walk, argument, need);
					if (progress != Progress::DONE) {
						return progress;
					}
				}
			}
			else if (ast::NodeType::LIST == child->node_type) {
				for (ast::Node* element : child->children) {
					progress = walk_node(walk, element, need);
					if (progress != Progress::DONE) {
						return progress;
					}
				}
			}
		}
		return Progress::DONE;
	}

	// A parameter or result: a COLON (names, then a type), or a bare type, possibly with = default
	static Progress walk_parameter(Walk& walk, ast::Node* node) {
		if (ast::NodeType::COLON == node->node_type) {
			for (size_t i = 1; i < node->children.size(); ++i) {
				Progress progress = walk_node(walk, node->children[i], Need::DECLARED);
				if (progress != Progress::DONE) {
					return progress;
				}
			}
			return Progress::DONE;
		}
		if (ast::NodeType::BINARY_OPERATOR == node->node_type && is_assign(node)) {
			for (ast::Node* child : node->children) {
				Progress progress = walk_parameter(walk, child);
				if (progress != Progress::DONE) {
					return progress;
				}
			}
			return Progress::DONE;
		}
		return walk_node(walk, node, Need::DECLARED);
	}

	// A function's signature only needs the names it uses declared. Its body waits for type checking.
	/*
	 * Several results, like (int, string) or (result: string, valid: bool). Named ones are stored
	 * flat, as each name, a COLON, then the type, so with any COLON only the node after each is a type.
	 */
	static Progress walk_results(Walk& walk, ast::Node* list) {
		bool has_names = false;
		for (ast::Node* child : list->children) {
			if (ast::NodeType::COLON == child->node_type) {
				has_names = true;
			}
		}
		for (size_t i = 0; i < list->children.size(); ++i) {
			ast::Node* child = list->children[i];
			if (ast::NodeType::COLON == child->node_type) {
				continue;
			}
			const bool is_type = !has_names
				|| ast::NodeType::FUNCTION == child->node_type
				|| (i > 0 && ast::NodeType::COLON == list->children[i - 1]->node_type);
			if (!is_type) {
				continue;
			}
			Progress progress = walk_node(walk, child, Need::DECLARED);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		return Progress::DONE;
	}

	static Progress walk_function(Walk& walk, ast::Node* node) {
		const size_t locals_before = walk.locals.size();
		bool seen_parameters = false;
		Progress progress = Progress::DONE;
		for (ast::Node* child : node->children) {
			if (ast::NodeType::GENERIC_TAG == child->node_type) {
				progress = push_generic_parameters(walk, child);
			}
			else if (ast::NodeType::LIST == child->node_type && !seen_parameters) {
				seen_parameters = true;
				for (ast::Node* parameter : child->children) {
					progress = walk_parameter(walk, parameter);
					if (progress != Progress::DONE) {
						break;
					}
				}
			}
			else if (ast::NodeType::LIST == child->node_type) {
				progress = walk_results(walk, child);
			}
			else if (ast::NodeType::DIRECTIVE == child->node_type
				|| ast::NodeType::BLOCK == child->node_type
				|| ast::NodeType::VOID == child->node_type) {
				continue;
			}
			else {
				progress = walk_parameter(walk, child);
			}
			if (progress != Progress::DONE) {
				break;
			}
		}
		walk.locals.resize(locals_before);
		return progress;
	}

	// A struct's fields are held by value, so their types need to be resolved, unless they're pointers.
	static Progress walk_struct(Walk& walk, ast::Node* node) {
		const size_t locals_before = walk.locals.size();
		Progress progress = insert_members(walk, node);
		if (progress != Progress::DONE) {
			return progress;
		}
		for (ast::Node* child : node->children) {
			if (ast::NodeType::GENERIC_TAG == child->node_type) {
				progress = push_generic_parameters(walk, child);
			}
			else if (ast::NodeType::DEFINITION == child->node_type) {
				// names, then the type, then = and a default value
				for (size_t i = 1; i < child->children.size(); ++i) {
					ast::Node* part = child->children[i];
					if (is_assign(part)) {
						continue;
					}
					progress = walk_node(walk, part, Need::RESOLVED);
					if (progress != Progress::DONE) {
						break;
					}
				}
			}
			else if (ast::NodeType::USING == child->node_type && !child->children.empty()) {
				// using Name, or using package.Name: the included struct is held by value
				bool head_was_package = false;
				ast::Node* head = child->children[0];
				ast::Node* qualifier = child->children.size() >= 3 ? child->children[2] : nullptr;
				progress = require_qualified(walk, head, head->value.value, qualifier,
					Need::RESOLVED, head_was_package);
			}
			if (progress != Progress::DONE) {
				break;
			}
		}
		walk.locals.resize(locals_before);
		return progress;
	}

	// A union's variants hold their payloads by value.
	static Progress walk_union(Walk& walk, ast::Node* node) {
		const size_t locals_before = walk.locals.size();
		Progress progress = insert_members(walk, node);
		if (progress != Progress::DONE) {
			return progress;
		}
		for (ast::Node* child : node->children) {
			if (ast::NodeType::GENERIC_TAG == child->node_type) {
				progress = push_generic_parameters(walk, child);
			}
			else if (ast::NodeType::PAREN_GROUP == child->node_type) {
				for (ast::Node* payload : child->children) {
					progress = walk_node(walk, payload, Need::RESOLVED);
					if (progress != Progress::DONE) {
						break;
					}
				}
			}
			if (progress != Progress::DONE) {
				break;
			}
		}
		walk.locals.resize(locals_before);
		return progress;
	}

	static Progress walk_children(Walk& walk, ast::Node* node, Need need) {
		for (ast::Node* child : node->children) {
			Progress progress = walk_node(walk, child, need);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		return Progress::DONE;
	}

	static Progress walk_node(Walk& walk, ast::Node* node, Need need) {
		const ast::NodeType type = node->node_type;
		// A type #insert put here is itself, with nothing to look up (docs/compilation.md, Code Values)
		if ((ast::NodeType::TYPE == type || ast::NodeType::IDENTIFIER == type) && node->type != nullptr) {
			return ast::NodeType::IDENTIFIER == type ? walk_postfix(walk, node, 0, need) : Progress::DONE;
		}
		if (ast::NodeType::IDENTIFIER == type) {
			return walk_identifier(walk, node, need);
		}
		if (ast::NodeType::TYPE == type) {
			return walk_type(walk, node, need);
		}
		if (ast::NodeType::STRUCT_LITERAL == type || ast::NodeType::ARRAY_LITERAL == type) {
			return walk_literal(walk, node, need);
		}
		if (ast::NodeType::ENUM_SHORTHAND == type) {
			return walk_postfix(walk, node, 0, need);
		}
		if (ast::NodeType::FUNCTION == type) {
			return walk_function(walk, node);
		}
		if (ast::NodeType::STRUCT == type) {
			return walk_struct(walk, node);
		}
		if (ast::NodeType::UNION == type) {
			return walk_union(walk, node);
		}
		if (ast::NodeType::ENUM == type) {
			Progress inserted = insert_members(walk, node);
			if (inserted != Progress::DONE) {
				return inserted;
			}
			// Members, with their values
			for (ast::Node* member : node->children) {
				if (ast::NodeType::IDENTIFIER == member->node_type) {
					Progress progress = walk_children(walk, member, Need::RESOLVED);
					if (progress != Progress::DONE) {
						return progress;
					}
				}
			}
			return Progress::DONE;
		}
		if (ast::NodeType::UNARY_OPERATOR == type) {
			// &x only needs x to exist
			return walk_children(walk, node,
				TokenType::SYM_AMPERSAND == node->value.type ? Need::DECLARED : need);
		}
		if (ast::NodeType::BINARY_OPERATOR == type) {
			if (is_assign(node) && node->children.size() == 2) {
				// A named argument or field: the name on the left isn't looked up
				return walk_node(walk, node->children[1], need);
			}
			return walk_children(walk, node, need);
		}
		if (ast::NodeType::BLOCK == type) {
			//TODO(ches) bodies are checked with their locals in type checking
			return Progress::DONE;
		}
		if (ast::NodeType::ANNOTATION == type
			|| ast::NodeType::DIRECTIVE == type
			|| ast::NodeType::LITERAL == type
			|| ast::NodeType::KEYWORD_ALIAS == type
			|| ast::NodeType::KEYWORD_DISTINCT == type
			|| ast::NodeType::UNINITIALIZED == type
			|| ast::NodeType::VOID == type
			|| ast::NodeType::UNDERSCORE == type
			|| ast::NodeType::RANGE_ARRAY == type) {
			return Progress::DONE;
		}
		return walk_children(walk, node, need);
	}

	Progress walk_names(Walk& walk, ast::Node* node, Need need) {
		return walk_node(walk, node, need);
	}

	/*
	 * A definition's names: the explicit type, before the separator, then the value after it. A generic
	 * alias's parameters, on its alias word, are names in what it names, like V in alias[V] Pair[string, V].
	 */
	static bool is_separator(const ast::Node* node);

	static Progress walk_definition(Walk& walk, ast::Node* definition) {
		const size_t locals_before = walk.locals.size();
		bool after_separator = false;
		Progress progress = Progress::DONE;
		for (size_t i = 1; i < definition->children.size() && Progress::DONE == progress; ++i) {
			ast::Node* child = definition->children[i];
			if (is_separator(child)) {
				after_separator = true;
				continue;
			}
			if (ast::NodeType::KEYWORD_ALIAS == child->node_type || ast::NodeType::KEYWORD_DISTINCT == child->node_type) {
				for (ast::Node* part : child->children) {
					if (ast::NodeType::GENERIC_TAG == part->node_type) {
						progress = push_generic_parameters(walk, part);
					}
				}
				continue;
			}
			progress = walk_node(walk, child, after_separator ? Need::RESOLVED : Need::DECLARED);
		}
		walk.locals.resize(locals_before);
		return progress;
	}

	static bool is_separator(const ast::Node* node) {
		return ast::NodeType::COLON == node->node_type
			|| (ast::NodeType::IDENTIFIER == node->node_type && is_assign(node));
	}

	// Whether a declared type is a function type, or an alias of one, that gives a parameter a default.
	static bool has_type_defaults(TypeInfo const* type) {
		TypeInfo const* base = get_base_type_or_alias(type);
		if (base == nullptr || TypeInfoVariant::FUNCTION != base->variant) {
			return false;
		}
		for (const FunctionInput& input : static_cast<TypeInfoFunction const*>(base)->input) {
			if (input.default_value != nullptr && !input.default_in_body) {
				return true;
			}
		}
		return false;
	}

	// The declarations of a DEFINITION's names, from the registry.
	static std::vector<Declaration*> declarations_of(NameRegistry& names,
		InternedString package_path, ast::Node* definition) {

		std::vector<Declaration*> result;
		ast::Node* names_node = definition->children[0];
		std::vector<ast::Node*> name_nodes;
		if (ast::NodeType::LIST == names_node->node_type) {
			for (ast::Node* child : names_node->children) {
				name_nodes.push_back(child);
			}
		}
		else {
			name_nodes.push_back(names_node);
		}
		std::scoped_lock<std::mutex> lock(names.mutex);
		for (ast::Node* name_node : name_nodes) {
			if (ast::NodeType::IDENTIFIER != name_node->node_type) {
				continue;
			}
			auto iter = names.declarations.find(std::make_pair(package_path, name_node->value.value));
			if (iter != names.declarations.end() && iter->second->node == definition) {
				result.push_back(iter->second);
			}
		}
		return result;
	}

	/*
	 * Marks declarations resolved, or failed, and wakes anything waiting for them, unless the work
	 * resolving them parked. Anything waiting on a failed one fails too, without another error.
	 */
	static Progress finish_resolving(WorkThreadData& executor,
		const std::vector<Declaration*>& declarations, Progress progress) {

		if (Progress::PARKED == progress) {
			return progress;
		}
		NameRegistry& names = executor.program_info->names;
		std::vector<Declaration*> bodies;
		std::vector<Declaration*> defaults;
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			for (Declaration* declaration : declarations) {
				if (Progress::DONE == progress) {
					declaration->resolved = true;
					// A function's body is checked once its signature is known
					if (DeclarationKind::FUNCTION == declaration->kind && declaration->value_type != nullptr
						&& function_body(declaration->generic != nullptr ? declaration->generic : declaration) != nullptr) {
						bodies.push_back(declaration);
					}
					// And a function type's defaults, where it's declared
					if (DeclarationKind::TYPE == declaration->kind && has_type_defaults(declaration->type_value)) {
						defaults.push_back(declaration);
					}
				}
				else {
					declaration->failed = true;
					// Its body won't be checked, so what waits for that can go on
					declaration->body_done = true;
					wake_locked(*executor.global_data, names, body_key(declaration));
				}
				wake_locked(*executor.global_data, names, resolved_key(declaration));
			}
		}
		for (Declaration* function : bodies) {
			executor.create_work(WorkType::TYPE_CHECK, WorkTarget(WorkTargetType::BODY, { .declaration = function }));
		}
		for (Declaration* type : defaults) {
			executor.create_work(WorkType::TYPE_CHECK, WorkTarget(WorkTargetType::TYPE_DEFAULTS, { .declaration = type }));
		}
		return progress;
	}

	Progress resolve_definition(WorkThreadData& executor, InternedString package_path,
		InternedString file_name, ast::Node* definition) {

		NameRegistry& names = executor.program_info->names;
		std::vector<Declaration*> declarations = declarations_of(names, package_path, definition);
		if (declarations.empty()) {
			// A duplicate, already reported
			return Progress::FAILED;
		}

		Walk walk{
			executor,
			package_path,
			file_name,
			declarations[0]->file,
			declarations[0],
			nullptr,
			file_path_of(package_path, file_name),
			{},
			{},
			{},
		};

		Progress walked = walk_definition(walk, definition);
		if (walked != Progress::DONE) {
			return finish_resolving(executor, declarations, walked);
		}
		// Then its types, from what each name resolved to
		Progress computed = compute_declaration(walk, declarations, definition);
		// A constrained generic function's body is checked once before any instance (docs/types.md, Checked Bodies)
		if (Progress::DONE == computed && DeclarationKind::FUNCTION == declarations[0]->kind) {
			start_early_check(walk, declarations[0]);
		}
		return finish_resolving(executor, declarations, computed);
	}

	Progress resolve_instance(WorkThreadData& executor, Declaration* instance) {
		Walk walk{
			executor,
			instance->package_path,
			instance->file_name,
			instance->file,
			instance,
			nullptr,
			file_path_of(instance->package_path, instance->file_name),
			{},
			{},
			{},
		};
		// A function or a type declared inside a function: like one at the top level, from its own definition
		walk.local_types = instance->local_types;
		// In a generic's instance, its generic parameters are names it sees, as in the generic's own body
		walk.generic_types = instance->outer_generic_types;
		walk.generic_values = instance->outer_generic_values;
		for (const auto& [name, type] : walk.generic_types) {
			walk.locals.push_back(intern(name));
		}
		for (const auto& [name, value] : walk.generic_values) {
			walk.locals.push_back(intern(name));
		}
		if (instance->generic == nullptr) {
			Progress walked = walk_definition(walk, instance->node);
			if (Progress::DONE == walked) {
				walked = compute_declaration(walk, { instance }, instance->node);
			}
			return finish_resolving(executor, { instance }, walked);
		}
		// The generic's own names, with its parameters as locals, then its types with them bound; its tree, or its own
		const Declaration* generic = instance->generic != nullptr ? instance->generic : instance;
		ast::Node* value = generic_node(instance->node != generic->node ? instance : generic);
		Progress progress = Progress::FAILED;
		if (is_early_instance(instance)) {
			Progress promised = promise_archetypes(walk, instance);
			if (promised != Progress::DONE) {
				return finish_resolving(executor, { instance }, promised);
			}
		}
		if (value != nullptr && (ast::NodeType::KEYWORD_ALIAS == value->node_type || ast::NodeType::KEYWORD_DISTINCT == value->node_type)) {
			// A generic alias: its parameters are on the alias word, and what it names comes after
			progress = walk_definition(walk, generic->node);
		}
		else if (value != nullptr) {
			progress = walk_node(walk, value, Need::RESOLVED);
		}
		if (Progress::DONE == progress) {
			progress = compute_instance(walk, instance);
		}
		return finish_resolving(executor, { instance }, progress);
	}

	Progress require_resolved(Walk& walk, ast::Node* where, Declaration* declaration, Need need) {
		NameRegistry& names = walk.executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		return check_locked(walk, names, where, declaration, need);
	}

	Progress require_complete(Walk& walk, ast::Node* where, TypeInfo* type) {
		if (type == nullptr || type->complete) {
			return Progress::DONE;
		}
		// A generic argument written with mut is laid out as what it aliases, once that is
		if (is_mutable_argument(type)) {
			auto alias = static_cast<TypeInfoAlias*>(type);
			Progress progress = require_complete(walk, where, alias->base_type);
			if (progress == Progress::DONE && alias->base_type->complete) {
				NameRegistry& names = walk.executor.program_info->names;
				std::scoped_lock<std::mutex> lock(names.types_mutex);
				if (!alias->complete) {
					lay_out_alias(alias);
				}
			}
			return progress;
		}
		NameRegistry& names = walk.executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		auto iter = names.type_declarations.find(type);
		if (iter == names.type_declarations.end()) {
			// Made complete by its own construction, like an array of complete elements
			return Progress::DONE;
		}
		return check_locked(walk, names, where, iter->second, Need::RESOLVED);
	}

	std::string constant_text(const ConstantValue& value) {
		if (ConstantValue::Kind::BOOLEAN == value.kind) {
			return value.boolean ? "true" : "false";
		}
		if (ConstantValue::Kind::INTEGER == value.kind) {
			return std::to_string(value.integer);
		}
		if (ConstantValue::Kind::FUNCTION == value.kind && value.function != nullptr) {
			return std::format("{}.{}", std::string_view(*value.function->package_path), std::string_view(*value.function->name));
		}
		if (ConstantValue::Kind::UNKNOWN == value.kind) {
			return value.member;
		}
		return "." + value.member;
	}

	Declaration* nested_declaration(Walk& walk, ast::Node* definition) {
		NameRegistry& names = walk.executor.program_info->names;
		Declaration* made = nullptr;
		// In a generic's instance, one for each instance, with its generic arguments
		std::string instance_key;
		for (const auto& [name, type] : walk.generic_types) {
			instance_key += std::format("{}={} ", name, static_cast<const void*>(get_base_type_or_alias(type)));
		}
		for (const auto& [name, value] : walk.generic_values) {
			instance_key += std::format("{}={} ", name, constant_text(value));
		}
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			auto iter = names.nested.find(std::make_pair(definition, instance_key));
			if (iter != names.nested.end()) {
				return iter->second;
			}
			made = &names.storage.emplace_back();
			made->name = definition->children.empty() ? nullptr : definition->children[0]->value.value;
			made->package_path = walk.package_path;
			made->file_name = walk.file_name;
			made->file = walk.file;
			made->node = definition;
			made->local_types = walk.local_types;
			made->outer_generic_types = walk.generic_types;
			made->outer_generic_values = walk.generic_values;
			classify_declaration(names, made);
			names.nested[std::make_pair(definition, instance_key)] = made;
		}
		walk.executor.create_work(WorkType::TYPE_CHECK, WorkTarget(WorkTargetType::INSTANCE, { .declaration = made }));
		return made;
	}

	bool inserts_code(const ast::Node* node) {
		if (node == nullptr) {
			return false;
		}
		if (ast::NodeType::DIRECTIVE == node->node_type && (is_text(node->value.value, "#insert") || is_text(node->value.value, "#expand"))) {
			return true;
		}
		// A macro call, name!(arguments)
		for (size_t i = 0; i + 1 < node->children.size(); ++i) {
			const ast::Node* child = node->children[i];
			if (ast::NodeType::IDENTIFIER == node->node_type && ast::NodeType::UNARY_OPERATOR == child->node_type
				&& TokenType::OPERATOR_NOT == child->value.type && child->children.empty()
				&& ast::NodeType::PAREN_GROUP == node->children[i + 1]->node_type) {
				return true;
			}
		}
		for (const ast::Node* child : node->children) {
			if (inserts_code(child)) {
				return true;
			}
		}
		return false;
	}

	// A copy of a tree, with where each node came from and what each #code quotes, for an instance of its own.
	static ast::Node* copy_tree(ProgramInfo* program, const ast::Node* node) {
		ast::Node* copy = program->made_nodes.make(node->node_type, node->value);
		copy->type = node->type;
		if (std::shared_ptr<const ast::Origin> origin = program->made_nodes.origin(node)) {
			program->made_nodes.set_origin(copy, origin);
		}
		if (const ast::Node* quoted = program->quotes.get(node)) {
			program->quotes.set(copy, quoted, program->quotes.file_of(node), program->quotes.from_caller(node));
		}
		for (const ast::Node* child : node->children) {
			copy->children.push_back(copy_tree(program, child));
		}
		return copy;
	}

	Declaration* instance_of(Walk& walk, Declaration* generic, const std::vector<TypeInfo*>& arguments,
		const std::vector<ConstantValue>& values) {

		// Aliases that aren't distinct are the same type, so the same instance; values by their text
		std::string key;
		std::string name = std::string(std::string_view(*generic->name)) + "[";
		for (size_t i = 0; i < arguments.size(); ++i) {
			const bool is_value = arguments[i] == nullptr && i < values.size();
			key += is_value ? "=" + constant_text(values[i])
				: std::format("{}{} ", is_mutable_argument(arguments[i]) ? "mut " : "",
					static_cast<const void*>(get_base_type_or_alias(arguments[i])));
			// An unknown value is its own generic's, like an archetype (docs/types.md, Checked Bodies)
			if (is_value && ConstantValue::Kind::UNKNOWN == values[i].kind) {
				key += std::format("@{} ", static_cast<const void*>(values[i].function));
			}
			// A function by its name alone, like HashMap[string, int, hash_string]
			const bool is_function = is_value && ConstantValue::Kind::FUNCTION == values[i].kind && values[i].function != nullptr;
			name += (i > 0 ? ", " : "") + (is_function ? std::string(std::string_view(*values[i].function->name))
				: is_value ? constant_text(values[i]) : to_string(arguments[i]));
		}
		name += "]";
		NameRegistry& names = walk.executor.program_info->names;
		Declaration* instance = nullptr;
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			auto iter = names.instances.find(std::make_pair(generic, key));
			if (iter != names.instances.end()) {
				return iter->second;
			}
			instance = &names.storage.emplace_back();
			instance->name = intern(name);
			instance->package_path = generic->package_path;
			instance->file_name = generic->file_name;
			instance->file = generic->file;
			// One declared in a function sees what its generic does there
			instance->local_types = generic->local_types;
			instance->outer_generic_types = generic->outer_generic_types;
			instance->outer_generic_values = generic->outer_generic_values;
			/*
			 * A function whose body inserts code, with #insert or a macro call, or a type whose members do, has a tree of
			 * its own for each instance, since inserting changes the tree in place (docs/compilation.md, Code Values)
			 */
			if ((DeclarationKind::FUNCTION == generic->kind || DeclarationKind::GENERIC_TYPE == generic->kind)
				&& inserts_code(generic->node)) {
				ProgramInfo* program = walk.executor.program_info;
				std::unique_lock<std::mutex> making = program->made_nodes.hold();
				instance->node = copy_tree(program, generic->node);
			}
			else {
				instance->node = generic->node;
			}
			instance->generic = generic;
			instance->generic_arguments = arguments;
			instance->generic_values = values;
			instance->generic_values.resize(arguments.size());
			classify_declaration(names, instance);
			names.instances[std::make_pair(generic, key)] = instance;
		}
		walk.executor.create_work(WorkType::TYPE_CHECK,
			WorkTarget(WorkTargetType::INSTANCE, { .declaration = instance }));
		return instance;
	}

	Progress builtin_generic(Walk& walk, ast::Node* where, std::string_view name, Declaration*& found) {
		return base_declaration(walk, where, "builtin", name, found);
	}

	Progress base_declaration(Walk& walk, ast::Node* where, std::string_view folder, std::string_view name,
		Declaration*& found) {

		NameRegistry& names = walk.executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		InternedString package = intern(std::string(BASE_PACKAGE_PREFIX) + std::string(folder));
		Found result = declared_in_locked(walk, names, where, package, intern(std::string(name)), found);
		if (Found::PARKED == result) {
			return Progress::PARKED;
		}
		if (Found::NOTHING == result) {
			report_at(ErrorCode::E4008, walk.file_path, &walk.executor.program_info->made_nodes, where, std::string(name));
			return Progress::FAILED;
		}
		return Progress::DONE;
	}

	static void report_not_constant(const std::string& file_path, ast::Node* node,
		std::string_view details) {
		report_error(ErrorCode::E4010, file_path, node->value.line_number,
			node->value.column_number, std::string(details));
	}

	static std::string architecture_name(ArchType architecture) {
		switch (architecture) {
			case ArchType::arm: return "arm";
			case ArchType::aarch64: return "arm64";
			case ArchType::aarch64_32: return "arm64";
			case ArchType::x86: return "x86";
			case ArchType::x86_64: return "x86_64";
		}
		return "";
	}

	static std::string os_name(OSType os) {
		switch (os) {
			case OSType::Win32: return "Windows";
			case OSType::Linux: return "Linux";
			case OSType::Darwin:
			case OSType::MacOSX: return "Mac";
			case OSType::UEFI: return "UEFI";
			case OSType::SlopOS: return "SlopOS";
			case OSType::UnknownOS:
			case OSType::FreeBSD:
			case OSType::NetBSD:
			case OSType::OpenBSD: return "None";
		}
		return "None";
	}

	static bool parse_integer(std::string_view text, int64_t& value) {
		std::string digits;
		for (char c : text) {
			if (c != '_') {
				digits.push_back(c);
			}
		}
		int base = 10;
		size_t start = 0;
		if (digits.size() > 2 && digits[0] == '0' && (digits[1] == 'x' || digits[1] == 'X')) {
			base = 16;
			start = 2;
		}
		else if (digits.size() > 2 && digits[0] == '0' && (digits[1] == 'b' || digits[1] == 'B')) {
			base = 2;
			start = 2;
		}
		if (start >= digits.size()) {
			return false;
		}
		char* end = nullptr;
		value = static_cast<int64_t>(std::strtoull(digits.c_str() + start, &end, base));
		return end != nullptr && *end == '\0';
	}

	static Progress evaluate(Walk& walk, ast::Node* node, ConstantValue& result);

	// Whether checking a constant's value found a call, so its value is worked out by running it.
	static bool calls_a_function(const CheckedBody* checked) {
		if (checked == nullptr) {
			return false;
		}
		for (const auto& [node, found] : checked->nodes) {
			if (found.called != nullptr) {
				return true;
			}
		}
		return false;
	}

	// What compile-time code gave, as a constant checking can use: an integer, a boolean or an enum member.
	static Progress constant_from_run(Walk& walk, ast::Node* where, const Evaluation& evaluation, ConstantValue& result) {
		TypeInfo const* type = get_base_type(evaluation.type);
		const std::vector<uint8_t>& bytes = evaluation.value.bytes;
		uint64_t raw = 0;
		std::memcpy(&raw, bytes.data(), std::min<size_t>(bytes.size(), sizeof(raw)));
		if (type != nullptr && TypeInfoVariant::BOOLEAN == type->variant) {
			result.kind = ConstantValue::Kind::BOOLEAN;
			result.boolean = raw != 0;
			return Progress::DONE;
		}
		if (type != nullptr && TypeInfoVariant::INTEGER == type->variant && type->size <= 8) {
			result.kind = ConstantValue::Kind::INTEGER;
			const size_t shift = 64 - type->size * 8;
			result.integer = static_cast<const TypeInfoInteger*>(type)->is_signed
				? static_cast<int64_t>(raw << shift) >> shift : static_cast<int64_t>(shift == 64 ? 0 : (raw << shift) >> shift);
			return Progress::DONE;
		}
		if (type != nullptr && TypeInfoVariant::ENUM == type->variant) {
			auto enumeration = static_cast<const TypeInfoEnum*>(type);
			for (size_t i = 0; i < enumeration->members.size(); ++i) {
				if (enumeration->values[i] == raw) {
					result.kind = ConstantValue::Kind::ENUM_MEMBER;
					result.member = std::string(std::string_view(*enumeration->members[i]));
					return Progress::DONE;
				}
			}
		}
		report_not_constant(walk.file_path, where,
			"only integers, booleans and enum members from compile-time code can be used here");
		return Progress::FAILED;
	}

	/*
	 * A constant whose value calls a function, worked out by running it (docs/compilation.md, Compile-Time
	 * Execution): the run is queued the first time it's needed, and the walk waits for it.
	 */
	Progress require_compile_time_runtime(Walk& walk, ast::Node* where) {
		// The context, and the structs type information is made of
		static constexpr std::pair<std::string_view, std::string_view> NEEDED[] = {
			{ "runtime", "CarrierBlock" }, { "runtime", "Context" }, { "runtime", "COMPILE_TIME_CONTEXT" },
			{ "compiler", "TypeInfo" }, { "compiler", "TypeInfoAlias" }, { "compiler", "TypeInfoArray" },
			{ "compiler", "TypeInfoEnum" }, { "compiler", "TypeInfoFloat" }, { "compiler", "TypeInfoFunction" },
			{ "compiler", "TypeInfoInteger" }, { "compiler", "TypeInfoPointer" }, { "compiler", "TypeInfoString" },
			{ "compiler", "TypeInfoStruct" }, { "compiler", "TypeInfoUnion" },
		};
		for (const auto& [folder, name] : NEEDED) {
			Declaration* found = nullptr;
			Progress progress = base_declaration(walk, where, folder, name, found);
			if (progress == Progress::DONE) {
				progress = require_resolved(walk, where, found, Need::RESOLVED);
			}
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		return Progress::DONE;
	}

	/*
	 * The value of compile-time code that's checked: its result, or the walk waits for it, queuing its run the
	 * first time it's needed.
	 */
	static Progress run_or_wait(Walk& walk, ast::Node* where, Evaluation* evaluation, InternedString name,
		ConstantValue& result) {

		NameRegistry& names = walk.executor.program_info->names;
		bool queue = false;
		bool parked = false;
		Evaluation::State state = Evaluation::State::WAITING;
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			state = evaluation->state;
			if (Evaluation::State::WAITING == state) {
				queue = !evaluation->queued;
				evaluation->queued = true;
				park_locked(walk, names, evaluation_key(evaluation), where, name, nullptr);
				parked = true;
			}
		}
		if (queue) {
			walk.executor.create_work(WorkType::EXECUTION, WorkTarget(WorkTargetType::EVALUATION, { .evaluation = evaluation }));
		}
		if (parked) {
			return Progress::PARKED;
		}
		if (Evaluation::State::FAILED == state) {
			return Progress::FAILED;
		}
		return constant_from_run(walk, where, *evaluation, result);
	}

	static Progress evaluate_by_running(Walk& walk, ast::Node* where, Declaration* declaration, ConstantValue& result) {
		Progress ready = require_compile_time_runtime(walk, where);
		if (ready != Progress::DONE) {
			return ready;
		}
		NameRegistry& names = walk.executor.program_info->names;
		Evaluation* evaluation = nullptr;
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			std::unique_ptr<Evaluation>& slot = names.evaluations[declaration];
			if (slot == nullptr) {
				slot = std::make_unique<Evaluation>();
				slot->node = definition_value(declaration->node);
				slot->type = declaration->value_type;
				slot->declaration = declaration;
				slot->checked = declaration->checked;
				slot->file_path = file_path_of(declaration->package_path, declaration->file_name);
			}
			evaluation = slot.get();
		}
		return run_or_wait(walk, where, evaluation, declaration->name, result);
	}

	// Whether a constant expression is compile-time code to run: #run, or a call like table_size().
	static bool runs_code(const ast::Node* node) {
		if (ast::NodeType::DIRECTIVE == node->node_type) {
			return is_text(node->value.value, "#run") && !node->children.empty();
		}
		// Builtins like size_of are worked out without running anything
		if (ast::NodeType::IDENTIFIER != node->node_type || is_builtin_name(node->value.value)) {
			return false;
		}
		for (const ast::Node* child : node->children) {
			if (ast::NodeType::PAREN_GROUP == child->node_type) {
				return true;
			}
		}
		return false;
	}

	// Compile-time code written in place, like #assert table_size() == 16: checked here, then run.
	static Progress evaluate_expression_by_running(Walk& walk, ast::Node* node, ConstantValue& result) {
		ast::Node* expression = ast::NodeType::DIRECTIVE == node->node_type ? node->children[0] : node;
		NameRegistry& names = walk.executor.program_info->names;
		Evaluation* evaluation = nullptr;
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			std::unique_ptr<Evaluation>& slot = names.evaluations[expression];
			if (slot == nullptr) {
				slot = std::make_unique<Evaluation>();
				slot->node = expression;
				slot->file_path = walk.file_path;
			}
			evaluation = slot.get();
		}
		if (evaluation->checked == nullptr) {
			auto checked = std::make_shared<CheckedBody>();
			TypeInfo* type = nullptr;
			Progress progress = check_compile_time_expression(walk, expression, checked.get(), type);
			if (progress != Progress::DONE) {
				return progress;
			}
			std::scoped_lock<std::mutex> lock(names.mutex);
			if (evaluation->checked == nullptr) {
				evaluation->type = type;
				evaluation->checked = checked;
			}
		}
		return run_or_wait(walk, node, evaluation, intern(std::string("#run")), result);
	}

	Progress code_to_insert(Walk& walk, ast::Node* insert, const ast::Node*& tree) {
		tree = nullptr;
		if (insert->children.empty()) {
			return Progress::FAILED;
		}
		ast::Node* expression = insert->children[0];
		NameRegistry& names = walk.executor.program_info->names;
		Evaluation* evaluation = nullptr;
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			std::unique_ptr<Evaluation>& slot = names.evaluations[expression];
			if (slot == nullptr) {
				slot = std::make_unique<Evaluation>();
				slot->node = expression;
				slot->file_path = walk.file_path;
				slot->value.wants_code = true;
			}
			evaluation = slot.get();
		}
		if (evaluation->checked == nullptr) {
			auto checked = std::make_shared<CheckedBody>();
			TypeInfo* type = nullptr;
			Progress progress = check_compile_time_expression(walk, expression, checked.get(), type);
			if (progress != Progress::DONE) {
				return progress;
			}
			Declaration* code = nullptr;
			progress = base_declaration(walk, insert, "compiler", "Code", code);
			if (progress == Progress::DONE) {
				progress = require_resolved(walk, insert, code, Need::RESOLVED);
			}
			if (progress != Progress::DONE) {
				return progress;
			}
			if (type == nullptr || get_base_type(type) != get_base_type(code->type_value)) {
				report_at(ErrorCode::E4015, walk.file_path, &walk.executor.program_info->made_nodes, expression,
					std::format("#insert puts a compiler.Code in place, not {}", type != nullptr ? to_string(type) : "nothing"));
				return Progress::FAILED;
			}
			std::scoped_lock<std::mutex> lock(names.mutex);
			if (evaluation->checked == nullptr) {
				evaluation->type = type;
				evaluation->checked = checked;
			}
		}
		bool queue = false;
		Evaluation::State state = Evaluation::State::WAITING;
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			state = evaluation->state;
			if (Evaluation::State::WAITING == state) {
				queue = !evaluation->queued;
				evaluation->queued = true;
				park_locked(walk, names, evaluation_key(evaluation), insert, intern(std::string("#insert")), nullptr);
			}
		}
		if (queue) {
			walk.executor.create_work(WorkType::EXECUTION, WorkTarget(WorkTargetType::EVALUATION, { .evaluation = evaluation }));
		}
		if (Evaluation::State::WAITING == state) {
			return Progress::PARKED;
		}
		if (Evaluation::State::FAILED == state) {
			return Progress::FAILED;
		}
		tree = evaluation->value.code;
		if (tree == nullptr) {
			if (!evaluation->value.code_reported) {
				report_at(ErrorCode::E4029, walk.file_path, &walk.executor.program_info->made_nodes, insert,
					"#insert's code gave a compiler.Code that holds no code");
			}
			return Progress::FAILED;
		}
		return Progress::DONE;
	}

	Progress insert_members(Walk& walk, ast::Node* node) {
		const ast::NodeType kind = node->node_type;
		const std::string_view word = ast::NodeType::STRUCT == kind ? "fields" : ast::NodeType::UNION == kind ? "variants" : "members";
		const std::string_view holder = ast::NodeType::STRUCT == kind ? "a struct's fields"
			: ast::NodeType::UNION == kind ? "a union's variants" : "an enum's members";
		ProgramInfo* program = walk.executor.program_info;
		for (size_t i = 0; i < node->children.size(); ++i) {
			ast::Node* insert = node->children[i];
			if (ast::NodeType::DIRECTIVE != insert->node_type || !is_text(insert->value.value, "#insert") || insert->children.empty()) {
				continue;
			}
			/*
			 * A generic type's instance inserts into a tree of its own, with its arguments; the generic's own tree is
			 * what each instance copies, so it's left as it is. Anything else in a generic shares its tree.
			 */
			const bool generic = std::any_of(node->children.begin(), node->children.end(),
				[](const ast::Node* child) { return ast::NodeType::GENERIC_TAG == child->node_type; });
			const Declaration* owner = walk.owner;
			const bool own_tree = owner != nullptr && owner->generic != nullptr && owner->node != owner->generic->node;
			if (generic && !own_tree) {
				return Progress::DONE;
			}
			if (!own_tree && !walk.generic_types.empty()) {
				report_at(ErrorCode::E4024, walk.file_path, &program->made_nodes, insert, "#insert in a generic type isn't supported yet");
				return Progress::FAILED;
			}
			const ast::Node* tree = nullptr;
			Progress progress = code_to_insert(walk, insert, tree);
			if (progress != Progress::DONE) {
				return progress;
			}
			const std::shared_ptr<const ast::Origin> origin = program->made_nodes.origin(insert);
			const ast::InsertionSite site{ origin != nullptr ? origin->file : walk.file_path, insert->value.line_number,
				insert->value.column_number };
			const ast::Node* inserted = copy_to_insert(program->made_nodes, program->quotes, tree, site, origin.get());
			if (inserted == nullptr) {
				return Progress::FAILED;
			}
			show_inserted(walk.executor.global_data->options, site, inserted, program->quotes);
			std::vector<ast::Node*> items;
			if (!named_items(inserted, kind, word, items)) {
				report_at(ErrorCode::E4014, walk.file_path, &program->made_nodes, insert, std::format(
					"#insert among {} puts {} there: quote them with #code {} {{ ... }}", holder, word, word));
				return Progress::FAILED;
			}
			auto at = node->children.erase(node->children.begin() + static_cast<std::ptrdiff_t>(i));
			node->children.insert(at, items.begin(), items.end());
			// What was inserted is looked at from where it is, since it may hold #inserts of its own
			--i;
		}
		return Progress::DONE;
	}

	/*
	 * One constraint, checked by running its #constraint function with these arguments at compile
	 * time (docs/types.md, Constraints): queued the first time they're asked for, and the walk waits.
	 * Once it's run, result is what its requirements found.
	 */
	Progress run_constraint(Walk& walk, ast::Node* where, const ConstraintRun& asked, const ConstraintRun*& result) {
		result = nullptr;
		Progress ready = require_compile_time_runtime(walk, where);
		if (ready == Progress::DONE) {
			ready = require_resolved(walk, where, asked.constraint, Need::RESOLVED);
		}
		if (ready != Progress::DONE) {
			return ready;
		}
		std::string key = std::format("{}", static_cast<const void*>(asked.constraint));
		for (size_t i = 0; i < asked.types.size(); ++i) {
			key += asked.types[i] != nullptr ? std::format(" {}{}", is_mutable_argument(asked.types[i]) ? "mut " : "",
				static_cast<const void*>(get_base_type_or_alias(asked.types[i])))
				: " =" + (i < asked.values.size() ? constant_text(asked.values[i]) : std::string());
		}
		NameRegistry& names = walk.executor.program_info->names;
		Evaluation* evaluation = nullptr;
		bool queue = false;
		Evaluation::State state = Evaluation::State::WAITING;
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			std::unique_ptr<Evaluation>& slot = names.constraint_evaluations[key];
			if (slot == nullptr) {
				slot = std::make_unique<Evaluation>();
				slot->constraint = std::make_shared<ConstraintRun>(asked);
				slot->declaration = asked.constraint;
				slot->file_path = file_path_of(asked.constraint->package_path, asked.constraint->file_name);
			}
			evaluation = slot.get();
			state = evaluation->state;
			if (Evaluation::State::WAITING == state) {
				queue = !evaluation->queued;
				evaluation->queued = true;
				park_locked(walk, names, evaluation_key(evaluation), where, asked.constraint->name, nullptr);
			}
		}
		if (queue) {
			walk.executor.create_work(WorkType::EXECUTION, WorkTarget(WorkTargetType::EVALUATION, { .evaluation = evaluation }));
		}
		if (Evaluation::State::WAITING == state) {
			return Progress::PARKED;
		}
		if (Evaluation::State::FAILED == state) {
			return Progress::FAILED;
		}
		result = evaluation->constraint.get();
		return Progress::DONE;
	}

	/*
	 * A derived parameter's value for one instance, like E = element_of(C) with C bound in walk: a
	 * type written in place, or the result of running the expression, a type or a constant. key says
	 * which instance, since the same expression gives each its own (docs/types.md, Derived Parameters).
	 */
	Progress evaluate_derived(Walk& walk, ast::Node* expression, const std::string& key, TypeInfo*& type, ConstantValue& value) {
		type = nullptr;
		if (!runs_code(expression)) {
			Progress named = walk_names(walk, expression, Need::DECLARED);
			if (named != Progress::DONE) {
				return named;
			}
			if (ast::NodeType::LITERAL == expression->node_type || ast::NodeType::BINARY_OPERATOR == expression->node_type
				|| ast::NodeType::UNARY_OPERATOR == expression->node_type) {
				return evaluate(walk, expression, value);
			}
			return type_of(walk, expression, Need::DECLARED, type);
		}
		Progress ready = require_compile_time_runtime(walk, expression);
		if (ready != Progress::DONE) {
			return ready;
		}
		NameRegistry& names = walk.executor.program_info->names;
		Evaluation* evaluation = nullptr;
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			std::unique_ptr<Evaluation>& slot = names.derived_evaluations[key];
			if (slot == nullptr) {
				slot = std::make_unique<Evaluation>();
				slot->node = expression;
				slot->file_path = walk.file_path;
			}
			evaluation = slot.get();
		}
		if (evaluation->checked == nullptr) {
			auto checked = std::make_shared<CheckedBody>();
			TypeInfo* result_type = nullptr;
			Progress progress = check_compile_time_expression(walk, expression, checked.get(), result_type);
			if (progress != Progress::DONE) {
				return progress;
			}
			std::scoped_lock<std::mutex> lock(names.mutex);
			if (evaluation->checked == nullptr) {
				evaluation->type = result_type;
				evaluation->checked = checked;
			}
		}
		TypeInfo const* result_type = get_base_type(evaluation->type);
		if (result_type != nullptr && TypeInfoVariant::TYPE == result_type->variant) {
			ConstantValue ignored;
			bool queue = false;
			Evaluation::State state = Evaluation::State::WAITING;
			{
				std::scoped_lock<std::mutex> lock(names.mutex);
				state = evaluation->state;
				if (Evaluation::State::WAITING == state) {
					queue = !evaluation->queued;
					evaluation->queued = true;
					park_locked(walk, names, evaluation_key(evaluation), expression, intern(std::string("a derived parameter")), nullptr);
				}
			}
			if (queue) {
				walk.executor.create_work(WorkType::EXECUTION, WorkTarget(WorkTargetType::EVALUATION, { .evaluation = evaluation }));
			}
			if (Evaluation::State::WAITING == state) {
				return Progress::PARKED;
			}
			if (Evaluation::State::FAILED == state) {
				return Progress::FAILED;
			}
			// A type value is its descriptor's address, which the compile-time data knows the type of
			uint64_t address = 0;
			std::memcpy(&address, evaluation->value.bytes.data(), std::min<size_t>(evaluation->value.bytes.size(), sizeof(address)));
			const auto& described = compile_time_data(walk.executor.program_info).described_types();
			auto found = described.find(static_cast<uintptr_t>(address));
			if (found == described.end()) {
				report_not_constant(walk.file_path, expression, "this doesn't give a type the compiler knows");
				return Progress::FAILED;
			}
			type = const_cast<TypeInfo*>(found->second);
			return Progress::DONE;
		}
		return run_or_wait(walk, expression, evaluation, intern(std::string("a derived parameter")), value);
	}

	Progress wait_for_body(Walk& walk, ast::Node* where, Declaration* function) {
		NameRegistry& names = walk.executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		if (function->body_done || function->failed) {
			return Progress::DONE;
		}
		park_locked(walk, names, body_key(function), where, function->name, nullptr);
		return Progress::PARKED;
	}

	void finish_body(WorkThreadData& executor, Declaration* function) {
		NameRegistry& names = executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		function->body_done = true;
		wake_locked(*executor.global_data, names, body_key(function));
	}

	void finish_evaluation(WorkThreadData& executor, Evaluation* evaluation, bool succeeded) {
		NameRegistry& names = executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		evaluation->state = succeeded ? Evaluation::State::DONE : Evaluation::State::FAILED;
		wake_locked(*executor.global_data, names, evaluation_key(evaluation));
	}

	Progress wait_for_declaration(WorkThreadData& executor, Evaluation* evaluation, Declaration* declaration) {
		NameRegistry& names = executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		const bool function = DeclarationKind::FUNCTION == declaration->kind;
		const bool done = function ? declaration->body_done : (declaration->resolved || declaration->failed);
		if (done) {
			return declaration->checked != nullptr ? Progress::DONE : Progress::FAILED;
		}
		Walk walk{
			executor,
			declaration->package_path,
			declaration->file_name,
			declaration->file,
			nullptr,
			nullptr,
			evaluation->file_path,
			{},
			{},
			{},
		};
		park_locked(walk, names, function ? body_key(declaration) : resolved_key(declaration), evaluation->node,
			declaration->name, nullptr);
		return Progress::PARKED;
	}

	// The value of a constant declaration, from the expression after its separator.
	static Progress evaluate_declaration(Walk& walk, ast::Node* where, Declaration* declaration,
		ConstantValue& result) {

		if (declaration->externally_initialized) {
			report_not_constant(walk.file_path, where, std::format(
				"{} is #externally_initialized, so its value isn't known until the program is loaded",
				std::string_view(*declaration->name)));
			return Progress::FAILED;
		}

		ast::Node* value = nullptr;
		bool after_separator = false;
		for (size_t i = 1; i < declaration->node->children.size(); ++i) {
			ast::Node* child = declaration->node->children[i];
			if (is_separator(child)) {
				after_separator = true;
				continue;
			}
			if (after_separator) {
				value = child;
				break;
			}
		}
		if (value == nullptr) {
			report_not_constant(walk.file_path, where, std::format("{} has no value",
				std::string_view(*declaration->name)));
			return Progress::FAILED;
		}
		// A function is a constant itself
		if (ast::NodeType::FUNCTION == value->node_type) {
			result.kind = ConstantValue::Kind::FUNCTION;
			result.function = declaration;
			return Progress::DONE;
		}
		// A value that calls a function comes from running it
		if (calls_a_function(declaration->checked.get())) {
			return evaluate_by_running(walk, where, declaration, result);
		}
		Walk inner{
			walk.executor,
			declaration->package_path,
			declaration->file_name,
			declaration->file,
			walk.owner,
			walk.chain,
			file_path_of(declaration->package_path, declaration->file_name),
			{},
			{},
			{},
		};
		return evaluate(inner, value, result);
	}

	static Progress evaluate_maybe_type(Walk& walk, ast::Node* node, ConstantValue& result);

	// size_of(T), align_of(T) or offset_of(T, member): what the compiler knows of a type's layout.
	static Progress evaluate_builtin_call(Walk& walk, ast::Node* node, ConstantValue& result) {
		const std::string name(std::string_view(*node->value.value));
		std::vector<ast::Node*> arguments(node->children.begin() + 1, node->children.end());
		// Whether two types are the same, following aliases that aren't distinct
		if (name == "types_are_aliases" && arguments.size() == 2) {
			ConstantValue a;
			ConstantValue b;
			Progress progress = evaluate_maybe_type(walk, arguments[0], a);
			if (progress == Progress::DONE) {
				progress = evaluate_maybe_type(walk, arguments[1], b);
			}
			if (progress != Progress::DONE) {
				return progress;
			}
			if (ConstantValue::Kind::TYPE != a.kind || ConstantValue::Kind::TYPE != b.kind) {
				report_not_constant(walk.file_path, node, "types_are_aliases needs two types");
				return Progress::FAILED;
			}
			result.kind = ConstantValue::Kind::BOOLEAN;
			result.boolean = same_type(a.type, b.type);
			return Progress::DONE;
		}
		// Whether a type's values are secrets (docs/memory.md, Secrets), as a generic asks of what it's given
		if (name == "is_secret_type" && arguments.size() == 1) {
			ConstantValue given;
			Progress progress = evaluate_maybe_type(walk, arguments[0], given);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (ConstantValue::Kind::TYPE != given.kind) {
				report_not_constant(walk.file_path, node, "is_secret_type needs a type");
				return Progress::FAILED;
			}
			result.kind = ConstantValue::Kind::BOOLEAN;
			result.boolean = is_secret_type(given.type);
			return Progress::DONE;
		}
		const bool known = name == "size_of" || name == "align_of" || name == "offset_of";
		if (!known || arguments.size() != (name == "offset_of" ? 2u : 1u)) {
			report_not_constant(walk.file_path, node, std::format("{} isn't something the compiler can compute here",
				name));
			return Progress::FAILED;
		}
		TypeInfo* type = nullptr;
		Progress progress = walk_node(walk, arguments[0], Need::RESOLVED);
		if (progress == Progress::DONE) {
			progress = type_of(walk, arguments[0], Need::RESOLVED, type);
		}
		if (progress == Progress::DONE) {
			progress = require_complete(walk, arguments[0], type);
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		result.kind = ConstantValue::Kind::INTEGER;
		if (name == "size_of") {
			result.integer = static_cast<int64_t>(type->size);
			return Progress::DONE;
		}
		if (name == "align_of") {
			result.integer = static_cast<int64_t>(type->alignment);
			return Progress::DONE;
		}
		TypeInfo const* base = get_base_type(type);
		if (base != nullptr && TypeInfoVariant::STRUCT == base->variant) {
			for (const StructMember& member : static_cast<TypeInfoStruct const*>(base)->members) {
				if (member.name != nullptr && *member.name == *arguments[1]->value.value) {
					result.integer = static_cast<int64_t>(member.offset);
					return Progress::DONE;
				}
			}
		}
		report_not_constant(walk.file_path, arguments[1], std::format("{} has no member {}", to_string(type),
			std::string_view(*arguments[1]->value.value)));
		return Progress::FAILED;
	}

	// A builtin constant, from the command line: TARGET_ARCH or OS.
	static Progress evaluate_builtin(Walk& walk, ast::Node* node, ConstantValue& result) {
		InternedString name = node->value.value;
		const Options* options = walk.executor.global_data->options;
		if (is_text(name, "TARGET_ARCH") && options != nullptr) {
			result.kind = ConstantValue::Kind::ENUM_MEMBER;
			result.member = architecture_name(options->architecture);
			return Progress::DONE;
		}
		if (is_text(name, "OS") && options != nullptr) {
			result.kind = ConstantValue::Kind::ENUM_MEMBER;
			result.member = os_name(options->os);
			return Progress::DONE;
		}
		report_not_constant(walk.file_path, node, std::format("{} isn't a known constant",
			std::string_view(*name)));
		return Progress::FAILED;
	}

	static Progress evaluate_name(Walk& walk, ast::Node* node, ConstantValue& result) {
		InternedString name = node->value.value;
		// A compile-time parameter, in an instance
		auto value = walk.generic_values.find(std::string(std::string_view(*name)));
		if (value != walk.generic_values.end() && node->children.empty()) {
			result = value->second;
			return Progress::DONE;
		}
		// size_of(T), align_of(T) and offset_of(T, member), which #assert uses
		if (!node->children.empty() && ast::NodeType::PAREN_GROUP == node->children[0]->node_type) {
			return evaluate_builtin_call(walk, node, result);
		}

		// Qualified, like compiler.Architecture.x86_64 or Mode.Fast: an enum member, by its name
		if (!node->children.empty()) {
			ast::Node* last = node->children.back();
			bool all_members = true;
			for (size_t i = 0; i < node->children.size(); ++i) {
				ast::NodeType expected = i % 2 == 0 ? ast::NodeType::DOT_ACCESS : ast::NodeType::IDENTIFIER;
				if (node->children[i]->node_type != expected) {
					all_members = false;
				}
			}
			if (!all_members || ast::NodeType::IDENTIFIER != last->node_type) {
				report_not_constant(walk.file_path, node, "only names and enum members are supported");
				return Progress::FAILED;
			}
			// The package's own declaration, like an enum, wins over an imported package's name
			InternedString package = nullptr;
			Progress head = qualifier_package(walk, node, name, package);
			if (head != Progress::DONE) {
				return head;
			}
			// A builtin constant, like base.OS
			if (package == nullptr && is_text(name, "base") && node->children.size() == 2) {
				return evaluate_builtin(walk, last, result);
			}
			// A constant in an imported package, like settings.KERNEL
			if (package != nullptr && node->children.size() == 2 && !is_compiler_provided(package)) {
				Progress progress = require_in(walk, last, package, last->value.value, Need::RESOLVED);
				if (progress != Progress::DONE) {
					return progress;
				}
				Declaration* declaration = nullptr;
				{
					NameRegistry& names = walk.executor.program_info->names;
					std::scoped_lock<std::mutex> lock(names.mutex);
					declaration = names.declarations[std::make_pair(package, last->value.value)];
				}
				return evaluate_declaration(walk, node, declaration, result);
			}
			result.kind = ConstantValue::Kind::ENUM_MEMBER;
			result.member = std::string(std::string_view(*last->value.value));
			return Progress::DONE;
		}

		// The same rules as any name (docs/packages.md, Name Collision)
		Declaration* declaration = nullptr;
		{
			NameRegistry& names = walk.executor.program_info->names;
			std::scoped_lock<std::mutex> lock(names.mutex);
			Found found = declared_in_locked(walk, names, node, walk.package_path, name, declaration);
			if (Found::PARKED == found) {
				return Progress::PARKED;
			}
			Progress progress = Found::DECLARATION == found
				? check_locked(walk, names, node, declaration, Need::RESOLVED)
				: require_from_imports_locked(walk, names, node, name, Need::RESOLVED, declaration);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		if (declaration == nullptr) {
			return evaluate_builtin(walk, node, result);
		}
		return evaluate_declaration(walk, node, declaration, result);
	}

	/*
	 * An operand that may be a type, where types are compared (== and != on them, types_are_aliases): a type named, as
	 * itself, or else any other constant.
	 */
	static Progress evaluate_maybe_type(Walk& walk, ast::Node* node, ConstantValue& result) {
		const bool plain_name = ast::NodeType::IDENTIFIER == node->node_type || (ast::NodeType::TYPE == node->node_type && node->children.empty());
		if (plain_name && node->children.empty()) {
			if (TypeInfo* builtin = builtin_type(std::string_view(*node->value.value))) {
				result.kind = ConstantValue::Kind::TYPE;
				result.type = builtin;
				return Progress::DONE;
			}
		}
		Declaration* declaration = nullptr;
		if (ast::NodeType::IDENTIFIER == node->node_type) {
			Progress progress = named_declaration_in(walk, node, declaration);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		if (declaration != nullptr && DeclarationKind::TYPE == declaration->kind && declaration->type_value != nullptr) {
			result.kind = ConstantValue::Kind::TYPE;
			result.type = declaration->type_value;
			return Progress::DONE;
		}
		return evaluate(walk, node, result);
	}

	static Progress evaluate_unary(Walk& walk, ast::Node* node, ConstantValue& result) {
		ConstantValue operand;
		Progress progress = evaluate(walk, node->children[0], operand);
		if (progress != Progress::DONE) {
			return progress;
		}
		const TokenType op = node->value.type;
		if (TokenType::OPERATOR_NOT == op && ConstantValue::Kind::BOOLEAN == operand.kind) {
			result.kind = ConstantValue::Kind::BOOLEAN;
			result.boolean = !operand.boolean;
			return Progress::DONE;
		}
		if (TokenType::OPERATOR_MINUS == op && ConstantValue::Kind::INTEGER == operand.kind) {
			result.kind = ConstantValue::Kind::INTEGER;
			result.integer = -operand.integer;
			return Progress::DONE;
		}
		// ~x, every bit flipped
		if (TokenType::OPERATOR_BITWISE_XOR == op && ConstantValue::Kind::INTEGER == operand.kind) {
			result.kind = ConstantValue::Kind::INTEGER;
			result.integer = ~operand.integer;
			return Progress::DONE;
		}
		report_not_constant(walk.file_path, node, "this operator isn't supported for that value");
		return Progress::FAILED;
	}

	static Progress evaluate_binary(Walk& walk, ast::Node* node, ConstantValue& result) {
		ConstantValue left;
		const TokenType op = node->value.type;
		// == and != compare types too
		const bool equality = TokenType::OPERATOR_EQUAL == op || TokenType::OPERATOR_NOT_EQUAL == op;
		Progress progress = equality ? evaluate_maybe_type(walk, node->children[0], left) : evaluate(walk, node->children[0], left);
		if (progress != Progress::DONE) {
			return progress;
		}
		// && and || only evaluate the right side when it decides the result
		if (ConstantValue::Kind::BOOLEAN == left.kind
			&& ((TokenType::OPERATOR_AND == op && !left.boolean)
				|| (TokenType::OPERATOR_OR == op && left.boolean))) {
			result = left;
			return Progress::DONE;
		}
		ConstantValue right;
		progress = equality ? evaluate_maybe_type(walk, node->children[1], right) : evaluate(walk, node->children[1], right);
		if (progress != Progress::DONE) {
			return progress;
		}
		if (left.kind != right.kind) {
			report_not_constant(walk.file_path, node, "the two sides have different kinds of value");
			return Progress::FAILED;
		}
		result.kind = ConstantValue::Kind::BOOLEAN;
		if (TokenType::OPERATOR_EQUAL == op || TokenType::OPERATOR_NOT_EQUAL == op) {
			// Types exactly: an alias is a type of its own
			bool equal = left.kind == ConstantValue::Kind::BOOLEAN ? left.boolean == right.boolean
				: left.kind == ConstantValue::Kind::INTEGER ? left.integer == right.integer
				: left.kind == ConstantValue::Kind::TYPE ? get_base_type_or_alias(left.type) == get_base_type_or_alias(right.type)
				: left.member == right.member;
			result.boolean = TokenType::OPERATOR_EQUAL == op ? equal : !equal;
			return Progress::DONE;
		}
		if (ConstantValue::Kind::BOOLEAN == left.kind
			&& (TokenType::OPERATOR_AND == op || TokenType::OPERATOR_OR == op)) {
			result.boolean = right.boolean;
			return Progress::DONE;
		}
		if (ConstantValue::Kind::INTEGER == left.kind) {
			const int64_t a = left.integer;
			const int64_t b = right.integer;
			if (TokenType::SYM_LT == op) { result.boolean = a < b; return Progress::DONE; }
			if (TokenType::OPERATOR_LESS_THAN_OR_EQUAL == op) { result.boolean = a <= b; return Progress::DONE; }
			if (TokenType::SYM_GT == op) { result.boolean = a > b; return Progress::DONE; }
			if (TokenType::OPERATOR_GREATER_THAN_OR_EQUAL == op) { result.boolean = a >= b; return Progress::DONE; }
			result.kind = ConstantValue::Kind::INTEGER;
			if (TokenType::OPERATOR_PLUS == op) { result.integer = a + b; return Progress::DONE; }
			if (TokenType::OPERATOR_MINUS == op) { result.integer = a - b; return Progress::DONE; }
			if (TokenType::OPERATOR_MULTIPLY == op) { result.integer = a * b; return Progress::DONE; }
			if (TokenType::OPERATOR_DIVIDE == op && b != 0) { result.integer = a / b; return Progress::DONE; }
			if ((TokenType::OPERATOR_MODULUS == op || TokenType::OPERATOR_REMAINDER == op) && b != 0) {
				result.integer = a % b;
				return Progress::DONE;
			}
			// The bitwise operators, and shifts by 0 to 63 bits
			if (TokenType::SYM_AMPERSAND == op) { result.integer = a & b; return Progress::DONE; }
			if (TokenType::OPERATOR_BITWISE_OR == op) { result.integer = a | b; return Progress::DONE; }
			if (TokenType::OPERATOR_BITWISE_XOR == op) { result.integer = a ^ b; return Progress::DONE; }
			const bool shift = TokenType::OPERATOR_LEFT_SHIFT == op || TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC == op
				|| TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL == op;
			if (shift && b >= 0 && b < 64) {
				const uint64_t bits = static_cast<uint64_t>(a);
				result.integer = TokenType::OPERATOR_LEFT_SHIFT == op ? static_cast<int64_t>(bits << b)
					: TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL == op ? static_cast<int64_t>(bits >> b) : a >> b;
				return Progress::DONE;
			}
		}
		report_not_constant(walk.file_path, node, "this operator isn't supported for those values");
		return Progress::FAILED;
	}

	/*
	 * A generic function named with its arguments, like hash_integer[int]: that instance, as a function
	 * constant, for a compile-time parameter like a HashMap's hash (docs/types.md, Values in Generic Lists).
	 */
	static Progress evaluate_instance(Walk& walk, ast::Node* node, ConstantValue& result) {
		ast::Node* qualifier = nullptr;
		ast::Node* tag = nullptr;
		for (size_t i = 0; i < node->children.size(); ++i) {
			ast::Node* child = node->children[i];
			if (ast::NodeType::DOT_ACCESS == child->node_type && i + 1 < node->children.size() && qualifier == nullptr) {
				qualifier = node->children[i + 1];
			}
			if (ast::NodeType::GENERIC_TAG == child->node_type) {
				tag = child;
			}
		}
		bool head_was_package = false;
		Progress progress = qualifier != nullptr
			? require_qualified(walk, node, node->value.value, qualifier, Need::DECLARED, head_was_package)
			: require(walk, node, node->value.value, Need::DECLARED);
		if (progress != Progress::DONE) {
			return progress;
		}
		auto bound = walk.bindings.find(head_was_package ? qualifier : node);
		Declaration* generic = bound != walk.bindings.end() ? bound->second : nullptr;
		ast::Node* function = generic != nullptr && DeclarationKind::FUNCTION == generic->kind ? generic_node(generic) : nullptr;
		bool is_generic = false;
		for (ast::Node* child : function != nullptr ? function->children : MyVector<ast::Node*>{}) {
			is_generic = is_generic || ast::NodeType::GENERIC_TAG == child->node_type;
		}
		if (!is_generic || tag == nullptr) {
			report_not_constant(walk.file_path, node, "only a generic function can be named with its arguments here");
			return Progress::FAILED;
		}
		std::vector<ast::Node*> nodes(tag->children.begin(), tag->children.end());
		for (ast::Node* argument : nodes) {
			progress = walk_node(walk, argument, Need::DECLARED);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		std::vector<TypeInfo*> arguments;
		std::vector<ConstantValue> values;
		progress = generic_type_arguments(walk, generic, nodes, [&](ast::Node* argument, TypeInfo*& type) {
			return argument_type_of(walk, argument, Need::DECLARED, type);
		}, arguments, values);
		if (progress != Progress::DONE) {
			return progress;
		}
		Declaration* instance = instance_of(walk, generic, arguments, values);
		progress = check_constraints(walk, node, generic, instance);
		if (progress == Progress::DONE) {
			progress = check_function_arguments(walk, node, generic, instance);
		}
		if (progress == Progress::DONE) {
			progress = require_resolved(walk, node, instance, Need::RESOLVED);
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		result.kind = ConstantValue::Kind::FUNCTION;
		result.function = instance;
		return Progress::DONE;
	}

	static Progress evaluate(Walk& walk, ast::Node* node, ConstantValue& result);

	/*
	 * The value of an enum member written Enum.Member or package.Enum.Member, which evaluates to the member's
	 * name alone, for a cast of it to an integer.
	 */
	static Progress enum_member_value(Walk& walk, ast::Node* node, int64_t& value) {
		const size_t count = node->children.size();
		if (count != 2 && count != 4) {
			report_not_constant(walk.file_path, node, "only an enum member written Enum.Member or package.Enum.Member can be cast here");
			return Progress::FAILED;
		}
		InternedString enum_name = 2 == count ? node->value.value : node->children[1]->value.value;
		InternedString member = node->children[count - 1]->value.value;
		Declaration* declaration = nullptr;
		NameRegistry& names = walk.executor.program_info->names;
		if (2 == count) {
			std::scoped_lock<std::mutex> lock(names.mutex);
			Found found = declared_in_locked(walk, names, node, walk.package_path, enum_name, declaration);
			if (Found::PARKED == found) {
				return Progress::PARKED;
			}
			Progress progress = Found::DECLARATION == found
				? check_locked(walk, names, node, declaration, Need::RESOLVED)
				: require_from_imports_locked(walk, names, node, enum_name, Need::RESOLVED, declaration);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		else {
			InternedString package = nullptr;
			Progress progress = qualifier_package(walk, node, node->value.value, package);
			if (progress == Progress::DONE && package != nullptr) {
				progress = require_in(walk, node->children[1], package, enum_name, Need::RESOLVED);
			}
			if (progress != Progress::DONE) {
				return progress;
			}
			if (package != nullptr) {
				std::scoped_lock<std::mutex> lock(names.mutex);
				declaration = names.declarations[std::make_pair(package, enum_name)];
			}
		}
		TypeInfo const* type = declaration != nullptr && DeclarationKind::TYPE == declaration->kind
			? get_base_type(declaration->type_value) : nullptr;
		if (type != nullptr && TypeInfoVariant::ENUM == type->variant) {
			auto enumeration = static_cast<TypeInfoEnum const*>(type);
			for (size_t i = 0; i < enumeration->members.size() && i < enumeration->values.size(); ++i) {
				if (*enumeration->members[i] == *member) {
					value = static_cast<int64_t>(enumeration->values[i]);
					return Progress::DONE;
				}
			}
		}
		report_not_constant(walk.file_path, node, std::format("{} isn't a member of an enum here", std::string_view(*member)));
		return Progress::FAILED;
	}

	// cast[T](x) of an integer, or an enum member, to an integer type: x as a T holds it, wrapped to T's width.
	static Progress evaluate_cast(Walk& walk, ast::Node* node, ConstantValue& result) {
		if (TokenType::KEYWORD_CAST != node->value.type || node->children.size() != 2) {
			report_not_constant(walk.file_path, node, "only cast is supported among the casts here");
			return Progress::FAILED;
		}
		Progress progress = walk_node(walk, node->children[0], Need::RESOLVED);
		TypeInfo* target = nullptr;
		if (progress == Progress::DONE) {
			progress = type_of(walk, node->children[0], Need::RESOLVED, target);
		}
		ConstantValue value;
		if (progress == Progress::DONE) {
			progress = evaluate(walk, node->children[1], value);
		}
		if (progress == Progress::DONE && ConstantValue::Kind::ENUM_MEMBER == value.kind
			&& ast::NodeType::IDENTIFIER == node->children[1]->node_type) {
			progress = enum_member_value(walk, node->children[1], value.integer);
			value.kind = ConstantValue::Kind::INTEGER;
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		TypeInfo const* integer = target != nullptr ? get_base_type(target) : nullptr;
		if (ConstantValue::Kind::INTEGER != value.kind || integer == nullptr || TypeInfoVariant::INTEGER != integer->variant) {
			report_not_constant(walk.file_path, node, "only an integer cast to an integer type is supported here");
			return Progress::FAILED;
		}
		result.kind = ConstantValue::Kind::INTEGER;
		result.integer = value.integer;
		const size_t bits = integer->size * 8;
		if (bits < 64) {
			const uint64_t mask = (uint64_t{ 1 } << bits) - 1;
			uint64_t wrapped = static_cast<uint64_t>(value.integer) & mask;
			if (static_cast<TypeInfoInteger const*>(integer)->is_signed && (wrapped >> (bits - 1)) != 0) {
				wrapped |= ~mask;
			}
			result.integer = static_cast<int64_t>(wrapped);
		}
		return Progress::DONE;
	}

	static Progress evaluate(Walk& walk, ast::Node* node, ConstantValue& result) {
		const TokenType token = node->value.type;
		if (TokenType::KEYWORD_TRUE == token || TokenType::KEYWORD_FALSE == token) {
			result.kind = ConstantValue::Kind::BOOLEAN;
			result.boolean = TokenType::KEYWORD_TRUE == token;
			return Progress::DONE;
		}
		const ast::NodeType type = node->node_type;
		if (ast::NodeType::LITERAL == type) {
			if (TokenType::LITERAL_INTEGER == token
				&& parse_integer(std::string_view(*node->value.value), result.integer)) {
				result.kind = ConstantValue::Kind::INTEGER;
				return Progress::DONE;
			}
			report_not_constant(walk.file_path, node, "only integer literals are supported");
			return Progress::FAILED;
		}
		if (ast::NodeType::ENUM_SHORTHAND == type) {
			result.kind = ConstantValue::Kind::ENUM_MEMBER;
			result.member = std::string(std::string_view(*node->value.value));
			return Progress::DONE;
		}
		// Whether constraints are satisfied, worked out by the checker rather than run (docs/types.md, Constraints)
		if (is_satisfies_call(walk, node)) {
			return evaluate_satisfies(walk, node, result);
		}
		if (runs_code(node)) {
			return evaluate_expression_by_running(walk, node, result);
		}
		// A generic function's instance, like hash_integer[int]
		if (ast::NodeType::IDENTIFIER == type || ast::NodeType::TYPE == type) {
			bool tagged = false;
			bool called = false;
			for (const ast::Node* child : node->children) {
				tagged = tagged || ast::NodeType::GENERIC_TAG == child->node_type;
				called = called || ast::NodeType::PAREN_GROUP == child->node_type;
			}
			if (tagged && !called) {
				return evaluate_instance(walk, node, result);
			}
		}
		// A name, or one in a type's position, like count in u8[count] or a function in HashMap[string, int, maps.hash_string]
		bool qualified_name = ast::NodeType::TYPE == type && !node->children.empty();
		for (size_t i = 0; i < node->children.size(); ++i) {
			qualified_name = qualified_name && node->children[i]->node_type == (i % 2 == 0 ? ast::NodeType::DOT_ACCESS : ast::NodeType::IDENTIFIER);
		}
		if (ast::NodeType::IDENTIFIER == type || (ast::NodeType::TYPE == type && (node->children.empty() || qualified_name))) {
			return evaluate_name(walk, node, result);
		}
		if (ast::NodeType::PAREN_GROUP == type && node->children.size() == 1) {
			return evaluate(walk, node->children[0], result);
		}
		if (ast::NodeType::UNARY_OPERATOR == type && node->children.size() == 1) {
			return evaluate_unary(walk, node, result);
		}
		if (ast::NodeType::BINARY_OPERATOR == type && node->children.size() == 2) {
			return evaluate_binary(walk, node, result);
		}
		if (ast::NodeType::CAST == type) {
			return evaluate_cast(walk, node, result);
		}
		report_not_constant(walk.file_path, node, "not supported in a compile-time constant yet");
		return Progress::FAILED;
	}

	Progress evaluate_in(Walk& walk, ast::Node* expression, ConstantValue& result) {
		return evaluate(walk, expression, result);
	}

	Progress named_declaration_in(Walk& walk, ast::Node* node, Declaration*& declaration) {
		declaration = nullptr;
		if (ast::NodeType::IDENTIFIER != node->node_type) {
			return Progress::DONE;
		}
		InternedString name = node->value.value;
		NameRegistry& names = walk.executor.program_info->names;
		if (node->children.empty()) {
			std::scoped_lock<std::mutex> lock(names.mutex);
			Found found = declared_in_locked(walk, names, node, walk.package_path, name, declaration);
			if (Found::PARKED == found) {
				return Progress::PARKED;
			}
			return Found::DECLARATION == found ? check_locked(walk, names, node, declaration, Need::RESOLVED)
				: require_from_imports_locked(walk, names, node, name, Need::RESOLVED, declaration);
		}
		// package.name
		if (node->children.size() != 2 || ast::NodeType::DOT_ACCESS != node->children[0]->node_type
			|| ast::NodeType::IDENTIFIER != node->children[1]->node_type) {
			return Progress::DONE;
		}
		InternedString package = nullptr;
		Progress progress = qualifier_package(walk, node, name, package);
		if (progress != Progress::DONE || package == nullptr || is_compiler_provided(package)) {
			return progress;
		}
		ast::Node* last = node->children[1];
		progress = require_in(walk, last, package, last->value.value, Need::RESOLVED);
		if (progress != Progress::DONE) {
			return progress;
		}
		std::scoped_lock<std::mutex> lock(names.mutex);
		declaration = names.declarations[std::make_pair(package, last->value.value)];
		return Progress::DONE;
	}

	Progress code_at_top_level(WorkThreadData& executor, IfChain* chain, FileInfo* file, const ast::Node*& tree) {
		Walk walk{
			executor,
			chain->file.package_path,
			chain->file.file_name,
			file,
			nullptr,
			chain,
			file_path_of(chain->file.package_path, chain->file.file_name),
			{},
			{},
			{},
		};
		return code_to_insert(walk, chain->branches.front(), tree);
	}

	Progress evaluate_condition(WorkThreadData& executor, IfChain* chain, FileInfo* file,
		ast::Node* expression, ConstantValue& result) {

		Walk walk{
			executor,
			chain->file.package_path,
			chain->file.file_name,
			file,
			nullptr,
			chain,
			file_path_of(chain->file.package_path, chain->file.file_name),
			{},
			{},
			{},
		};
		return evaluate(walk, expression, result);
	}

	/*
	 * The work a cycle step belongs to, as seen from the cycle's first step, where the error is
	 * reported: a declaration's name, or an #if chain as "this #if", "the #if on line N" in the same
	 * file, or with its file elsewhere.
	 */
	static std::string describe(const ParkedWork* parked, const ParkedWork* reported) {
		if (parked->owner != nullptr) {
			return std::string(std::string_view(*parked->owner->name));
		}
		if (parked->owner_chain == nullptr || parked->owner_chain->branches.empty()) {
			return std::string("an #if condition");
		}
		const IfChain* chain = parked->owner_chain;
		const ast::Node* first = chain->branches.front();
		const std::string_view directive = first->value.value != nullptr ? std::string_view(*first->value.value) : "#if";
		if (parked->owner_chain == reported->owner_chain) {
			return std::format("this {}", directive);
		}
		const std::string file_path = file_path_of(chain->file.package_path, chain->file.file_name);
		if (file_path == reported->file_path) {
			return std::format("the {} on line {}", directive, first->value.line_number);
		}
		return std::format("the {} at {}({},{})", directive, file_path, first->value.line_number,
			first->value.column_number);
	}

	/*
	 * One step of a cycle, after its subject: what it needs, and for an #if chain, what in that
	 * chain may provide it.
	 */
	static std::string describe_step(const ParkedWork* step, const ParkedWork* next,
		const ParkedWork* reported) {

		if (WaitKey::Kind::CHAIN_DECIDED != step->key.kind || step->reason == nullptr) {
			return std::format(" needs {}", describe(next, reported));
		}
		const bool is_import = ast::NodeType::IMPORT == step->reason->node_type;
		const std::string what = is_import
			? std::format("import {}, line {}", std::string_view(*import_local_name(step->reason)),
				step->reason->value.line_number)
			: std::format("line {}", step->reason->value.line_number);
		return std::format(" needs {}, which {} may {} ({})", std::string_view(*step->needed),
			next == step ? std::string("it") : describe(next, reported),
			is_import ? "import" : "declare", what);
	}

	void report_stall(GlobalThreadData& global_data) {
		NameRegistry& names = global_data.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);

		std::vector<ParkedWork*> all;
		for (auto& [key, list] : names.waiting) {
			for (ParkedWork& parked : list) {
				all.push_back(&parked);
			}
		}

		// Each parked work waits for one thing, so it has at most one successor: the parked
		// resolver of the declaration it waits for
		auto successor = [&names](ParkedWork* parked) -> ParkedWork* {
			if (WaitKey::Kind::DECLARATION_RESOLVED == parked->key.kind) {
				auto iter = names.parked_resolvers.find(parked->key.declaration);
				return iter == names.parked_resolvers.end() ? nullptr : iter->second;
			}
			if (WaitKey::Kind::CHAIN_DECIDED == parked->key.kind) {
				auto iter = names.parked_chains.find(parked->key.chain);
				return iter == names.parked_chains.end() ? nullptr : iter->second;
			}
			return nullptr;
		};

		size_t reported = 0;

		// Cycles: follow successors from each work, marking where each walk has been
		std::map<ParkedWork*, size_t> visited_in_walk;
		size_t walk_number = 0;
		for (ParkedWork* start : all) {
			if (visited_in_walk.contains(start)) {
				continue;
			}
			++walk_number;
			std::vector<ParkedWork*> path;
			ParkedWork* current = start;
			while (current != nullptr && !visited_in_walk.contains(current)) {
				visited_in_walk[current] = walk_number;
				path.push_back(current);
				current = successor(current);
			}
			if (current == nullptr || visited_in_walk[current] != walk_number) {
				continue; // ends somewhere already handled, or not in a cycle
			}
			// current is on this walk's path: from there to the end is a cycle
			std::vector<ParkedWork*> cycle(std::find(path.begin(), path.end(), current), path.end());
			std::string details = describe(cycle[0], cycle[0]);
			for (size_t i = 0; i < cycle.size(); ++i) {
				if (i > 0) {
					details += WaitKey::Kind::CHAIN_DECIDED == cycle[i - 1]->key.kind ? "; that #if" : ", which";
				}
				details += describe_step(cycle[i], cycle[(i + 1) % cycle.size()], cycle[0]);
			}
			details[0] = static_cast<char>(std::toupper(static_cast<unsigned char>(details[0])));
			report_error(ErrorCode::E4007, cycle[0]->file_path, cycle[0]->line, cycle[0]->column,
				details);
			++reported;
		}

		// Names nothing will ever declare
		std::set<std::tuple<std::string, uint32_t, uint32_t>> seen;
		for (ParkedWork* parked : all) {
			if (WaitKey::Kind::NAME_DECLARED != parked->key.kind) {
				continue;
			}
			auto where = std::make_tuple(parked->file_path, parked->line, parked->column);
			if (seen.contains(where)) {
				continue;
			}
			seen.insert(where);
			report_error(ErrorCode::E4008, parked->file_path, parked->line, parked->column,
				std::string(std::string_view(*parked->key.name)) + parked->note);
			++reported;
		}

		// Compile-time code waiting for a function whose checking needs that code's value
		for (ParkedWork* parked : all) {
			if (WaitKey::Kind::BODY_CHECKED != parked->key.kind) {
				continue;
			}
			report_error(ErrorCode::E4007, parked->file_path, parked->line, parked->column, std::format(
				"this compile-time code calls {}, which can't be checked until the code has run",
				std::string_view(*parked->key.declaration->name)));
			++reported;
		}

		if (reported == 0 && !all.empty()) {
			report_error(ErrorCode::E4011, all[0]->file_path, all[0]->line, all[0]->column,
				std::format("{} work items are waiting", all.size()));
		}

		names.waiting.clear();
		names.parked_resolvers.clear();
		names.parked_chains.clear();
		names.provisional_uses.clear();
		global_data.parked_work = 0;
	}

	void check_provisional_uses(GlobalThreadData& global_data) {
		NameRegistry& names = global_data.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);

		std::set<std::pair<FileInfo*, InternedString>> seen;
		for (const ProvisionalUse& use : names.provisional_uses) {
			if (!seen.insert(std::make_pair(use.file, use.name)).second) {
				continue;
			}
			size_t declared_by = is_builtin_name(use.name) ? 1 : 0;
			std::scoped_lock<std::mutex> imports_lock(use.file->imports_mutex);
			for (ImportInfo* import : use.file->imports) {
				if (import->resolved_path != nullptr && !is_compiler_provided(import->resolved_path)
					&& names.declarations.contains(std::make_pair(import->resolved_path, use.name))) {
					declared_by += 1;
				}
			}
			if (declared_by > 1) {
				report_error(ErrorCode::E4012, use.file_path, use.line, use.column, std::format(
					"{} is declared by more than one of the file's imports and the builtins, once its #if chains are decided; qualify it",
					std::string_view(*use.name)));
			}
			// Code an #insert put in the package declared it after all, where an import or a builtin was used
			else if (use.package_path != nullptr && names.declarations.contains(std::make_pair(use.package_path, use.name))) {
				report_error(ErrorCode::E4012, use.file_path, use.line, use.column, std::format(
					"{} is declared by code an #insert put in this package, and was used as the import or builtin it also names; rename one",
					std::string_view(*use.name)));
			}
		}
		names.provisional_uses.clear();
	}
}
