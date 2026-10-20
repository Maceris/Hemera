#pragma once

#include <filesystem>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#include "front_end/walk.h"

namespace hemera {

	/*
	 * Type checking of expressions and statements (checking.cpp): function bodies, constants'
	 * values, and parameters' defaults (docs/operators.md, docs/control_flow.md, docs/functions.md).
	 */

	/// <summary>
	/// What an expression is.
	/// </summary>
	enum class ValueKind : uint8_t {
		/// <summary>
		/// A value of type.
		/// </summary>
		VALUE,
		/// <summary>
		/// A type, like int or Pair[int, string], used where a value can be: size_of(int).
		/// </summary>
		TYPE,
		/// <summary>
		/// Literals that take the type they're used as: 5, 0.5, "text", true.
		/// </summary>
		UNTYPED_INTEGER,
		UNTYPED_FLOAT,
		UNTYPED_STRING,
		UNTYPED_BOOLEAN,
		/// <summary>
		/// null, which any pointer, cstring or optional can be.
		/// </summary>
		NULL_VALUE,
		/// <summary>
		/// No value: a call to a function without results, or void.
		/// </summary>
		NOTHING,
		/// <summary>
		/// A call's several results.
		/// </summary>
		RESULTS,
		/// <summary>
		/// An imported package, before .Name.
		/// </summary>
		PACKAGE,
		/// <summary>
		/// A function that's generic, before its call binds it.
		/// </summary>
		GENERIC_FUNCTION,
		/// <summary>
		/// A builtin function, like size_of.
		/// </summary>
		BUILTIN_FUNCTION,
		/// <summary>
		/// A union's variant, like Shape.Circle, before its values.
		/// </summary>
		VARIANT,
		/// <summary>
		/// Something already reported as an error: anything goes with it, so one mistake gives one error.
		/// </summary>
		POISONED,
	};

	struct Value {
		ValueKind kind = ValueKind::POISONED;
		/// <summary>
		/// For VALUE, its type; for TYPE, the type it is; for VARIANT, the union.
		/// </summary>
		TypeInfo* type = nullptr;
		/// <summary>
		/// A location: a variable, field, element or what a pointer points to, which & can take.
		/// </summary>
		bool is_location = false;
		/// <summary>
		/// A location that can be assigned to.
		/// </summary>
		bool is_mutable = false;
		/// <summary>
		/// The context or part of it, which can never be changed (docs/control_flow.md).
		/// </summary>
		bool is_context = false;
		/// <summary>
		/// A call to a #never_returns function.
		/// </summary>
		bool never_returns = false;
		std::vector<TypeInfo*> results;
		/// <summary>
		/// What a name referred to, for a GENERIC_FUNCTION, or a VALUE that's a function.
		/// </summary>
		Declaration* declaration = nullptr;
		/// <summary>
		/// For PACKAGE, its path; for BUILTIN_FUNCTION, its name.
		/// </summary>
		InternedString name = nullptr;
		/// <summary>
		/// For VARIANT, which one.
		/// </summary>
		size_t variant = 0;
		/// <summary>
		/// Generic arguments given explicitly, like f[int], before the call.
		/// </summary>
		std::vector<TypeInfo*> generic_arguments;
		/// <summary>
		/// For an explicit argument that's a value (its type in generic_arguments is null), the value.
		/// </summary>
		std::vector<ConstantValue> generic_values;
		/// <summary>
		/// The local a name is, by where it was defined, or null for anything else.
		/// </summary>
		const void* local = nullptr;
		/// <summary>
		/// For a call's result: the function type called, and the function (an instance, for a
		/// generic one), or null for a function value.
		/// </summary>
		TypeInfoFunction const* called = nullptr;
		Declaration* called_declaration = nullptr;
		/// <summary>
		/// For UNTYPED_INTEGER, its value when it's known, like a literal's or its negation's, which
		/// has to be in range of the integer type it becomes.
		/// </summary>
		bool integer_known = false;
		bool integer_negative = false;
		uint64_t integer_magnitude = 0;
		/// <summary>
		/// A secret: of a #secret type, or worked out from one (docs/memory.md, Secrets).
		/// </summary>
		bool is_secret = false;
	};

	/// <summary>
	/// What the checker found at one node of a body, for generating its code.
	/// </summary>
	struct CheckedNode {
		ValueKind kind = ValueKind::POISONED;
		TypeInfo* type = nullptr;
		Declaration* declaration = nullptr;
		const void* local = nullptr;
		TypeInfoFunction const* called = nullptr;
		Declaration* called_declaration = nullptr;
		size_t variant = 0;
		/// <summary>
		/// For a name's head, the child its steps start at: 2 after package.Name, otherwise 0.
		/// </summary>
		size_t next = 0;
		/// <summary>
		/// For an untyped integer whose value is known, like 512 / 4, that value, generated as one
		/// constant of the type it becomes.
		/// </summary>
		bool integer_known = false;
		bool integer_negative = false;
		uint64_t integer_magnitude = 0;
	};

	/// <summary>
	/// A checked function body: what each expression is, by node. A value inside a chain like
	/// a.b(c)[d] is at the node after it: the member's name, the (, the [, or the ^.
	/// </summary>
	struct CheckedBody {
		std::unordered_map<const ast::Node*, CheckedNode> nodes;
		/// <summary>
		/// What a name alone is, before what follows it like .b(c), by the name's node; and for a
		/// cast, the type it converts to.
		/// </summary>
		std::unordered_map<const ast::Node*, CheckedNode> heads;
		/// <summary>
		/// Each parameter's local, in order, and each named result's (null for an unnamed one).
		/// </summary>
		std::vector<const void*> parameters;
		std::vector<const void*> outputs;
		/// <summary>
		/// How deep in the function's scopes each local is defined: 1 for parameters, and more for
		/// each block in. A variable lives as long as its scope (docs/memory.md, Pointers to the Stack).
		/// </summary>
		std::unordered_map<const void*, size_t> local_depths;
		/// <summary>
		/// In an instance, the values of its generic list that aren't parameters, like capacity in
		/// fn[T, capacity: usize]: locals that are constants, by where they're declared.
		/// </summary>
		std::unordered_map<const void*, ConstantValue> generic_constants;
		/// <summary>
		/// What each compiler.satisfies worked out, by its call's node (docs/types.md, Constraints).
		/// </summary>
		std::unordered_map<const ast::Node*, bool> satisfied;
	};

	/// <summary>
	/// Checks a function's body, once its signature is resolved, with its generic parameters bound
	/// for an instance.
	/// </summary>
	Progress check_body(WorkThreadData& executor, Declaration* function);

	/// <summary>
	/// The type of a constant's value, or for a literal, what kind of untyped value it is.
	/// </summary>
	Progress check_constant(Walk& walk, ast::Node* value, TypeInfo* expected, Value& result,
		CheckedBody* record_into = nullptr);

	/// <summary>
	/// A top-level #assert (docs/directives.md): its condition, a compile-time constant, is true.
	/// </summary>
	Progress check_top_level_assert(WorkThreadData& executor, const FileLocation& file, ast::Node* node);

	/// <summary>
	/// Checks compile-time code in the walk's scope, recording what it found in record, for running it, and
	/// gives its value's type (null for nothing). FAILED once it reported errors.
	/// </summary>
	Progress check_compile_time_expression(Walk& walk, ast::Node* expression, CheckedBody* record, TypeInfo*& type);

	/// <summary>
	/// Checks the expression of a top-level #run, recording what it found in record, for running it.
	/// </summary>
	Progress check_top_level_run(WorkThreadData& executor, const FileLocation& file, ast::Node* expression,
		CheckedBody* record);

	/// <summary>
	/// The type a value has where nothing else decides it: 5 is an int, 0.5 an f64; null if it
	/// has none.
	/// </summary>
	TypeInfo* usual_type(const Value& value);

	/// <summary>
	/// A function definition's body, or null for a declaration without one (---).
	/// </summary>
	ast::Node* function_body(const Declaration* function);

	/*
	 * The file #file_data(path) names, in a file at including_file: path is relative to that
	 * file's folder (docs/directives.md, Values). Empty if the argument isn't a string literal.
	 */
	std::filesystem::path file_data_path(std::string_view including_file, const ast::Node* directive);
}
