#pragma once

#include <functional>
#include <map>
#include <set>
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
		/// <summary>
		/// The generic parameters given with mut, like T in SharedPtr[mut Buffer]: ptr[T] can change what it
		/// points to (docs/types.md, Mutability).
		/// </summary>
		std::set<std::string> generic_mutable{};
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

	/// <summary>
	/// A generic argument written with mut, like mut Buffer: an alias of base that remembers it.
	/// </summary>
	TypeInfo* mutable_argument(Walk& walk, TypeInfo* base);
	bool is_mutable_argument(TypeInfo const* type);

	/// <summary>
	/// Whether an instance of a generic struct given mut becomes one given without it, like SharedPtr[mut Buffer]
	/// to SharedPtr[Buffer]: the parameters that differ are only pointed to, so the layout is the same.
	/// </summary>
	bool converts_to_read_only(TypeInfo const* from, TypeInfo const* to);

	/// <summary>
	/// A generic parameter bound in walk to argument: the type itself, with mut remembered by name.
	/// </summary>
	void bind_generic_type(Walk& walk, const std::string& name, TypeInfo* argument);
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
		const std::vector<TypeInfo*>& arguments, Need need, TypeInfo*& result, const std::vector<ConstantValue>& values = {});

	/// <summary>
	/// Whether a generic's parameter at index is a value, written name: type, rather than a type
	/// (docs/types.md, Values in Generic Lists), or a type with constraints, like T: Equatable.
	/// </summary>
	bool generic_parameter_is_value(NameRegistry& names, const Declaration* generic, size_t index);

	/*
	 * Constraints (constraints.cpp, docs/types.md, Constraints).
	 */

	/// <summary>
	/// Whether a declaration is a #constraint function.
	/// </summary>
	bool is_constraint_function(const Declaration* declaration);

	/// <summary>
	/// The #constraint function a name in a generic's constraints is, from the generic's package
	/// or its file's imports, or null if it isn't one. Takes the registry's lock.
	/// </summary>
	Declaration* constraint_named(NameRegistry& names, const Declaration* context, const ast::Node* node);
	Declaration* constraint_named(NameRegistry& names, InternedString package_path, FileInfo* file, const ast::Node* node);

	/// <summary>
	/// Whether node is a call to compiler.satisfies, which the walk's file can see.
	/// </summary>
	bool is_satisfies_call(Walk& walk, const ast::Node* node);

	/// <summary>
	/// compiler.satisfies(Hashable(Point) && Ordered(Point)): whether a constraint expression is
	/// satisfied, with the walk's generic parameters, reporting nothing. A boolean constant.
	/// </summary>
	Progress evaluate_satisfies(Walk& walk, ast::Node* node, ConstantValue& result);
	Progress evaluate_satisfies(Walk& walk, ast::Node* where, const std::vector<ast::Node*>& arguments, ConstantValue& result);

	/// <summary>
	/// Whether a declaration is one of base/compiler's, named name.
	/// </summary>
	bool is_compiler_function(const Declaration* declaration, std::string_view name);

	/// <summary>
	/// Whether a generic list's parameter, name: something, is a type with constraints rather than
	/// a value of a type: something combines constraints, or names a #constraint function.
	/// </summary>
	bool generic_parameter_is_constrained(NameRegistry& names, const Declaration* generic, const ast::Node* parameter);

	/// <summary>
	/// A derived parameter's value for one instance (names.cpp): a type, or a constant when type is null.
	/// </summary>
	Progress evaluate_derived(Walk& walk, ast::Node* expression, const std::string& key, TypeInfo*& type, ConstantValue& value);

	/// <summary>
	/// The derived parameters a generic's instance gets from the rest (constraints.cpp): each one
	/// not in bound or bound_values worked out in the generic's file, in whatever order they need.
	/// </summary>
	Progress bind_derived(Walk& walk, ast::Node* where, Declaration* generic, std::map<std::string, TypeInfo*>& bound,
		std::map<std::string, ConstantValue>& bound_values);

	/// <summary>
	/// Runs one constraint at compile time (names.cpp), waiting for it; result is what it found.
	/// </summary>
	Progress run_constraint(Walk& walk, ast::Node* where, const ConstraintRun& asked, const ConstraintRun*& result);

	/// <summary>
	/// Checks an instance's constraints where it's made, at where in walk's file: once for the
	/// instance, reporting what isn't satisfied at each place it's used, unless quiet. FAILED when
	/// they aren't.
	/// </summary>
	Progress check_constraints(Walk& walk, ast::Node* where, Declaration* generic, Declaration* instance, bool quiet = false);

	/*
	 * Checked bodies (early.cpp, docs/types.md, Checked Bodies): a constrained generic function's body
	 * is checked once, before any instance, with archetypes for its type parameters, which only have
	 * what its constraints promise.
	 */

	/// <summary>
	/// Whether a generic has constraints, in its generic list or a where clause.
	/// </summary>
	bool has_constraints(NameRegistry& names, const Declaration* generic);

	/// <summary>
	/// Whether a derived generic parameter, like E = element_of(C) or atomic = true, is a type, from how it's
	/// written: a type, or a call to a function returning one; anything else is a value.
	/// </summary>
	bool derived_parameter_is_type(NameRegistry& names, const Declaration* generic, const ast::Node* parameter);

	/// <summary>
	/// Makes a constrained generic function's archetypes and the instance of them whose body is
	/// checked before any other: once, when the generic is resolved.
	/// </summary>
	void start_early_check(Walk& walk, Declaration* generic);

	/// <summary>
	/// Whether an instance is its generic's early check, made of its own archetypes.
	/// </summary>
	bool is_early_instance(const Declaration* instance);

	/// <summary>
	/// Whether any of an instance's arguments is an archetype or an unknown value: one a checked
	/// body uses, whose own body isn't checked, since it's only ever an instance in name.
	/// </summary>
	bool has_archetype_arguments(const Declaration* instance);

	/// <summary>
	/// Gives the early instance's archetypes what the generic's constraints promise, before its body is checked.
	/// </summary>
	Progress promise_archetypes(Walk& walk, Declaration* instance);

	/// <summary>
	/// Whether the early check found its generic's body uses only what's promised; false until it's done.
	/// </summary>
	bool early_check_failed(NameRegistry& names, const Declaration* generic);

	/// <summary>
	/// A generic's early instance, if it has one, which its real instances wait for.
	/// </summary>
	Declaration* early_instance(NameRegistry& names, const Declaration* generic);

	/// <summary>
	/// Waits until a function's body has been checked, with or without errors (names.cpp).
	/// </summary>
	Progress wait_for_body(Walk& walk, ast::Node* where, Declaration* function);
	void finish_early_check(NameRegistry& names, const Declaration* instance, bool failed);

	/// <summary>
	/// For an instance a checked body uses with its archetypes: whether the body's own constraints
	/// promise what the instance's generic needs (E4033 when they don't).
	/// </summary>
	Progress prove_constraints(Walk& walk, ast::Node* where, Declaration* generic, Declaration* instance);

	/// <summary>
	/// Checks that each function an instance is given takes and gives what its parameter says, at
	/// where it's made (declarations.cpp, docs/types.md, Values in Generic Lists).
	/// </summary>
	Progress check_function_arguments(Walk& walk, ast::Node* where, Declaration* generic, Declaration* instance);

	/// <summary>
	/// A generic type's arguments: for a parameter that's a type, the type type_of gives; for one
	/// that's a value, a null type and the compile-time value of the argument.
	/// </summary>
	Progress generic_type_arguments(Walk& walk, const Declaration* generic, const std::vector<ast::Node*>& nodes,
		const std::function<Progress(ast::Node*, TypeInfo*&)>& type_of, std::vector<TypeInfo*>& arguments,
		std::vector<ConstantValue>& values);

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
