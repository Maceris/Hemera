#pragma once

#include <map>
#include <string>
#include <vector>

#include "front_end/names.h"

namespace hemera {

	/*
	 * Shared by the name walker (names.cpp) and the type evaluator (declarations.cpp), which works
	 * out a declaration's types once its names are resolved.
	 */

	/*
	 * Where a walk is: its package and file, the declaration it resolves or the #if chain it decides
	 * (or neither), and the generic parameters in scope.
	 */
	struct Walk {
		WorkThreadData& executor;
		InternedString package_path;
		InternedString file_name;
		FileInfo* file;
		Declaration* owner;
		IfChain* chain;
		std::string file_path;
		std::vector<InternedString> locals;
		/// <summary>
		/// The declaration each name the walk looked up resolved to, by the node it's used at
		/// (for a qualified name, its last part). Builtins and generic parameters aren't here.
		/// </summary>
		std::map<const ast::Node*, Declaration*> bindings;
		/// <summary>
		/// In an instance of a generic type, the type given for each generic parameter.
		/// </summary>
		std::map<std::string, TypeInfo*> generic_types;
		/// <summary>
		/// In an instance of a generic function, the value given for each compile-time parameter.
		/// </summary>
		std::map<std::string, ConstantValue> generic_values{};
	};

	/// <summary>
	/// Requires a declaration to be resolved, when need is RESOLVED, parking the walk's work until
	/// it is.
	/// </summary>
	Progress require_resolved(Walk& walk, ast::Node* where, Declaration* declaration, Need need);

	/// <summary>
	/// Requires a type to be complete, its layout known, parking the walk's work until the
	/// declaration it belongs to is resolved.
	/// </summary>
	Progress require_complete(Walk& walk, ast::Node* where, TypeInfo* type);

	/// <summary>
	/// Waits until what compile-time code runs with is resolved: base/runtime's CarrierBlock, Context and
	/// COMPILE_TIME_CONTEXT (docs/compilation.md, Compile-Time Execution).
	/// </summary>
	Progress require_compile_time_runtime(Walk& walk, ast::Node* where);

	/// <summary>
	/// Evaluates a compile-time constant expression in the walk's scope, like an array's count.
	/// </summary>
	Progress evaluate_in(Walk& walk, ast::Node* expression, ConstantValue& result);

	/// <summary>
	/// The instance of a generic type for these arguments, made (and its resolution started) the
	/// first time it's asked for.
	/// </summary>
	Declaration* instance_of(Walk& walk, Declaration* generic, const std::vector<TypeInfo*>& arguments,
		const std::vector<ConstantValue>& values = {});

	/// <summary>
	/// The constant a compile-time value is, as text, like 16 or .Fast.
	/// </summary>
	std::string constant_text(const ConstantValue& value);

	/// <summary>
	/// A builtin generic type from base/builtin, Optional or Result, waiting until it's declared.
	/// </summary>
	Progress builtin_generic(Walk& walk, ast::Node* where, std::string_view name, Declaration*& found);

	/// <summary>
	/// A declaration in a package of base, like runtime's Context, waiting until it's declared.
	/// </summary>
	Progress base_declaration(Walk& walk, ast::Node* where, std::string_view folder, std::string_view name,
		Declaration*& found);

	/*
	 * Name lookup (names.cpp, docs/packages.md), recording each declaration found in walk.bindings.
	 * They park the walk's work until what they need is there.
	 */

	/// <summary>
	/// The package a file imports under local_name, or null.
	/// </summary>
	InternedString imported_package(FileInfo* file, InternedString local_name);

	/// <summary>
	/// A name used unqualified, by the rules of docs/packages.md, Name Collision.
	/// </summary>
	Progress require(Walk& walk, ast::Node* where, InternedString name, Need need);

	/// <summary>
	/// A name declared in a particular package, like runtime.Fiber's Fiber.
	/// </summary>
	Progress require_in(Walk& walk, ast::Node* where, InternedString package_path, InternedString name,
		Need need);

	/// <summary>
	/// A name, possibly qualified by a package: qualifier is the IDENTIFIER after the dot, or null.
	/// head_was_package says whether head named a package rather than a declaration.
	/// </summary>
	Progress require_qualified(Walk& walk, ast::Node* where, InternedString head, ast::Node* qualifier,
		Need need, bool& head_was_package);

	/// <summary>
	/// Looks up every name a node uses, like a type's in a function body, so type_of can follow them.
	/// </summary>
	Progress walk_names(Walk& walk, ast::Node* node, Need need);

	/*
	 * Types (declarations.cpp), the same object each time they're asked for.
	 */

	/// <summary>
	/// The type a type expression is, in either position: a TYPE node, or a value like ptr[int].
	/// </summary>
	Progress type_of(Walk& walk, ast::Node* node, Need need, TypeInfo*& result);

	TypeInfo* pointer_to(Walk& walk, TypeInfo* base, bool is_mutable, bool is_relative, size_t size);
	TypeInfo* array_of(Walk& walk, TypeInfo* element, ArrayType array_type, size_t count);
	Progress optional_of(Walk& walk, ast::Node* where, TypeInfo* type, Need need, TypeInfo*& result);

	/// <summary>
	/// A FUNCTION node's type, the same object for the same signature.
	/// </summary>
	Progress function_type(Walk& walk, ast::Node* node, TypeInfo*& result);

	/// <summary>
	/// The instance of a generic type for these arguments, resolved when need asks.
	/// </summary>
	Progress instance_type(Walk& walk, ast::Node* where, Declaration* generic,
		const std::vector<TypeInfo*>& arguments, Need need, TypeInfo*& result);

	/// <summary>
	/// Makes a type the program's registry owns, which lives as long as the program does.
	/// </summary>
	template<typename T, typename... Arguments>
	T* make_type(NameRegistry& names, Arguments&&... arguments) {
		T* type = new T(std::forward<Arguments>(arguments)...);
		std::scoped_lock<std::mutex> lock(names.types_mutex);
		names.owned_types.emplace_back(type);
		return type;
	}

	/// <summary>
	/// Works out what a declaration is, and its types, once every name it uses is resolved
	/// (docs/types.md): a struct's members and layout, an enum's values, a function's signature,
	/// a constant's type. Waits for types it holds by value to be complete.
	/// </summary>
	Progress compute_declaration(Walk& walk, const std::vector<Declaration*>& declarations,
		ast::Node* definition);

	/// <summary>
	/// The same for an instance of a generic type, with its generic parameters bound.
	/// </summary>
	Progress compute_instance(Walk& walk, Declaration* instance);

	/// <summary>
	/// Makes the TypeInfo a type declaration has from when it's declared, and sets its kind, from
	/// its syntax.
	/// </summary>
	void classify_declaration(NameRegistry& names, Declaration* declaration);

	/// <summary>
	/// The node after a definition's separator (:: or : type :), its value, or null.
	/// </summary>
	ast::Node* definition_value(ast::Node* definition);

	/// <summary>
	/// What a generic declaration's instances are made from: its struct, union or function, which
	/// for a function without a body (---) is its declared type.
	/// </summary>
	ast::Node* generic_node(const Declaration* generic);
}
