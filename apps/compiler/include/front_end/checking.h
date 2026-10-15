#pragma once

#include <string>
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
	};

	/// <summary>
	/// Checks a function's body, once its signature is resolved, with its generic parameters bound
	/// for an instance.
	/// </summary>
	Progress check_body(WorkThreadData& executor, Declaration* function);

	/// <summary>
	/// The type of a constant's value, or for a literal, what kind of untyped value it is.
	/// </summary>
	Progress check_constant(Walk& walk, ast::Node* value, TypeInfo* expected, Value& result);

	/// <summary>
	/// The type a value has where nothing else decides it: 5 is an int, 0.5 an f64; null if it
	/// has none.
	/// </summary>
	TypeInfo* usual_type(const Value& value);

	/// <summary>
	/// A function definition's body, or null for a declaration without one (---).
	/// </summary>
	ast::Node* function_body(const Declaration* function);
}
