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
	/// Evaluates a compile-time constant expression in the walk's scope, like an array's count.
	/// </summary>
	Progress evaluate_in(Walk& walk, ast::Node* expression, ConstantValue& result);

	/// <summary>
	/// The instance of a generic type for these arguments, made (and its resolution started) the
	/// first time it's asked for.
	/// </summary>
	Declaration* instance_of(Walk& walk, Declaration* generic, const std::vector<TypeInfo*>& arguments);

	/// <summary>
	/// A builtin generic type from base/builtin, Optional or Result, waiting until it's declared.
	/// </summary>
	Progress builtin_generic(Walk& walk, ast::Node* where, std::string_view name, Declaration*& found);

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
}
