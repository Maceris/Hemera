#pragma once

#include <atomic>
#include <cstdint>
#include <list>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

#include "memory/allocator.h"
#include "parser/ast_types.h"

namespace hemera {

	struct FileInfo;
	struct FileLocation;
	struct GlobalThreadData;
	struct IfChain;
	struct PackageInfo;
	struct ProgramInfo;
	struct Work;
	struct WorkThreadData;

	/// <summary>
	/// The resolved path of an import from base. Base is the interface to what the compiler provides,
	/// so its packages are built into the compiler rather than read from disk (base_sources.h): an
	/// import from base resolves to this prefix plus the package's folder, like "<base>/runtime".
	/// </summary>
	constexpr std::string_view BASE_PACKAGE_PREFIX = "<base>/";

	/// <summary>
	/// base/builtin, whose names are the compiler's own. Only its generic types, Optional and
	/// Result, are declared from its source, since their instances are made like any other's.
	/// </summary>
	constexpr std::string_view BUILTIN_PACKAGE = "<base>/builtin";

	/// <summary>
	/// BUILTIN_PACKAGE, interned.
	/// </summary>
	InternedString builtin_package();

	/// <summary>
	/// Whether a package's resolved path is a package of base.
	/// </summary>
	bool is_base_package(InternedString package_path);

	/// <summary>
	/// Whether a package's names are the compiler's own, with nothing to load: base/builtin.
	/// </summary>
	bool is_compiler_provided(InternedString package_path);

	/// <summary>
	/// The path of a source file, for error messages: on disk, or like "<base>/runtime/core.hsc".
	/// </summary>
	std::string file_path_of(InternedString package_path, InternedString file_name);

	/// <summary>
	/// A top-level declaration: one name of a top-level definition, in a package.
	/// </summary>
	/// <summary>
	/// What a declaration is, as far as its syntax says.
	/// </summary>
	enum class DeclarationKind : uint8_t {
		/// <summary>
		/// A struct, union, enum, alias or function type. Its TypeInfo exists from when it's
		/// declared, so pointers can refer to it before its layout is known.
		/// </summary>
		TYPE,
		/// <summary>
		/// A struct or union with generic parameters, a type only with its arguments.
		/// </summary>
		GENERIC_TYPE,
		/// <summary>
		/// A function, with a body or ---.
		/// </summary>
		FUNCTION,
		/// <summary>
		/// A constant, or a name for something else, like X :: Y, which is a type when Y is one.
		/// </summary>
		VALUE,
	};

	/// <summary>
	/// A compile-time constant value, for #if conditions.
	/// </summary>
	struct ConstantValue {
		enum class Kind : uint8_t {
			BOOLEAN,
			INTEGER,
			/// <summary>
			/// An enum member, by name, like .x86_64.
			/// </summary>
			ENUM_MEMBER,
		};
		Kind kind;
		bool boolean = false;
		int64_t integer = 0;
		std::string member;
	};

	/// <summary>
	/// What kind of literal an untyped constant is, like C :: 5, which takes the type it's used as.
	/// </summary>
	enum class Untyped : uint8_t {
		NONE,
		INTEGER,
		FLOAT,
		STRING,
		BOOLEAN,
	};

	struct Declaration {
		InternedString name = nullptr;
		/// <summary>
		/// The canonical path of the package it's declared in.
		/// </summary>
		InternedString package_path = nullptr;
		InternedString file_name = nullptr;
		FileInfo* file = nullptr;
		/// <summary>
		/// The DEFINITION node.
		/// </summary>
		ast::Node* node = nullptr;
		/// <summary>
		/// The work resolving it, which is what waiting on it waits for.
		/// </summary>
		Work* resolver = nullptr;
		/// <summary>
		/// Every name it needs is declared, and every declaration it needs resolved is resolved.
		/// </summary>
		bool resolved = false;
		/// <summary>
		/// Resolving it failed, and reported why. What needs it resolved fails too, without
		/// reporting it again.
		/// </summary>
		bool failed = false;
		DeclarationKind kind = DeclarationKind::VALUE;
		/// <summary>
		/// The type it is, for a TYPE, or a VALUE that turns out to name a type. Complete once
		/// it's resolved.
		/// </summary>
		TypeInfo* type_value = nullptr;
		/// <summary>
		/// The type of its value, for a function or a constant, once it's resolved; null for an
		/// untyped constant, like C :: 5, or one whose type comes from type checking its value.
		/// </summary>
		TypeInfo* value_type = nullptr;
		/// <summary>
		/// For an instance of a generic type, like Pair[int, string]: the generic declaration, and
		/// the types given for its parameters, in order. Its node is the generic's.
		/// </summary>
		Declaration* generic = nullptr;
		/// <summary>
		/// One per generic parameter: its type, or null for a compile-time value (docs/types.md,
		/// Compile-Time Parameters), which is in generic_values at the same place.
		/// </summary>
		std::vector<TypeInfo*> generic_arguments;
		std::vector<ConstantValue> generic_values;
		/// <summary>
		/// Marked #externally_initialized (docs/directives.md): its value is only the image's
		/// initial contents, so it can't be read at compile time.
		/// </summary>
		bool externally_initialized = false;
		/// <summary>
		/// From #section(name), the output section to put it in, or null.
		/// </summary>
		InternedString section = nullptr;
		/// <summary>
		/// For a constant without a type, what kind of literal it is.
		/// </summary>
		Untyped untyped = Untyped::NONE;
	};

	/// <summary>
	/// How much of a name a reference needs.
	/// </summary>
	enum class Need : uint8_t {
		/// <summary>
		/// That the name is declared: references through pointers, views, &amp;x, and
		/// function signatures.
		/// </summary>
		DECLARED,
		/// <summary>
		/// That the declaration is resolved too: constant values, #if conditions, and
		/// fields held by value, whose size depends on it.
		/// </summary>
		RESOLVED,
	};

	/// <summary>
	/// What parked work is waiting for.
	/// </summary>
	struct WaitKey {
		enum class Kind : uint8_t {
			/// <summary>
			/// A name to be declared in a package. Also woken once all the package's files are
			/// parsed, so lookups waiting for that look again.
			/// </summary>
			NAME_DECLARED,
			/// <summary>
			/// A declaration to be resolved.
			/// </summary>
			DECLARATION_RESOLVED,
			/// <summary>
			/// An #if chain to be decided, and the branch it picks processed.
			/// </summary>
			CHAIN_DECIDED,
		};
		Kind kind;
		InternedString package_path;
		InternedString name;
		Declaration* declaration;
		IfChain* chain;

		bool operator<(const WaitKey& other) const {
			return std::tie(kind, package_path, name, declaration, chain)
				< std::tie(other.kind, other.package_path, other.name, other.declaration, other.chain);
		}
	};

	/// <summary>
	/// Work that is waiting for something, and why, for error messages.
	/// </summary>
	struct ParkedWork {
		Work* work;
		WaitKey key;
		/// <summary>
		/// The declaration this work resolves, or null for other work.
		/// </summary>
		Declaration* owner;
		/// <summary>
		/// The #if chain this work decides, or null for other work.
		/// </summary>
		IfChain* owner_chain;
		/// <summary>
		/// The name it was looking up.
		/// </summary>
		InternedString needed;
		/// <summary>
		/// For CHAIN_DECIDED, what in the chain may provide the name: a definition or an import.
		/// </summary>
		ast::Node* reason;
		std::string file_path;
		uint32_t line;
		uint16_t column;
	};

	/// <summary>
	/// What can still declare names in a package: listing its files, parsing each one, and the #if
	/// chains not yet decided. A name the package doesn't declare yet may still be declared by these,
	/// which would take precedence over an import's (docs/packages.md, Name Collision).
	/// </summary>
	struct PackageProgress {
		/// <summary>
		/// The package's IMPORT work has started.
		/// </summary>
		bool started = false;
		/// <summary>
		/// Listing the files, and parsing each.
		/// </summary>
		uint32_t files_pending = 0;
		std::vector<IfChain*> pending_chains;
	};

	/// <summary>
	/// A name a file used from an import or the builtins while an #if chain in that file, with imports
	/// in its branches, wasn't decided yet: once everything is, it's checked again, since an import
	/// that chain added may declare it too, which would make it ambiguous.
	/// </summary>
	struct ProvisionalUse {
		FileInfo* file;
		InternedString name;
		std::string file_path;
		uint32_t line;
		uint16_t column;
	};

	/// <summary>
	/// Every top-level declaration in the program, and the work waiting on names and declarations.
	/// One mutex covers both, so checking for something and waiting for it can't miss it arriving.
	/// </summary>
	struct NameRegistry {
		std::mutex mutex;
		/// <summary>
		/// Owns every declaration, at a stable address.
		/// </summary>
		std::list<Declaration> storage;
		std::map<std::pair<InternedString, InternedString>, Declaration*> declarations;
		std::map<InternedString, PackageProgress> progress;
		std::vector<ProvisionalUse> provisional_uses;
		std::map<WaitKey, std::list<ParkedWork>> waiting;
		/// <summary>
		/// The parked work resolving each declaration, and deciding each #if chain, if it's parked,
		/// for building the wait graph.
		/// </summary>
		std::map<Declaration*, ParkedWork*> parked_resolvers;
		std::map<IfChain*, ParkedWork*> parked_chains;
		/// <summary>
		/// Each instance of a generic type, by the generic and its arguments.
		/// </summary>
		std::map<std::pair<Declaration*, std::string>, Declaration*> instances;
		/// <summary>
		/// The declaration each declared type belongs to, for waiting on its layout.
		/// </summary>
		std::map<const TypeInfo*, Declaration*> type_declarations;
		/// <summary>
		/// Every type made while compiling, besides the builtins.
		/// </summary>
		std::mutex types_mutex;
		std::vector<std::unique_ptr<TypeInfo>> owned_types;
		/// <summary>
		/// Types made from others, like ptr[int] or int[4], by what they're made of, so each is one
		/// object. Guarded by types_mutex.
		/// </summary>
		std::map<std::string, TypeInfo*> derived_types;
	};

	/// <summary>
	/// The result of evaluating something that may have to wait.
	/// </summary>
	enum class Progress : uint8_t {
		DONE,
		/// <summary>
		/// The work parked, waiting for something. It runs again from the start when woken.
		/// </summary>
		PARKED,
		/// <summary>
		/// It failed, and reported why.
		/// </summary>
		FAILED,
	};

	/// <summary>
	/// The names declared by base/builtin, which every file can use without importing anything.
	/// </summary>
	bool is_builtin_name(InternedString name);

	/// <summary>
	/// All of them, for checking against base/builtin.
	/// </summary>
	std::span<const std::string_view> builtin_names();

	/// <summary>
	/// Registers each name of a top-level DEFINITION node, waking anything waiting for them.
	/// Reports a duplicate declaration in the same package.
	/// </summary>
	/// <returns>The declarations, one per name.</returns>
	std::vector<Declaration*> declare(WorkThreadData& executor, InternedString package_path,
		InternedString file_name, FileInfo* file, ast::Node* definition);

	/// <summary>
	/// Records that listing a package's files, or parsing one, has started or finished. Once the last
	/// finishes, anything waiting on the package's names looks again.
	/// </summary>
	void begin_file_work(WorkThreadData& executor, InternedString package_path);
	void end_file_work(WorkThreadData& executor, InternedString package_path);

	/// <summary>
	/// Records an #if chain that isn't decided yet, or that it's decided and its branch processed,
	/// waking anything waiting for it.
	/// </summary>
	void begin_if_chain(WorkThreadData& executor, IfChain* chain);
	void end_if_chain(WorkThreadData& executor, IfChain* chain);

	/// <summary>
	/// Resolves an instance of a generic type, like Pair[int, string]: its members' types, with
	/// the generic parameters bound to its arguments, and its layout.
	/// </summary>
	Progress resolve_instance(WorkThreadData& executor, Declaration* instance);

	/// <summary>
	/// Checks that every name a top-level definition refers to is declared, and that the
	/// declarations it needs resolved are, then marks its names resolved and wakes anything
	/// waiting for them. Function bodies aren't checked yet.
	/// </summary>
	Progress resolve_definition(WorkThreadData& executor, InternedString package_path,
		InternedString file_name, ast::Node* definition);

	/// <summary>
	/// Evaluates an #if chain's condition, a compile-time constant expression.
	/// </summary>
	Progress evaluate_condition(WorkThreadData& executor, IfChain* chain, FileInfo* file,
		ast::Node* expression, ConstantValue& result);

	/// <summary>
	/// Called once no work is left but some is still parked, so nothing can ever resume:
	/// reports each cycle and each name that's never declared, and releases the parked work.
	/// </summary>
	void report_stall(GlobalThreadData& global_data);

	/// <summary>
	/// Called once all work is done: reports names used from an import or the builtins that an
	/// import added later by an #if makes ambiguous.
	/// </summary>
	void check_provisional_uses(GlobalThreadData& global_data);

	/// <summary>
	/// The file a work target refers to, or null.
	/// </summary>
	FileInfo* find_file(ProgramInfo* program_info, InternedString package_path,
		InternedString file_name);
}
