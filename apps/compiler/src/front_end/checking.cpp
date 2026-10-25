#include <algorithm>
#include <format>
#include <iostream>
#include <map>
#include <set>
#include <unordered_set>

#include "error/reporting.h"
#include "front_end/checking.h"
#include "front_end/format_spec.h"
#include "front_end/front_end.h"
#include "front_end/bounds.h"
#include "front_end/ownership.h"
#include "front_end/stack_pointers.h"
#include "middle_end/code_values.h"
#include "util/logger.h"

namespace hemera {

	/*
	 * Type checking of expressions and statements. A check that has to wait for a declaration parks
	 * its work and starts over when woken; errors it reported before are reported once (reporting
	 * drops exact repeats). An expression with an error is POISONED, which anything accepts, so one
	 * mistake gives one error.
	 */

	// ---------------------------------------------------------------------------------------------
	// Scopes

	struct Local {
		InternedString name = nullptr;
		Value value;
		// Its name's hygiene mark: a macro's local is seen only by code the same expansion wrote (docs/compilation.md, Macros)
		uint32_t mark = 0;
	};

	struct Scope {
		std::vector<Local> locals;
	};

	struct Checker {
		Walk& walk;
		/// <summary>
		/// The function whose body this is, or null for a constant's value.
		/// </summary>
		TypeInfoFunction* function = nullptr;
		std::vector<Scope> scopes;
		/// <summary>
		/// How many loops the statement being checked is in, for continue.
		/// </summary>
		size_t loops = 0;
		/// <summary>
		/// How many loops and switches it's in, for break, and break 2 (docs/control_flow.md).
		/// </summary>
		size_t breakables = 0;
		/// <summary>
		/// Whether there's a context: false in entry points until they push one.
		/// </summary>
		bool has_context = true;
		/// <summary>
		/// In a body checked before any instance, an #if was left to the instances, since what it
		/// decides on is only known there (docs/types.md, Checked Bodies).
		/// </summary>
		bool undecided = false;
		/// <summary>
		/// What the left of |> gave, for the call on its right to take first.
		/// </summary>
		std::vector<Value> piped;
		/// <summary>
		/// Where to record what each node is, for generating code, or null.
		/// </summary>
		CheckedBody* record = nullptr;
		/// <summary>
		/// Secrets (docs/memory.md, Secrets): whether the function is #constant_time, whether it works
		/// with a secret, and which expressions are secrets, so what's worked out from them is too.
		/// </summary>
		bool constant_time = false;
		bool saw_secret = false;
		std::unordered_set<const ast::Node*> secret_nodes;
		/// <summary>
		/// The call being checked is of an intrinsic, which takes secrets wherever it's given them.
		/// </summary>
		bool intrinsic_arguments = false;
		explicit Checker(Walk& walk_)
			: walk{ walk_ }
		{}
	};

	static bool is_text(InternedString value, std::string_view text) {
		return value != nullptr && std::string_view(*value) == text;
	}

	static Value error_at(Checker& checker, ErrorCode code, const ast::Node* node, std::string message);

	/*
	 * A secret was worked with (docs/memory.md, Secrets). Any function can hold secrets, and the rules
	 * hold everywhere; one whose parameters or results are secrets says so with #constant_time.
	 */
	static void note_secret(Checker& checker, const ast::Node* where) {
		(void)where;
		checker.saw_secret = true;
	}

	// Whether a function's definition is marked #constant_time, like f #constant_time :: fn(...).
	static bool marked_constant_time(const ast::Node* definition) {
		if (definition == nullptr || definition->children.empty()) {
			return false;
		}
		for (const ast::Node* directive : definition->children[0]->children) {
			if (ast::NodeType::DIRECTIVE == directive->node_type && is_text(directive->value.value, "#constant_time")) {
				return true;
			}
		}
		return false;
	}

	static bool is_secret_node(const Checker& checker, const ast::Node* node) {
		return node != nullptr && checker.secret_nodes.contains(node);
	}

	// A secret can't decide what's described, like a branch or a loop's count, which would show in its timing.
	static void require_public(Checker& checker, const ast::Node* node, std::string_view what) {
		if (is_secret_node(checker, node)) {
			error_at(checker, ErrorCode::E4037, node, std::format("a secret can't decide {}, which would show in how long it takes", what));
		}
	}

	/*
	 * Whether a secret can go where a value of type does: a #secret type, or a place that already holds
	 * secrets, like a secret local. Otherwise it's said why, and how to get past it.
	 */
	static bool require_secret_fits(Checker& checker, bool secret, TypeInfo const* type, bool secret_place, const ast::Node* where,
		std::string_view what) {

		if (!secret || secret_place || type == nullptr || is_secret_type(type)) {
			return true;
		}
		error_at(checker, ErrorCode::E4037, where, std::format(
			"{} isn't a #secret type, so a secret can't go there; give it a #secret type, or compiler.declassify what's public by design",
			what));
		return false;
	}

	static std::string text_of(InternedString value) {
		return value != nullptr ? std::string(std::string_view(*value)) : std::string("_");
	}

	static bool is_assign(const ast::Node* node) {
		return TokenType::OPERATOR_ASSIGN == node->value.type;
	}

	static Value poisoned() {
		return Value{};
	}

	// Reports an error at a node, and gives the POISONED value it leaves behind.
	static Value error_at(Checker& checker, ErrorCode code, const ast::Node* where, std::string details) {
		report_at(code, checker.walk.file_path, &checker.walk.executor.program_info->made_nodes, where, details);
		return poisoned();
	}

	void report_at(ErrorCode code, const std::string& file_path, const ast::NodeStore* made, const ast::Node* where,
		std::string_view details) {
		const std::shared_ptr<const ast::Origin> origin = made != nullptr ? made->origin(where) : nullptr;
		if (origin == nullptr) {
			report_error(code, file_path, where->value.line_number, where->value.column_number, details);
			return;
		}
		report_error(code, origin->file, where->value.line_number, where->value.column_number,
			std::string(details) + inserted_note(*origin));
	}

	std::string inserted_note(const ast::Origin& origin) {
		// A long chain, from macros expanding many times, shows its latest sites and the first
		static constexpr size_t SHOWN = 4;
		std::string note;
		const size_t count = origin.inserted.size();
		for (size_t i = count; i-- > 0;) {
			if (count > SHOWN + 1 && i == count - SHOWN - 1) {
				note += std::format("; ... {} more", count - SHOWN - 1);
				i = 0;
			}
			const ast::InsertionSite& site = origin.inserted[i];
			note += std::format("; inserted at {}({},{})", site.file, site.line, site.column);
		}
		return note;
	}

	static Value typed(TypeInfo* type) {
		Value value;
		value.kind = ValueKind::VALUE;
		value.type = type;
		return value;
	}

	static Value type_value(TypeInfo* type) {
		Value value;
		value.kind = ValueKind::TYPE;
		value.type = type;
		return value;
	}

	static Value nothing() {
		Value value;
		value.kind = ValueKind::NOTHING;
		return value;
	}

	static void store_checked(CheckedNode& checked, const Value& value) {
		checked.kind = value.kind;
		checked.type = value.type;
		checked.stored_type = value.stored_type;
		checked.declaration = value.declaration;
		checked.local = value.local;
		checked.called = value.called;
		checked.called_declaration = value.called_declaration;
		checked.variant = value.variant;
		checked.integer_known = ValueKind::UNTYPED_INTEGER == value.kind && value.integer_known;
		checked.integer_negative = value.integer_negative;
		checked.integer_magnitude = value.integer_magnitude;
	}

	// Records what a node is, for generating its code.
	static void record(Checker& checker, const ast::Node* node, const Value& value) {
		if (checker.record != nullptr) {
			store_checked(checker.record->nodes[node], value);
		}
	}

	// A local, keyed by where it's defined (its name's node), which its uses record.
	static void declare_local(Checker& checker, const void* at, InternedString name, Value value) {
		if (name == nullptr || is_text(name, "_")) {
			return;
		}
		value.local = at;
		// What it is, where it's defined, for generating its storage
		if (checker.record != nullptr) {
			store_checked(checker.record->nodes[static_cast<const ast::Node*>(at)], value);
			checker.record->local_depths[at] = checker.scopes.size();
		}
		const uint32_t mark = checker.walk.executor.program_info->made_nodes.mark_of(static_cast<const ast::Node*>(at));
		checker.scopes.back().locals.push_back({ name, std::move(value), mark });
	}

	// The local a name used at a node refers to, written by the same macro expansion as it, or null.
	static const Local* find_local(const Checker& checker, const ast::Node* use) {
		const InternedString name = use->value.value;
		const uint32_t mark = checker.walk.executor.program_info->made_nodes.mark_of(use);
		for (auto scope = checker.scopes.rbegin(); scope != checker.scopes.rend(); ++scope) {
			for (auto local = scope->locals.rbegin(); local != scope->locals.rend(); ++local) {
				if (local->mark == mark && *local->name == *name) {
					return &*local;
				}
			}
		}
		return nullptr;
	}

	// ---------------------------------------------------------------------------------------------
	// Types

	static TypeInfo const* base_of(TypeInfo const* type) {
		return get_base_type(type);
	}

	static bool is_variant(TypeInfo const* type, TypeInfoVariant variant) {
		type = base_of(type);
		return type != nullptr && variant == type->variant;
	}

	static bool is_integer(TypeInfo const* type) {
		return is_variant(type, TypeInfoVariant::INTEGER);
	}

	static bool is_signed(TypeInfo const* type) {
		return is_integer(type) && static_cast<TypeInfoInteger const*>(base_of(type))->is_signed;
	}

	static bool is_float(TypeInfo const* type) {
		return is_variant(type, TypeInfoVariant::FLOAT);
	}

	static bool is_numeric(TypeInfo const* type) {
		return is_integer(type) || is_float(type) || is_variant(type, TypeInfoVariant::COMPLEX)
			|| is_variant(type, TypeInfoVariant::QUATERNION);
	}

	// A complex number or a quaternion (docs/types.md, Complex Numbers and Quaternions).
	static bool is_composite(TypeInfo const* type) {
		return is_variant(type, TypeInfoVariant::COMPLEX) || is_variant(type, TypeInfoVariant::QUATERNION);
	}

	static bool is_boolean(TypeInfo const* type) {
		return is_variant(type, TypeInfoVariant::BOOLEAN);
	}

	static bool is_enum(TypeInfo const* type) {
		return is_variant(type, TypeInfoVariant::ENUM);
	}

	static bool is_pointer(TypeInfo const* type) {
		return is_variant(type, TypeInfoVariant::POINTER);
	}

	// A constrained generic's type parameter, while its body is checked before any instance (docs/types.md, Checked Bodies).
	static TypeInfoArchetype const* archetype_of(TypeInfo const* type) {
		type = base_of(type);
		return type != nullptr && TypeInfoVariant::ARCHETYPE == type->variant ? static_cast<TypeInfoArchetype const*>(type) : nullptr;
	}

	static bool promised(TypeInfo const* type, uint32_t capability) {
		TypeInfoArchetype const* archetype = archetype_of(type);
		return archetype != nullptr && (archetype->capabilities & capability) == capability;
	}

	// The constraint in base/compiler that promises a capability, for what to add.
	static const char* constraint_promising(uint32_t capability) {
		switch (capability) {
			case CAPABILITY_EQUALITY: return "compiler.Equatable";
			case CAPABILITY_ORDERING: return "compiler.Ordered";
			case CAPABILITY_INTEGER: return "compiler.Integer";
			case CAPABILITY_FLOAT: return "compiler.Float";
			default: return "compiler.Numeric";
		}
	}

	static Value not_promised(Checker& checker, const ast::Node* where, TypeInfoArchetype const* archetype, std::string_view what,
		std::string_view fix) {

		return error_at(checker, ErrorCode::E4033, where, std::format("{} on {}, which {}'s constraints don't promise; {}", what,
			to_string(archetype), text_of(archetype->generic), fix));
	}

	static Value not_promised(Checker& checker, const ast::Node* where, TypeInfoArchetype const* archetype, std::string_view what,
		uint32_t capability) {

		return not_promised(checker, where, archetype, what, std::format("constrain {} with {}", to_string(archetype),
			constraint_promising(capability)));
	}

	// The union an Optional or Result instance is, by its generic's name, or null.
	static TypeInfoUnion const* builtin_union(TypeInfo const* type, std::string_view generic) {
		type = base_of(type);
		if (type == nullptr || TypeInfoVariant::UNION != type->variant) {
			return nullptr;
		}
		auto result = static_cast<TypeInfoUnion const*>(type);
		const std::string name = text_of(result->name);
		return name.starts_with(std::string(generic) + "[") ? result : nullptr;
	}

	static Progress complete_subject(Checker& checker, ast::Node* where, const Value& subject);

	// What an optional (Some) or a result (Ok) holds, or null if type is neither.
	static TypeInfo* held_value(TypeInfo const* type) {
		TypeInfoUnion const* holder = builtin_union(type, "Optional");
		if (holder == nullptr) {
			holder = builtin_union(type, "Result");
		}
		if (holder == nullptr || holder->variants.empty()) {
			return nullptr;
		}
		// Result[void, E]'s Ok holds nothing
		if (holder->variants[0].types.empty()) {
			return builtin_union(type, "Result") != nullptr ? BUILTIN_void : nullptr;
		}
		return holder->variants[0].types[0];
	}

	static std::string describe(const Value& value) {
		const ValueKind kind = value.kind;
		if (ValueKind::VALUE == kind) {
			return to_string(value.type);
		}
		if (ValueKind::TYPE == kind) {
			return std::format("the type {}", to_string(value.type));
		}
		if (ValueKind::UNTYPED_INTEGER == kind) {
			return value.integer_known ? std::format("the integer {}{}", value.integer_negative ? "-" : "", value.integer_magnitude)
				: "an integer";
		}
		if (ValueKind::UNTYPED_FLOAT == kind) {
			return "a floating point number";
		}
		if (ValueKind::UNTYPED_COMPLEX == kind) {
			return "a complex number";
		}
		if (ValueKind::UNTYPED_QUATERNION == kind) {
			return "a quaternion";
		}
		if (ValueKind::UNTYPED_STRING == kind) {
			return "a string";
		}
		if (ValueKind::UNTYPED_BOOLEAN == kind) {
			return "a boolean";
		}
		if (ValueKind::NULL_VALUE == kind) {
			return "null";
		}
		if (ValueKind::NOTHING == kind) {
			return "nothing";
		}
		if (ValueKind::RESULTS == kind) {
			std::string result = "(";
			for (size_t i = 0; i < value.results.size(); ++i) {
				result += (i > 0 ? ", " : "") + to_string(value.results[i]);
			}
			return result + ")";
		}
		if (ValueKind::PACKAGE == kind) {
			return "a package";
		}
		return "a function";
	}

	/*
	 * Whether a value of type from can be used as a to: the same type (aliases that aren't
	 * distinct included), an implicit conversion (docs/types.md, Implicit Casting), anything as
	 * any, an array as a view of its elements, ptr[mut T] as ptr[T], or T as T?.
	 */
	static bool assignable(TypeInfo* from, TypeInfo* to) {
		if (from == nullptr || to == nullptr) {
			return true;
		}
		if (same_type(from, to) || can_implicitly_convert_to(from, to)) {
			return true;
		}
		// A changeable share becomes a read-only one, like SharedPtr[mut Buffer] to SharedPtr[Buffer]
		if (converts_to_read_only(from, to)) {
			return true;
		}
		TypeInfo const* source = get_base_type_or_alias(from);
		TypeInfo const* target = get_base_type_or_alias(to);
		if (TypeInfoVariant::ANY == target->variant) {
			return true;
		}
		/*
		 * An array as a view of its elements, and a mut T[] as a T[]. A view never becomes a mut T[]; an array
		 * does if what holds it can be changed, which fits checks, having the value
		 */
		if (TypeInfoVariant::ARRAY == source->variant && TypeInfoVariant::ARRAY == target->variant) {
			auto a = static_cast<TypeInfoArray const*>(source);
			auto b = static_cast<TypeInfoArray const*>(target);
			const bool loses_nothing = !b->is_mutable || ArrayType::VIEW != a->array_type || a->is_mutable;
			return ArrayType::VIEW == b->array_type && same_type(a->element_type, b->element_type) && loses_nothing;
		}
		if (TypeInfoVariant::POINTER == source->variant && TypeInfoVariant::POINTER == target->variant) {
			auto a = static_cast<TypeInfoPointer const*>(source);
			auto b = static_cast<TypeInfoPointer const*>(target);
			return a->is_relative == b->is_relative && a->size == b->size && (a->is_mutable || !b->is_mutable)
				&& (b->base_type == nullptr || same_type(a->base_type, b->base_type));
		}
		if (TypeInfoVariant::FUNCTION == source->variant && TypeInfoVariant::FUNCTION == target->variant) {
			auto a = static_cast<TypeInfoFunction const*>(source);
			auto b = static_cast<TypeInfoFunction const*>(target);
			if (a->input.size() != b->input.size() || a->output.size() != b->output.size()) {
				return false;
			}
			for (size_t i = 0; i < a->input.size(); ++i) {
				if (!same_type(a->input[i].type, b->input[i].type)
					|| a->input[i].is_varargs != b->input[i].is_varargs) {
					return false;
				}
				// One that keeps a parameter can't be called as one that doesn't, whose callers may pass the stack
				if (a->input[i].is_escaping && !b->input[i].is_escaping) {
					return false;
				}
			}
			for (size_t i = 0; i < a->output.size(); ++i) {
				if (!same_type(a->output[i].type, b->output[i].type)) {
					return false;
				}
				// One whose result may point into the stack can't be called as one whose result can't
				if (b->output[i].is_unrestricted && !a->output[i].is_unrestricted) {
					return false;
				}
			}
			return a->never_returns || !b->never_returns;
		}
		TypeInfo* held = held_value(target);
		return builtin_union(target, "Optional") != nullptr && held != nullptr && assignable(from, held);
	}

	/*
	 * The largest value an integer type holds, and the magnitude of its smallest, as far as a literal
	 * goes: u64's largest, so every literal fits an i128 or u128.
	 */
	static uint64_t integer_max(TypeInfoInteger const* integer) {
		const size_t bits = integer->size * 8;
		if (bits > 64) {
			return UINT64_MAX;
		}
		if (integer->is_signed) {
			return (uint64_t{ 1 } << (bits - 1)) - 1;
		}
		return bits == 64 ? UINT64_MAX : (uint64_t{ 1 } << bits) - 1;
	}

	static uint64_t integer_min_magnitude(TypeInfoInteger const* integer) {
		if (!integer->is_signed) {
			return 0;
		}
		const size_t bits = integer->size * 8;
		return bits > 64 ? UINT64_MAX : uint64_t{ 1 } << (bits - 1);
	}

	// Whether an untyped integer whose value is known, like 300, is in range of an integer type, like u8.
	static bool in_range(const Value& value, TypeInfo const* type) {
		if (ValueKind::UNTYPED_INTEGER != value.kind || !value.integer_known || !is_integer(type)) {
			return true;
		}
		auto integer = static_cast<TypeInfoInteger const*>(base_of(type));
		// ~m in an unsigned type is m's bits flipped there, which fits when m does
		if (value.complement && !integer->is_signed) {
			return value.complemented <= integer_max(integer);
		}
		if (value.integer_negative) {
			return value.integer_magnitude <= integer_min_magnitude(integer);
		}
		return value.integer_magnitude <= integer_max(integer);
	}

	/*
	 * Whether value is an array that can't be changed where it is, like a parameter's, wanted as a mut T[]
	 * (docs/types.md, Mutability). A view that can't be changed isn't assignable to one at all.
	 */
	static bool elements_read_only(const Value& value, TypeInfo* type) {
		TypeInfo const* source = value.type != nullptr ? base_of(value.type) : nullptr;
		TypeInfo const* target = type != nullptr ? base_of(type) : nullptr;
		if (source == nullptr || target == nullptr || TypeInfoVariant::ARRAY != source->variant
			|| TypeInfoVariant::ARRAY != target->variant) {
			return false;
		}
		auto wanted = static_cast<TypeInfoArray const*>(target);
		auto given = static_cast<TypeInfoArray const*>(source);
		if (ArrayType::VIEW != wanted->array_type || !wanted->is_mutable) {
			return false;
		}
		if (ArrayType::VIEW == given->array_type) {
			return !given->is_mutable;
		}
		return value.is_location && !value.is_mutable;
	}

	/*
	 * Whether a value can be used as type, converting untyped literals: an integer becomes any
	 * integer or float; a float any float; a string a string or cstring; true and false any boolean;
	 * null any pointer, cstring, function or optional. A value fits an optional of its type, and
	 * anything but null fits an any, a type as a type value.
	 */
	static bool fits(const Value& value, TypeInfo* type) {
		if (type == nullptr || base_of(type) == nullptr || ValueKind::POISONED == value.kind) {
			return true;
		}
		const ValueKind kind = value.kind;
		TypeInfo* held = builtin_union(type, "Optional") != nullptr ? held_value(type) : nullptr;
		if (held != nullptr && ValueKind::VALUE != kind && fits(value, held)) {
			return true;
		}
		if (TypeInfoVariant::ANY == base_of(type)->variant) {
			return ValueKind::VALUE == kind || ValueKind::UNTYPED_INTEGER == kind
				|| ValueKind::UNTYPED_FLOAT == kind || ValueKind::UNTYPED_STRING == kind
				|| ValueKind::UNTYPED_COMPLEX == kind || ValueKind::UNTYPED_QUATERNION == kind
				|| ValueKind::UNTYPED_BOOLEAN == kind || ValueKind::TYPE == kind;
		}
		if (ValueKind::VALUE == kind) {
			return assignable(value.type, type) && !elements_read_only(value, type);
		}
		// A real number is a complex number's or a quaternion's real part
		if (ValueKind::UNTYPED_INTEGER == kind) {
			return (is_integer(type) && in_range(value, type)) || is_float(type) || is_composite(type) || promised(type, CAPABILITY_ARITHMETIC);
		}
		if (ValueKind::UNTYPED_FLOAT == kind) {
			return is_float(type) || is_composite(type) || promised(type, CAPABILITY_FLOAT);
		}
		if (ValueKind::UNTYPED_COMPLEX == kind) {
			return is_composite(type);
		}
		if (ValueKind::UNTYPED_QUATERNION == kind) {
			return is_variant(type, TypeInfoVariant::QUATERNION);
		}
		if (ValueKind::UNTYPED_STRING == kind) {
			return is_variant(type, TypeInfoVariant::STRING);
		}
		if (ValueKind::UNTYPED_BOOLEAN == kind) {
			return is_boolean(type);
		}
		// null is a rawptr's, or an optional's None: ptr[T], cstring and functions are never null
		if (ValueKind::NULL_VALUE == kind) {
			return (is_pointer(type) && static_cast<TypeInfoPointer const*>(base_of(type))->base_type == nullptr)
				|| builtin_union(type, "Optional") != nullptr;
		}
		if (ValueKind::TYPE == kind) {
			return is_variant(type, TypeInfoVariant::TYPE);
		}
		// A variant without values, like ConsoleError.Unsupported, is a value of its union
		if (ValueKind::VARIANT == kind && value.type != nullptr) {
			auto union_type = static_cast<TypeInfoUnion const*>(base_of(value.type));
			return value.variant < union_type->variants.size() && union_type->variants[value.variant].types.empty()
				&& assignable(value.type, type);
		}
		return false;
	}

	/*
	 * Whether a value given for one type could be taken for the other: one converts to the other implicitly, or a
	 * literal fits both, like 3 an int and an f32 (docs/functions.md, Variable Arguments).
	 */
	static bool could_be_either(TypeInfo* a, TypeInfo* b) {
		if (assignable(a, b) || assignable(b, a)) {
			return true;
		}
		for (ValueKind kind : { ValueKind::UNTYPED_INTEGER, ValueKind::UNTYPED_FLOAT, ValueKind::UNTYPED_STRING, ValueKind::UNTYPED_BOOLEAN,
			ValueKind::NULL_VALUE, ValueKind::UNTYPED_COMPLEX, ValueKind::UNTYPED_QUATERNION }) {
			Value literal;
			literal.kind = kind;
			literal.integer_known = true;
			if (fits(literal, a) && fits(literal, b)) {
				return true;
			}
		}
		return false;
	}

	// The type an untyped value has where nothing else decides it: 5 is an int, 0.5 an f64.
	static TypeInfo* default_type(const Value& value) {
		const ValueKind kind = value.kind;
		if (ValueKind::VALUE == kind) {
			return value.type;
		}
		if (ValueKind::UNTYPED_INTEGER == kind) {
			return BUILTIN_int;
		}
		if (ValueKind::UNTYPED_FLOAT == kind) {
			return BUILTIN_f64;
		}
		if (ValueKind::UNTYPED_COMPLEX == kind) {
			return BUILTIN_c128;
		}
		if (ValueKind::UNTYPED_QUATERNION == kind) {
			return BUILTIN_q256;
		}
		if (ValueKind::UNTYPED_STRING == kind) {
			return BUILTIN_string;
		}
		if (ValueKind::UNTYPED_BOOLEAN == kind) {
			return BUILTIN_bool;
		}
		if (ValueKind::TYPE == kind) {
			return BUILTIN_type;
		}
		return nullptr;
	}

	static void report_out_of_range(Checker& checker, const Value& value, TypeInfo* type, const ast::Node* where) {
		auto integer = static_cast<TypeInfoInteger const*>(base_of(type));
		const uint64_t smallest = integer_min_magnitude(integer);
		if (value.complement && !integer->is_signed) {
			error_at(checker, ErrorCode::E4015, where, std::format("~{:#x} in a {} needs {:#x} to be one, and it's out of {}'s range, 0 to {}",
				value.complemented, to_string(type), value.complemented, to_string(type), integer_max(integer)));
			return;
		}
		error_at(checker, ErrorCode::E4015, where, std::format("{}{} is out of {}'s range, {}{} to {}",
			value.integer_negative ? "-" : "", value.integer_magnitude, to_string(type), smallest == 0 ? "" : "-", smallest,
			integer_max(integer)));
	}

	// Reports a value that can't be used as type. Returns whether it fits.
	static bool require_fit(Checker& checker, const Value& value, TypeInfo* type, const ast::Node* where,
		std::string_view what) {

		if (fits(value, type)) {
			return true;
		}
		if (!in_range(value, type)) {
			report_out_of_range(checker, value, type, where);
			return false;
		}
		if (ValueKind::VALUE == value.kind && elements_read_only(value, type)) {
			error_at(checker, ErrorCode::E4016, where, std::format("{} needs {}, whose elements can be changed, and these "
				"can't be changed here: give a mut view, or the array from where it can be changed (docs/types.md, Mutability)",
				what, to_string(type)));
			return false;
		}
		error_at(checker, ErrorCode::E4015, where, std::format("{} needs {}, not {}", what, to_string(type),
			describe(value)));
		return false;
	}

	// Reports a known integer out of range of the other side's type, like 300 in small + 300. Returns whether it was.
	static bool report_operand_range(Checker& checker, const Value& left, const Value& right, const ast::Node* where) {
		if (ValueKind::VALUE == right.kind && !in_range(left, right.type)) {
			report_out_of_range(checker, left, right.type, where);
			return true;
		}
		if (ValueKind::VALUE == left.kind && !in_range(right, left.type)) {
			report_out_of_range(checker, right, left.type, where);
			return true;
		}
		return false;
	}

	// Reports an untyped integer out of range of its usual type, int, which it's becoming. Returns whether it fits.
	static bool require_default_range(Checker& checker, const Value& value, const ast::Node* where) {
		TypeInfo* type = default_type(value);
		if (in_range(value, type)) {
			return true;
		}
		report_out_of_range(checker, value, type, where);
		return false;
	}

	// ---------------------------------------------------------------------------------------------
	// Expressions

	static Progress check_expression(Checker& checker, ast::Node* node, TypeInfo* expected, Value& result);
	static Progress check_block(Checker& checker, ast::Node* block, bool& continues, Value* last_value,
		TypeInfo* expected);
	static Progress check_statement(Checker& checker, ast::Node* statement, bool& continues);
	static Progress apply_postfix(Checker& checker, ast::Node* node, size_t start, Value& value);
	static Progress check_postfix(Checker& checker, ast::Node* node, Value& value);

	// A type written in a body, like the T in x : T or cast[T]: its names are looked up first.
	static Progress check_type(Checker& checker, ast::Node* node, Need need, TypeInfo*& result) {
		Progress progress = walk_names(checker.walk, node, need);
		if (progress != Progress::DONE) {
			return progress;
		}
		return type_of(checker.walk, node, need, result);
	}

	// A local's type, written in a body: mut only where it changes something, as in mut T[].
	static Progress check_held_type(Checker& checker, ast::Node* node, Need need, TypeInfo*& result) {
		Progress progress = walk_names(checker.walk, node, need);
		if (progress != Progress::DONE) {
			return progress;
		}
		return held_type_of(checker.walk, node, need, result);
	}

	// The value a declaration is, where its name is used.
	static Value declaration_value(Checker& checker, Declaration* declaration) {
		if (declaration->type_value != nullptr || DeclarationKind::GENERIC_TYPE == declaration->kind) {
			Value value = type_value(declaration->type_value);
			value.declaration = declaration;
			return value;
		}
		if (DeclarationKind::FUNCTION == declaration->kind && declaration->value_type == nullptr) {
			Value value;
			value.kind = ValueKind::GENERIC_FUNCTION;
			value.declaration = declaration;
			return value;
		}
		Value value;
		value.declaration = declaration;
		if (declaration->value_type != nullptr) {
			value.kind = ValueKind::VALUE;
			value.type = declaration->value_type;
			// A constant has an address, but can't be assigned
			value.is_location = DeclarationKind::VALUE == declaration->kind;
			return value;
		}
		const Untyped untyped = declaration->untyped;
		value.integer_known = declaration->integer_known;
		value.integer_negative = declaration->integer_negative;
		value.integer_magnitude = declaration->integer_magnitude;
		value.kind = Untyped::INTEGER == untyped ? ValueKind::UNTYPED_INTEGER
			: Untyped::FLOAT == untyped ? ValueKind::UNTYPED_FLOAT
			: Untyped::STRING == untyped ? ValueKind::UNTYPED_STRING
			: Untyped::BOOLEAN == untyped ? ValueKind::UNTYPED_BOOLEAN
			: Untyped::COMPLEX == untyped ? ValueKind::UNTYPED_COMPLEX
			: Untyped::QUATERNION == untyped ? ValueKind::UNTYPED_QUATERNION
			: ValueKind::POISONED;
		(void)checker;
		return value;
	}

	// real, imag, jmag, kmag, conj and abs, on numbers rather than types (docs/types.md, Complex Numbers and Quaternions).
	static bool is_number_builtin(std::string_view name) {
		return name == "real" || name == "imag" || name == "jmag" || name == "kmag" || name == "conj" || name == "abs";
	}

	static bool is_builtin_function(std::string_view name) {
		return name == "size_of" || name == "align_of" || name == "offset_of" || name == "type_of"
			|| name == "type_info_of" || name == "types_are_aliases" || name == "max_value"
			|| name == "min_value" || name == "todo" || is_number_builtin(name);
	}

	static bool is_pointer_name(std::string_view name) {
		return name == "ptr" || name == "relptr8" || name == "relptr16" || name == "relptr32"
			|| name == "relptr64";
	}

	// A type from base, like runtime's Context, resolved.
	static Progress base_type(Checker& checker, ast::Node* where, std::string_view folder, std::string_view name,
		TypeInfo*& result) {

		Declaration* declaration = nullptr;
		Progress progress = base_declaration(checker.walk, where, folder, name, declaration);
		if (progress != Progress::DONE) {
			return progress;
		}
		progress = require_resolved(checker.walk, where, declaration, Need::RESOLVED);
		if (progress != Progress::DONE) {
			return progress;
		}
		result = declaration->type_value;
		return Progress::DONE;
	}

	/*
	 * What a name refers to: a local, the context, a generic parameter's type, a package, a
	 * declaration (waiting until it's resolved), or a builtin. For package.Name, the head and the
	 * name after it; next is set to the child after them.
	 */
	static Progress check_name(Checker& checker, ast::Node* node, Value& result, size_t& next) {
		InternedString name = node->value.value;
		next = 0;
		// A type #insert put here, as itself, like an enum before .Member (docs/compilation.md, Code Values)
		if (node->type != nullptr) {
			result = type_value(node->type);
			return Progress::DONE;
		}
		if (const Local* local = find_local(checker, node)) {
			result = local->value;
			return Progress::DONE;
		}
		if (is_text(name, "context")) {
			if (!checker.has_context) {
				result = error_at(checker, ErrorCode::E4027, node,
					"there's no context here until one is pushed with push_context ... from");
				return Progress::DONE;
			}
			TypeInfo* context = nullptr;
			Progress progress = base_type(checker, node, "runtime", "Context", context);
			if (progress != Progress::DONE) {
				return progress;
			}
			result = typed(context);
			result.is_location = true;
			result.is_context = true;
			return Progress::DONE;
		}
		auto generic = checker.walk.generic_types.find(text_of(name));
		if (generic != checker.walk.generic_types.end()) {
			result = type_value(generic->second);
			return Progress::DONE;
		}
		ast::Node* qualifier = node->children.size() >= 2
			&& ast::NodeType::DOT_ACCESS == node->children[0]->node_type
			&& ast::NodeType::IDENTIFIER == node->children[1]->node_type ? node->children[1] : nullptr;
		bool head_was_package = false;
		Progress progress = require_qualified(checker.walk, node, name, qualifier, Need::RESOLVED,
			head_was_package);
		if (progress == Progress::FAILED) {
			result = poisoned();
			return Progress::DONE;
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		ast::Node* binding = node;
		if (head_was_package) {
			binding = qualifier;
			name = qualifier->value.value;
			next = 2;
		}
		auto bound = checker.walk.bindings.find(binding);
		if (bound != checker.walk.bindings.end()) {
			result = declaration_value(checker, bound->second);
			return Progress::DONE;
		}
		// A builtin, maybe as base.Name
		if (TypeInfo* builtin = builtin_type(text_of(name))) {
			result = type_value(builtin);
			return Progress::DONE;
		}
		if (is_builtin_function(text_of(name))) {
			result.kind = ValueKind::BUILTIN_FUNCTION;
			result.name = name;
			return Progress::DONE;
		}
		if (is_pointer_name(text_of(name)) || is_text(name, "vector")) {
			// ptr, a relative pointer or vector, which is a type once it's given its arguments
			result = type_value(nullptr);
			result.name = name;
			return Progress::DONE;
		}
		if (is_text(name, "OS") || is_text(name, "TARGET_ARCH")) {
			TypeInfo* type = nullptr;
			progress = base_type(checker, node, "compiler", is_text(name, "OS") ? "OperatingSystem" : "Architecture",
				type);
			if (progress != Progress::DONE) {
				return progress;
			}
			result = typed(type);
			return Progress::DONE;
		}
		if (InternedString package = imported_package(checker.walk.file, name)) {
			result.kind = ValueKind::PACKAGE;
			result.name = package;
			return Progress::DONE;
		}
		result = error_at(checker, ErrorCode::E4008, node, text_of(name));
		return Progress::DONE;
	}

	// A struct's member by name, including those of structs it includes with using, at any depth.
	static const StructMember* find_member(TypeInfoStruct const* type, InternedString name) {
		for (const StructMember& member : type->members) {
			if (member.name != nullptr && !member.is_using && *member.name == *name) {
				return &member;
			}
		}
		for (const StructMember& member : type->members) {
			if (member.is_using || member.name == nullptr) {
				TypeInfo const* included = base_of(member.member_type);
				if (included != nullptr && TypeInfoVariant::STRUCT == included->variant) {
					if (const StructMember* found = find_member(static_cast<TypeInfoStruct const*>(included), name)) {
						return found;
					}
				}
			}
		}
		for (const StructMember& member : type->members) {
			if (member.is_using && member.name != nullptr && *member.name == *name) {
				return &member;
			}
		}
		return nullptr;
	}

	/*
	 * The using pointer field a member is reached through, like value in a struct with
	 * using value : ptr[Config], when the struct has no member of that name itself (docs/types.md, Structs).
	 */
	static const StructMember* forwarding_member(TypeInfoStruct const* type, InternedString name) {
		for (const StructMember& member : type->members) {
			if (!member.is_using || member.name == nullptr) {
				continue;
			}
			TypeInfo const* used = base_of(member.member_type);
			if (used == nullptr || TypeInfoVariant::POINTER != used->variant) {
				continue;
			}
			TypeInfo const* pointed = base_of(static_cast<TypeInfoPointer const*>(used)->base_type);
			if (pointed != nullptr && TypeInfoVariant::STRUCT == pointed->variant) {
				auto target = static_cast<TypeInfoStruct const*>(pointed);
				if (find_member(target, name) != nullptr || forwarding_member(target, name) != nullptr) {
					return &member;
				}
			}
		}
		return nullptr;
	}

	// .name on a value: a struct's field (through one pointer), or an array's or string's count.
	/*
	 * docs/types.md, Relative Pointers: a relative pointer in a field, an element or what a pointer points to is read
	 * where it's stored, as the pointer it holds, a ptr[T], or for an optional one a ptr[T]?. The place keeps what's
	 * stored there, which & points to and an assignment stores into.
	 */
	static Progress read_place(Checker& checker, ast::Node* where, Value& value) {
		TypeInfoPointer const* relative = ValueKind::VALUE == value.kind ? relative_pointer_of(value.type) : nullptr;
		if (relative == nullptr) {
			return Progress::DONE;
		}
		TypeInfo* stored = value.type;
		TypeInfo* read = pointer_to(checker.walk, relative->base_type, relative->is_mutable, false, POINTER_SIZE);
		if (TypeInfoVariant::UNION == base_of(stored)->variant) {
			Progress progress = optional_of(checker.walk, where, read, Need::RESOLVED, read);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		value.type = read;
		value.stored_type = stored;
		return Progress::DONE;
	}

	/*
	 * A value with a relative pointer in it can't be one of its own (docs/types.md, Relative Pointers): what's
	 * reported, for what it would be, or false if type has none.
	 */
	static bool report_relative(Checker& checker, ast::Node* where, TypeInfo const* type, std::string_view what) {
		if (type == nullptr || !holds_relative(type)) {
			return false;
		}
		error_at(checker, ErrorCode::E4040, where, std::format(
			"{} would be a copy of {}, which has a relative pointer in it: one means something only where it's stored, so set it "
			"there (docs/types.md, Relative Pointers)", what, to_string(type)));
		return true;
	}

	static Progress check_member(Checker& checker, ast::Node* where, InternedString name, Value& value) {
		const ValueKind kind = value.kind;
		if (ValueKind::POISONED == kind) {
			return Progress::DONE;
		}
		if (ValueKind::PACKAGE == kind) {
			Progress progress = require_in(checker.walk, where, value.name, name, Need::RESOLVED);
			if (progress == Progress::FAILED) {
				value = poisoned();
				return Progress::DONE;
			}
			if (progress != Progress::DONE) {
				return progress;
			}
			value = declaration_value(checker, checker.walk.bindings[where]);
			return Progress::DONE;
		}
		if (ValueKind::TYPE == kind) {
			// An enum's member, or a union's variant
			TypeInfo const* type = base_of(value.type);
			if (type != nullptr && !type->complete) {
				Progress progress = require_complete(checker.walk, where, const_cast<TypeInfo*>(type));
				if (progress != Progress::DONE) {
					return progress;
				}
			}
			if (type != nullptr && TypeInfoVariant::ENUM == type->variant) {
				auto enumeration = static_cast<TypeInfoEnum const*>(type);
				for (InternedString member : enumeration->members) {
					if (*member == *name) {
						value = typed(value.type);
						return Progress::DONE;
					}
				}
			}
			if (type != nullptr && TypeInfoVariant::UNION == type->variant) {
				auto union_type = static_cast<TypeInfoUnion const*>(type);
				for (size_t i = 0; i < union_type->variants.size(); ++i) {
					if (*union_type->variants[i].name == *name) {
						TypeInfo* union_info = value.type;
						value = Value{};
						value.kind = ValueKind::VARIANT;
						value.type = union_info;
						value.variant = i;
						return Progress::DONE;
					}
				}
			}
			value = error_at(checker, ErrorCode::E4017, where, std::format("{} has no member {}",
				to_string(value.type), text_of(name)));
			return Progress::DONE;
		}
		// An untyped string or quaternion, like a constant's, has its type's members
		if (ValueKind::UNTYPED_STRING == kind || ValueKind::UNTYPED_QUATERNION == kind) {
			value = typed(default_type(value));
			return check_member(checker, where, name, value);
		}
		if (ValueKind::VALUE != kind) {
			value = error_at(checker, ErrorCode::E4017, where, std::format("{} has no member {}",
				describe(value), text_of(name)));
			return Progress::DONE;
		}
		TypeInfo const* type = base_of(value.type);
		// A value whose type is unknown comes from an error reported already, like a missing package
		if (type == nullptr) {
			value = poisoned();
			return Progress::DONE;
		}
		bool is_location = value.is_location;
		bool is_mutable = value.is_mutable;
		// Through a pointer, automatically
		if (TypeInfoVariant::POINTER == type->variant && static_cast<TypeInfoPointer const*>(type)->base_type != nullptr) {
			auto pointer = static_cast<TypeInfoPointer const*>(type);
			is_location = true;
			is_mutable = pointer->is_mutable;
			type = base_of(pointer->base_type);
		}
		const std::string member = text_of(name);
		if (!type->complete) {
			// A struct a signature only needed declared, which is laid out by now or soon
			Progress progress = require_complete(checker.walk, where, const_cast<TypeInfo*>(type));
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		if (TypeInfoVariant::STRUCT == type->variant) {
			const StructMember* found = find_member(static_cast<TypeInfoStruct const*>(type), name);
			if (found != nullptr) {
				const bool is_context = value.is_context;
				value = typed(found->member_type);
				value.is_location = is_location;
				value.is_mutable = is_mutable && !is_context;
				value.is_context = is_context;
				return read_place(checker, where, value);
			}
			// Through a using pointer field, which decides whether it can be changed
			if (const StructMember* forwarding = forwarding_member(static_cast<TypeInfoStruct const*>(type), name)) {
				value = typed(forwarding->member_type);
				value.is_location = is_location;
				value.is_mutable = is_mutable;
				return check_member(checker, where, name, value);
			}
		}
		else if (TypeInfoVariant::ARRAY == type->variant) {
			auto array = static_cast<TypeInfoArray const*>(type);
			if (member == "count" || (member == "capacity" && ArrayType::DYNAMIC == array->array_type)) {
				value = typed(BUILTIN_usize);
				return Progress::DONE;
			}
			if (member == "data" && ArrayType::STATIC != array->array_type) {
				value = typed(BUILTIN_rawptr);
				return Progress::DONE;
			}
		}
		else if (TypeInfoVariant::QUATERNION == type->variant) {
			// x, y and z, its imaginary parts, w its real part, and xyz the three as an array (docs/types.md, Quaternions)
			TypeInfo* part = static_cast<TypeInfoComposite const*>(type)->part_type;
			if (quaternion_field(member) >= 0 || member == "xyz") {
				value = typed(member == "xyz" ? array_of(checker.walk, part, ArrayType::STATIC, 3) : part);
				value.is_location = is_location;
				value.is_mutable = is_mutable;
				return Progress::DONE;
			}
		}
		else if (TypeInfoVariant::STRING == type->variant) {
			if (member == "count") {
				value = typed(BUILTIN_usize);
				return Progress::DONE;
			}
			if (member == "data") {
				value = typed(BUILTIN_rawptr);
				return Progress::DONE;
			}
		}
		else if (TypeInfoVariant::ARCHETYPE == type->variant) {
			// The fields its constraints promise, and a view's count
			auto archetype = static_cast<TypeInfoArchetype const*>(type);
			for (const auto& [field, field_type] : archetype->fields) {
				if (text_of(field) == member) {
					value = typed(field_type);
					value.is_location = is_location;
					value.is_mutable = is_mutable;
					return Progress::DONE;
				}
			}
			if (member == "count" && archetype->element != nullptr) {
				value = typed(BUILTIN_usize);
				return Progress::DONE;
			}
			value = not_promised(checker, where, archetype, std::format(".{}", member),
				std::format("promise it with compiler.require_field({}, \"{}\", ...) in a constraint", to_string(archetype), member));
			return Progress::DONE;
		}
		else if (TypeInfoVariant::ANY == type->variant) {
			if (member == "data") {
				value = typed(BUILTIN_rawptr);
				return Progress::DONE;
			}
			if (member == "type") {
				value = typed(BUILTIN_type);
				return Progress::DONE;
			}
		}
		value = error_at(checker, ErrorCode::E4017, where, std::format("{} has no member {}",
			to_string(value.type), member));
		return Progress::DONE;
	}

	// value[index] or value[range]: an element, or a view of several.
	static Progress check_index(Checker& checker, ast::Node* where, const std::vector<ast::Node*>& arguments,
		Value& value) {

		if (ValueKind::POISONED == value.kind) {
			return Progress::DONE;
		}
		// An untyped string, like a constant's, is indexed as a string
		if (ValueKind::UNTYPED_STRING == value.kind) {
			value = typed(default_type(value));
		}
		if (ValueKind::VALUE != value.kind || arguments.size() != 1) {
			value = error_at(checker, ErrorCode::E4020, where, std::format("{} can't be indexed", describe(value)));
			return Progress::DONE;
		}
		// Its type may be an alias, like a function's result's from another package, not resolved yet
		Progress resolved = complete_subject(checker, where, value);
		if (resolved != Progress::DONE) {
			return resolved;
		}
		TypeInfo const* type = base_of(value.type);
		if (type == nullptr) {
			value = poisoned();
			return Progress::DONE;
		}
		bool is_mutable = value.is_mutable;
		if (TypeInfoVariant::POINTER == type->variant && static_cast<TypeInfoPointer const*>(type)->base_type != nullptr) {
			/*
			 * What it points to only had to be declared, so an alias of it may not be resolved yet, by
			 * another thread: wait for it, as a member through a pointer does
			 */
			TypeInfo* pointee = static_cast<TypeInfoPointer const*>(type)->base_type;
			Progress progress = require_complete(checker.walk, where, pointee);
			if (progress != Progress::DONE) {
				return progress;
			}
			is_mutable = static_cast<TypeInfoPointer const*>(type)->is_mutable;
			type = base_of(pointee);
		}
		if (type == nullptr) {
			value = poisoned();
			return Progress::DONE;
		}
		TypeInfo* element = nullptr;
		if (TypeInfoVariant::ARRAY == type->variant) {
			/*
			 * A view's elements can be changed if it's a mut T[]; a static or dynamic array's if what holds it
			 * can be (docs/types.md, Mutability)
			 */
			element = static_cast<TypeInfoArray const*>(type)->element_type;
			if (ArrayType::VIEW == static_cast<TypeInfoArray const*>(type)->array_type) {
				is_mutable = static_cast<TypeInfoArray const*>(type)->is_mutable;
			}
		}
		else if (TypeInfoVariant::STRING == type->variant) {
			element = BUILTIN_char;
			is_mutable = false;
		}
		else if (TypeInfoVariant::VECTOR == type->variant && !static_cast<TypeInfoVector const*>(type)->is_bits) {
			// A lane, chosen by a constant so it's never out of range, and never decided at run time
			auto vector = static_cast<TypeInfoVector const*>(type);
			Value lane;
			Progress progress = check_expression(checker, arguments[0], BUILTIN_usize, lane);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (ValueKind::POISONED != lane.kind && (ValueKind::UNTYPED_INTEGER != lane.kind || !lane.integer_known
				|| lane.integer_negative || lane.integer_magnitude >= vector->count)) {
				error_at(checker, ErrorCode::E4015, arguments[0], std::format("a lane of {} is chosen by a constant from 0 to {}",
					to_string(value.type), vector->count - 1));
			}
			value = typed(vector->element_type);
			value.is_location = true;
			value.is_mutable = is_mutable;
			return Progress::DONE;
		}
		else if (TypeInfoVariant::ARCHETYPE == type->variant && static_cast<TypeInfoArchetype const*>(type)->element != nullptr) {
			element = static_cast<TypeInfoArchetype const*>(type)->element;
		}
		else if (TypeInfoVariant::ARCHETYPE == type->variant) {
			auto archetype = static_cast<TypeInfoArchetype const*>(type);
			value = not_promised(checker, where, archetype, "indexing", std::format("constrain it with compiler.ViewOf({}, ...)",
				to_string(archetype)));
			return Progress::DONE;
		}
		else {
			value = error_at(checker, ErrorCode::E4020, where, std::format("{} can't be indexed", to_string(value.type)));
			return Progress::DONE;
		}
		ast::Node* index = arguments[0];
		const TokenType op = index->value.type;
		const bool is_range = ast::NodeType::BINARY_OPERATOR == index->node_type
			&& (TokenType::OPERATOR_RANGE_EXCLUSIVE == op || TokenType::OPERATOR_RANGE_INCLUSIVE == op);
		const bool is_open_range = ast::NodeType::RANGE_ARRAY == index->node_type;
		if (is_range || is_open_range) {
			for (ast::Node* bound : index->children) {
				// The missing bound of an open range, like 5.. (its count) or ..<5 (0)
				if (ast::NodeType::RANGE_ARRAY == bound->node_type) {
					continue;
				}
				Value bound_value;
				Progress progress = check_expression(checker, bound, BUILTIN_usize, bound_value);
				if (progress != Progress::DONE) {
					return progress;
				}
				if (!is_integer(default_type(bound_value)) && ValueKind::POISONED != bound_value.kind) {
					error_at(checker, ErrorCode::E4015, bound, "a range's bounds are integers");
				}
			}
			// Part of a string is a string; part of an array, a view of its elements
			if (TypeInfoVariant::STRING == type->variant && !static_cast<TypeInfoString const*>(type)->is_raw) {
				value = typed(const_cast<TypeInfo*>(type));
				return Progress::DONE;
			}
			// Its elements can be changed through it if they can be through what it's part of
			value = typed(array_of(checker.walk, element, ArrayType::VIEW, 0, is_mutable));
			return Progress::DONE;
		}
		Value index_value;
		Progress progress = check_expression(checker, index, BUILTIN_usize, index_value);
		if (progress != Progress::DONE) {
			return progress;
		}
		if (ValueKind::POISONED != index_value.kind && !is_integer(default_type(index_value))) {
			error_at(checker, ErrorCode::E4015, index, std::format("an index is an integer, not {}",
				describe(index_value)));
		}
		require_public(checker, index, "which element is read, an address");
		value = typed(element);
		value.is_location = true;
		value.is_mutable = is_mutable;
		return read_place(checker, where, value);
	}

	// A function's parameters, from its FUNCTION node: their names, types and defaults.
	struct Parameter {
		InternedString name = nullptr;
		/// <summary>
		/// Its name's node, which keys it as a local.
		/// </summary>
		ast::Node* node = nullptr;
		ast::Node* type = nullptr;
		bool has_default = false;
		bool is_varargs = false;
	};

	static std::vector<Parameter> parameters_of(ast::Node* function) {
		std::vector<Parameter> result;
		for (ast::Node* child : function->children) {
			if (ast::NodeType::LIST != child->node_type) {
				continue;
			}
			for (ast::Node* parameter : child->children) {
				ast::Node* names_and_type = parameter;
				bool has_default = false;
				if (ast::NodeType::BINARY_OPERATOR == parameter->node_type && is_assign(parameter)
					&& !parameter->children.empty()) {
					names_and_type = parameter->children[0];
					has_default = true;
				}
				if (ast::NodeType::COLON != names_and_type->node_type) {
					result.push_back({ nullptr, names_and_type, names_and_type, has_default, false });
					continue;
				}
				std::vector<ast::Node*> names;
				ast::Node* type = nullptr;
				bool is_varargs = false;
				for (ast::Node* part : names_and_type->children) {
					if (ast::NodeType::IDENTIFIER == part->node_type && names.empty()) {
						names.push_back(part);
					}
					else if (ast::NodeType::LIST == part->node_type) {
						for (ast::Node* name : part->children) {
							names.push_back(name);
						}
					}
					else if (ast::NodeType::ELLIIPSIS == part->node_type) {
						is_varargs = true;
					}
					else {
						type = part;
					}
				}
				for (ast::Node* name : names) {
					result.push_back({ name->value.value, name, type, has_default, is_varargs });
				}
			}
			break;
		}
		return result;
	}

	// The FUNCTION node of a function declaration: its value, or its declared type for ---.
	static ast::Node* function_node(const Declaration* declaration) {
		for (ast::Node* child : declaration->node->children) {
			if (ast::NodeType::FUNCTION == child->node_type) {
				return child;
			}
		}
		return nullptr;
	}

	static std::vector<std::string> generic_names(ast::Node* function) {
		std::vector<std::string> result;
		for (ast::Node* child : function->children) {
			if (ast::NodeType::GENERIC_TAG == child->node_type) {
				for (ast::Node* parameter : child->children) {
					// T, or capacity in capacity: usize
					const bool is_value = ast::NodeType::COLON == parameter->node_type && !parameter->children.empty();
					result.push_back(text_of(is_value ? parameter->children[0]->value.value : parameter->value.value));
				}
			}
		}
		return result;
	}

	/*
	 * Whether a generic function's generic parameter at index takes a value: one written name: type,
	 * or a compile-time parameter, named like a parameter that isn't a type (docs/types.md).
	 */
	static bool generic_takes_value(NameRegistry& registry, Declaration* generic, size_t index) {
		ast::Node* function = generic != nullptr ? function_node(generic) : nullptr;
		if (function == nullptr) {
			return false;
		}
		if (generic_parameter_is_value(registry, generic, index)) {
			return true;
		}
		const std::vector<std::string> names = generic_names(function);
		if (index >= names.size()) {
			return false;
		}
		for (const Parameter& parameter : parameters_of(function)) {
			if (text_of(parameter.name) == names[index]) {
				return parameter.type == nullptr || !is_text(parameter.type->value.value, "type") || !parameter.type->children.empty();
			}
		}
		return false;
	}

	/*
	 * Binds generic parameters by matching a parameter's type, as written, with an argument's type
	 * (docs/types.md, Binding a Function's Generic Parameters): T in ptr[T] from a pointer's
	 * target, in T[] from an array's elements, in Pair[T, U] from an instance's arguments.
	 */
	static void unify(Checker& checker, ast::Node* pattern, TypeInfo* actual,
		std::map<std::string, TypeInfo*>& bound, std::map<std::string, ConstantValue>& bound_values,
		const std::vector<std::string>& generics) {

		if (pattern == nullptr || actual == nullptr) {
			return;
		}
		const std::string name = text_of(pattern->value.value);
		std::vector<ast::Node*> dimensions;
		ast::Node* arguments = nullptr;
		bool optional = false;
		for (ast::Node* child : pattern->children) {
			if (ast::NodeType::ARRAY_DIMENSION == child->node_type) {
				dimensions.push_back(child);
			}
			else if (ast::NodeType::GENERIC_TAG == child->node_type) {
				arguments = child;
			}
			else if (ast::NodeType::UNARY_OPERATOR == child->node_type) {
				optional = true;
			}
		}
		TypeInfo* current = actual;
		if (optional) {
			current = held_value(current);
			if (current == nullptr) {
				return;
			}
		}
		// The written dimensions, outermost first, peel the actual array
		for (size_t i = 0; i < dimensions.size(); ++i) {
			TypeInfo const* array = base_of(current);
			if (array == nullptr || TypeInfoVariant::ARRAY != array->variant) {
				return;
			}
			current = static_cast<TypeInfoArray const*>(array)->element_type;
		}
		if (std::find(generics.begin(), generics.end(), name) != generics.end() && arguments == nullptr) {
			bound.emplace(name, current);
			return;
		}
		if (arguments == nullptr) {
			return;
		}
		TypeInfo const* type = base_of(current);
		if ((name == "ptr" || name.starts_with("relptr")) && type != nullptr
			&& TypeInfoVariant::POINTER == type->variant && !arguments->children.empty()) {
			unify(checker, arguments->children[0], static_cast<TypeInfoPointer const*>(type)->base_type, bound,
				bound_values, generics);
			return;
		}
		// An instance of a generic type: its arguments
		NameRegistry& names = checker.walk.executor.program_info->names;
		Declaration* instance = nullptr;
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			auto iter = names.type_declarations.find(type);
			if (iter != names.type_declarations.end()) {
				instance = iter->second;
			}
		}
		if (instance == nullptr || instance->generic == nullptr) {
			return;
		}
		for (size_t i = 0; i < arguments->children.size() && i < instance->generic_arguments.size(); ++i) {
			// A value in the instance's list, like capacity in Ring[T, capacity], binds a value parameter
			ast::Node* argument = arguments->children[i];
			if (instance->generic_arguments[i] == nullptr) {
				const std::string value_name = text_of(argument->value.value);
				// In a type, the parser makes a plain name a TYPE node
				if ((ast::NodeType::IDENTIFIER == argument->node_type || ast::NodeType::TYPE == argument->node_type)
					&& argument->children.empty()
					&& std::find(generics.begin(), generics.end(), value_name) != generics.end()
					&& i < instance->generic_values.size()) {
					bound_values.emplace(value_name, instance->generic_values[i]);
				}
				continue;
			}
			unify(checker, argument, instance->generic_arguments[i], bound, bound_values, generics);
		}
	}

	// A positional argument: an expression, or a value a pipe passed.
	struct Positional {
		ast::Node* node = nullptr;
		bool has_value = false;
		Value value;
	};

	// The arguments of a call: positional first, then named, as name = value.
	struct Arguments {
		std::vector<Positional> positional;
		std::vector<std::pair<InternedString, ast::Node*>> named;
	};

	static bool is_placeholder(const ast::Node* node) {
		return ast::NodeType::UNDERSCORE == node->node_type
			|| ast::NodeType::PIPE_REORDER_IDENTIFIER == node->node_type;
	}

	/*
	 * Splits a call's arguments. What a pipe passed fills its _ placeholders in order, or $1, $2...
	 * by number, and comes first otherwise (docs/operators.md, Pipe operator).
	 */
	static Arguments split_arguments(Checker& checker, const std::vector<ast::Node*>& nodes,
		const std::vector<Value>& piped, const ast::Node* where) {

		Arguments result;
		const bool placeholders = std::any_of(nodes.begin(), nodes.end(), is_placeholder);
		if (!placeholders) {
			for (const Value& value : piped) {
				result.positional.push_back({ nullptr, true, value });
			}
		}
		size_t next_piped = 0;
		for (ast::Node* argument : nodes) {
			if (ast::NodeType::UNDERSCORE == argument->node_type) {
				if (next_piped >= piped.size()) {
					error_at(checker, ErrorCode::E4018, argument, "more _ than the values |> passes");
					result.positional.push_back({ argument, true, poisoned() });
					continue;
				}
				result.positional.push_back({ argument, true, piped[next_piped++] });
				continue;
			}
			if (ast::NodeType::PIPE_REORDER_IDENTIFIER == argument->node_type) {
				const std::string text = text_of(argument->value.value);
				const size_t number = text.size() > 1 ? std::stoul(text.substr(1)) : 0;
				if (number == 0 || number > piped.size()) {
					error_at(checker, ErrorCode::E4018, argument, std::format("{} isn't one of the {} values |> passes",
						text, piped.size()));
					result.positional.push_back({ argument, true, poisoned() });
					continue;
				}
				result.positional.push_back({ argument, true, piped[number - 1] });
				continue;
			}
			if (ast::NodeType::BINARY_OPERATOR == argument->node_type && is_assign(argument)
				&& argument->children.size() == 2
				&& ast::NodeType::IDENTIFIER == argument->children[0]->node_type) {
				result.named.emplace_back(argument->children[0]->value.value, argument->children[1]);
				continue;
			}
			if (!result.named.empty()) {
				error_at(checker, ErrorCode::E4018, argument, "positional arguments come before named ones");
			}
			result.positional.push_back({ argument, false, {} });
		}
		(void)where;
		return result;
	}

	// A positional argument's value: what a pipe passed, or its expression checked.
	static Progress positional_value(Checker& checker, const Positional& argument, TypeInfo* expected, Value& value) {
		if (argument.has_value) {
			value = argument.value;
			return Progress::DONE;
		}
		return check_expression(checker, argument.node, expected, value);
	}

	/*
	 * Checks a call's arguments against a function type's parameters (docs/functions.md): in order,
	 * then by name, defaults for the rest, and the varargs parameter taking the remaining positional
	 * ones (or another varargs view, passed on).
	 */
	/*
	 * A constant format string and the values it's given (docs/format_strings.md): each placeholder has a
	 * value, its options are well formed, and they suit the value's type.
	 */
	static void check_format_string(Checker& checker, ast::Node* literal, const std::vector<std::pair<ast::Node*, Value>>& values) {
		const std::string text = ast::string_value(literal);
		for (const FormatPlaceholder& placeholder : format_placeholders(text)) {
			const std::string written = text.substr(placeholder.offset, placeholder.length);
			if (!placeholder.valid) {
				error_at(checker, ErrorCode::E4034, literal, std::format("{} has options that aren't well formed, like %{{08x}} or %{{>10}}",
					written));
				continue;
			}
			if (placeholder.numbered_zero) {
				error_at(checker, ErrorCode::E4034, literal, "%0 names no value: values are numbered from %1");
				continue;
			}
			if (placeholder.value >= values.size()) {
				error_at(checker, ErrorCode::E4034, literal, std::format("{} is for value {}, but there {} only {}", written,
					placeholder.value + 1, values.size() == 1 ? "is" : "are", values.size()));
				continue;
			}
			const FormatSpec& spec = placeholder.spec;
			TypeInfo const* type = base_of(default_type(values[placeholder.value].second));
			if (type == nullptr || TypeInfoVariant::ANY == type->variant || TypeInfoVariant::ARCHETYPE == type->variant) {
				continue;
			}
			const TypeInfoVariant variant = type->variant;
			const bool integral = TypeInfoVariant::INTEGER == variant || TypeInfoVariant::CHAR == variant
				|| TypeInfoVariant::BOOLEAN == variant || TypeInfoVariant::ENUM == variant || TypeInfoVariant::POINTER == variant
				|| TypeInfoVariant::FUNCTION == variant;
			const bool number = TypeInfoVariant::INTEGER == variant || TypeInfoVariant::FLOAT == variant || spec.kind != 0;
			std::string problem;
			if (spec.kind != 0 && !integral) {
				problem = std::format("{} is written as a number in base {}, which {} isn't", written,
					spec.kind == 'b' ? "2" : spec.kind == 'o' ? "8" : spec.kind == 'd' ? "10" : "16", to_string(default_type(values[placeholder.value].second)));
			}
			else if ((spec.plus || spec.zeros) && !number) {
				problem = std::format("{} gives a number a sign or zeros, but {} isn't one", written,
					to_string(default_type(values[placeholder.value].second)));
			}
			else if (spec.prefix && !(spec.kind == 'x' || spec.kind == 'X' || spec.kind == 'b' || spec.kind == 'o'
				|| (spec.kind == 0 && (TypeInfoVariant::POINTER == variant || TypeInfoVariant::FUNCTION == variant)))) {
				problem = std::format("{} has # for a 0x, 0b or 0o prefix, which needs x, X, b or o", written);
			}
			else if (spec.has_precision && TypeInfoVariant::FLOAT != variant && TypeInfoVariant::STRING != variant) {
				problem = std::format("{} has a precision, which is for floats and strings, not {}", written,
					to_string(default_type(values[placeholder.value].second)));
			}
			if (!problem.empty()) {
				error_at(checker, ErrorCode::E4034, literal, problem);
			}
		}
	}

	/*
	 * A value given to a #crosses_threads parameter, like a new thread's data, can't reach anything
	 * #thread_bound: checked by the value's own type, even when it's passed as an any
	 * (docs/multitasking.md, Values That Stay on Their Thread).
	 */
	static void require_stays(Checker& checker, const Value& value, const FunctionInput& input, TypeInfoFunction const* function,
		const ast::Node* where) {

		if (!input.crosses_threads || ValueKind::VALUE != value.kind) {
			return;
		}
		TypeInfo const* bound = thread_bound_part(value.type);
		if (bound == nullptr) {
			return;
		}
		const std::string given = to_string(value.type);
		const std::string reason = same_type(bound, value.type) ? std::format("{} is #thread_bound", given)
			: std::format("{} reaches {}, which is #thread_bound", given, to_string(bound));
		error_at(checker, ErrorCode::E4036, where, std::format("{}, so it can't be given to {}, which goes to another thread",
			reason, input.name != nullptr ? text_of(input.name) : std::string("a parameter")));
		(void)function;
	}

	Progress check_type_default(WorkThreadData& executor, const FunctionInput& input);

	static size_t next_positional(const std::vector<FunctionInput>& inputs, size_t parameter);

	// A value whose type comes from where it goes: .{...}, .Member, .[...] or null.
	static bool takes_type_from_place(const ast::Node* node) {
		const ast::NodeType type = node->node_type;
		return ast::NodeType::ENUM_SHORTHAND == type || TokenType::KEYWORD_NULL == node->value.type
			|| ((ast::NodeType::STRUCT_LITERAL == type || ast::NodeType::ARRAY_LITERAL == type) && TokenType::SYM_DOT == node->value.type);
	}

	static Progress check_arguments(Checker& checker, ast::Node* where, TypeInfoFunction const* function,
		const Arguments& arguments, const std::vector<InternedString>& names, const std::vector<Value>& piped) {

		/*
		 * Parameters' types only had to be declared for the signature: wait until they're laid out,
		 * since whether a value fits an optional or a union depends on its variants
		 */
		for (const FunctionInput& input : function->input) {
			if (input.type != nullptr && !input.type->complete) {
				Progress progress = require_complete(checker.walk, where, input.type);
				if (progress != Progress::DONE) {
					return progress;
				}
			}
		}
		std::vector<bool> given(function->input.size(), false);
		size_t parameter = 0;
		(void)piped;
		// Which parameter each positional argument goes to, kept when a variadic parameter has others after it
		std::vector<uint32_t> argument_parameters;
		/*
		 * A format_string parameter followed by any... values, like log_info's: a constant one is checked
		 * against them (docs/format_strings.md), unless they're passed on as a view
		 */
		ast::Node* format_literal = nullptr;
		std::vector<std::pair<ast::Node*, Value>> format_values;
		bool format_values_known = true;
		auto takes_format = [&](size_t index) {
			const FunctionInput& input = function->input[index];
			return input.name != nullptr && text_of(input.name) == "format_string" && is_variant(input.type, TypeInfoVariant::STRING)
				&& index + 1 < function->input.size() && function->input[index + 1].is_varargs
				&& is_variant(function->input[index + 1].type, TypeInfoVariant::ANY);
		};
		for (size_t i = 0; i < arguments.positional.size(); ++i) {
			const Positional& positional = arguments.positional[i];
			ast::Node* argument = positional.node != nullptr ? positional.node : where;
			if (parameter >= function->input.size()) {
				error_at(checker, ErrorCode::E4018, argument, std::format("too many arguments, {} takes {}",
					to_string(function), function->input.size()));
				return Progress::DONE;
			}
			Value value;
			bool checked_already = false;
			if (function->input[parameter].is_varargs && function->input[parameter].type != nullptr) {
				/*
				 * Each value is one of the varargs while it fits them, unless the first is a view of them, which is
				 * passed on whole; the first value after them that doesn't goes to the parameter after them. A value
				 * that takes its type from where it goes, like .{...}, is the varargs' (docs/functions.md, Variable
				 * Arguments).
				 */
				const bool followed = next_positional(function->input, parameter) < function->input.size();
				const bool placed = positional.node != nullptr && takes_type_from_place(positional.node);
				Progress progress = positional_value(checker, positional, followed && !placed ? nullptr : function->input[parameter].type,
					value);
				if (progress != Progress::DONE) {
					return progress;
				}
				TypeInfo const* passed = ValueKind::VALUE == value.kind ? base_of(value.type) : nullptr;
				const bool passed_on = !given[parameter] && passed != nullptr && TypeInfoVariant::ARRAY == passed->variant
					&& ArrayType::VIEW == static_cast<TypeInfoArray const*>(passed)->array_type
					&& same_type(static_cast<TypeInfoArray const*>(passed)->element_type, function->input[parameter].type);
				if (passed_on) {
					given[parameter] = true;
					format_values_known = false;
					argument_parameters.push_back(static_cast<uint32_t>(parameter));
					++parameter;
					continue;
				}
				while (function->input[parameter].is_varargs && next_positional(function->input, parameter) < function->input.size()
					&& !placed && ValueKind::POISONED != value.kind && !fits(value, function->input[parameter].type)) {
					parameter = next_positional(function->input, parameter);
				}
				const FunctionInput& input = function->input[parameter];
				if (input.is_varargs) {
					given[parameter] = true;
					argument_parameters.push_back(static_cast<uint32_t>(parameter));
					format_values.emplace_back(argument, value);
					require_fit(checker, value, input.type, argument, std::format("{}", text_of(input.name)));
					if (!checker.intrinsic_arguments) {
						require_secret_fits(checker, value.is_secret, input.type, false, argument, std::format("{}", text_of(input.name)));
					}
					require_stays(checker, value, input, function, argument);
					continue;
				}
				checked_already = true;
			}
			const FunctionInput& input = function->input[parameter];
			TypeInfo* expected = input.type;
			if (!checked_already) {
				Progress progress = positional_value(checker, positional, expected, value);
				if (progress != Progress::DONE) {
					return progress;
				}
			}
			argument_parameters.push_back(static_cast<uint32_t>(parameter));
			require_fit(checker, value, expected, argument,
				input.name != nullptr ? std::format("{}", text_of(input.name)) : std::string("the argument"));
			if (!checker.intrinsic_arguments) {
				require_secret_fits(checker, value.is_secret, expected, false, argument,
					input.name != nullptr ? std::format("{}", text_of(input.name)) : std::string("the parameter"));
			}
			require_stays(checker, value, input, function, argument);
			if (takes_format(parameter) && positional.node != nullptr && ast::NodeType::LITERAL == positional.node->node_type
				&& TokenType::LITERAL_STRING == positional.node->value.type) {
				format_literal = positional.node;
			}
			given[parameter] = true;
			++parameter;
		}
		if (format_literal != nullptr && format_values_known) {
			check_format_string(checker, format_literal, format_values);
		}
		bool split = false;
		for (size_t i = 0; i + 1 < function->input.size(); ++i) {
			split = split || function->input[i].is_varargs;
		}
		if (split && checker.record != nullptr) {
			checker.record->argument_parameters[where] = std::move(argument_parameters);
		}
		for (const auto& [name, argument] : arguments.named) {
			size_t index = function->input.size();
			for (size_t i = 0; i < function->input.size(); ++i) {
				InternedString parameter_name = function->input[i].name != nullptr ? function->input[i].name
					: (i < names.size() ? names[i] : nullptr);
				if (parameter_name != nullptr && *parameter_name == *name) {
					index = i;
				}
			}
			if (index == function->input.size()) {
				error_at(checker, ErrorCode::E4018, argument, std::format("there's no parameter named {}", text_of(name)));
				continue;
			}
			if (given[index]) {
				error_at(checker, ErrorCode::E4018, argument, std::format("{} is given twice", text_of(name)));
			}
			given[index] = true;
			Value value;
			Progress progress = check_expression(checker, argument, function->input[index].type, value);
			if (progress != Progress::DONE) {
				return progress;
			}
			require_fit(checker, value, function->input[index].type, argument, text_of(name));
			require_stays(checker, value, function->input[index], function, argument);
		}
		for (size_t i = 0; i < function->input.size(); ++i) {
			if (!given[i] && !function->input[i].has_default && !function->input[i].is_varargs) {
				error_at(checker, ErrorCode::E4018, where, std::format("{} needs a value for {}",
					to_string(function), text_of(function->input[i].name)));
				break;
			}
		}
		// The defaults it leaves out that are a function type's, checked once each
		for (size_t i = 0; i < function->input.size(); ++i) {
			const FunctionInput& input = function->input[i];
			if (!given[i] && input.default_value != nullptr && !input.default_in_body) {
				Progress progress = check_type_default(checker.walk.executor, input);
				if (progress != Progress::DONE) {
					return progress;
				}
			}
		}
		return Progress::DONE;
	}

	/*
	 * A function type's default (docs/functions.md, Defaults in Function Types), checked like a function's:
	 * with the names the package and file it's written in see, with a context, and no locals. The
	 * declaration naming the type checks it, or for a type written in place, the first call that leaves it
	 * out; work that has to wait comes back to it. What checking finds is kept for the generator.
	 */
	Progress check_type_default(WorkThreadData& executor, const FunctionInput& input) {
		NameRegistry& names = executor.program_info->names;
		{
			// Checked, or being checked by other work, which reports what's wrong with it
			std::scoped_lock<std::mutex> lock(names.type_defaults_mutex);
			if (names.type_defaults.contains(input.default_value)) {
				return Progress::DONE;
			}
			auto [claim, claimed] = names.type_default_checkers.emplace(input.default_value, executor.current_work);
			if (!claimed && claim->second != executor.current_work) {
				return Progress::DONE;
			}
		}
		Walk walk{
			executor,
			input.default_package,
			input.default_file,
			find_file(executor.program_info, input.default_package, input.default_file),
			nullptr,
			nullptr,
			file_path_of(input.default_package, input.default_file),
			{},
			{},
			{},
		};
		auto checked = std::make_shared<CheckedBody>();
		Checker inner(walk);
		inner.record = checked.get();
		inner.has_context = true;
		inner.scopes.emplace_back();
		Value value;
		Progress progress = check_expression(inner, input.default_value, input.type, value);
		if (progress != Progress::DONE) {
			return progress;
		}
		require_fit(inner, value, input.type, input.default_value, "this default");
		std::scoped_lock<std::mutex> lock(names.type_defaults_mutex);
		names.type_defaults.emplace(input.default_value, checked);
		return Progress::DONE;
	}

	static Value call_result_of(TypeInfoFunction const* function) {
		Value value = nothing();
		if (function->output.size() == 1) {
			value = typed(function->output[0].type);
		}
		else if (function->output.size() > 1) {
			value.kind = ValueKind::RESULTS;
			for (const FunctionOutput& output : function->output) {
				value.results.push_back(output.type);
			}
		}
		value.never_returns = function->never_returns;
		return value;
	}

	// Without a context, only what takes none can be called: intrinsics, and #no_context functions.
	static void require_context_for(Checker& checker, const ast::Node* where, TypeInfoFunction const* function, Declaration* declaration) {
		if (checker.has_context || function->no_context) {
			return;
		}
		Declaration* written = declaration != nullptr && declaration->generic != nullptr ? declaration->generic : declaration;
		const bool intrinsic = written != nullptr && is_base_package(written->package_path) && function_body(written) == nullptr;
		if (!intrinsic) {
			error_at(checker, ErrorCode::E4027, where,
				"without a context, only intrinsics and #no_context functions can be called; push one with push_context ... from first");
		}
	}

	// The value a call gives: nothing, its result, or its several results.
	static Value call_result(TypeInfoFunction const* function, Declaration* declaration) {
		Value value = call_result_of(function);
		value.called = function;
		value.called_declaration = declaration;
		return value;
	}


	/*
	 * A call to a generic function: binds its generic parameters explicitly, from compile-time
	 * parameters (one with the same name), and from the arguments' types, then calls the instance
	 * for those (docs/types.md, Binding a Function's Generic Parameters).
	 */
	static Progress check_generic_call(Checker& checker, ast::Node* where, Value& callee,
		const std::vector<ast::Node*>& argument_nodes, const std::vector<Value>& piped) {

		Declaration* generic = callee.declaration;
		ast::Node* function = function_node(generic);
		const std::vector<std::string> generics = generic_names(function);
		const std::vector<Parameter> parameters = parameters_of(function);
		const Arguments arguments = split_arguments(checker, argument_nodes, piped, where);
		std::map<std::string, TypeInfo*> bound;
		std::map<std::string, ConstantValue> bound_values;
		// A compile-time argument that isn't a constant is reported already
		bool binding_failed = false;
		std::set<std::string> explicit_names;
		/*
		 * Giving a value or overriding a derived parameter, like scaled[int, 4] or sum[u8[], u64], gives
		 * the ones before it too, since they're positional, so those aren't given twice even when the
		 * arguments would bind them
		 */
		size_t needed_before = 0;
		{
			size_t index = 0;
			for (ast::Node* child : function->children) {
				if (ast::NodeType::GENERIC_TAG != child->node_type) {
					continue;
				}
				for (ast::Node* parameter : child->children) {
					const bool unbound = ast::NodeType::DERIVED_PARAMETER == parameter->node_type
						|| generic_parameter_is_value(checker.walk.executor.program_info->names, generic, index);
					if (index < callee.generic_arguments.size() && unbound) {
						needed_before = index;
					}
					++index;
				}
			}
		}
		for (size_t i = 0; i < callee.generic_arguments.size() && i < generics.size(); ++i) {
			if (callee.generic_arguments[i] == nullptr && i < callee.generic_values.size()) {
				bound_values[generics[i]] = callee.generic_values[i];
			}
			else {
				bound[generics[i]] = callee.generic_arguments[i];
			}
			// A mut argument says more than the arguments would, so it isn't given twice
			if (i >= needed_before && !is_mutable_argument(callee.generic_arguments[i])) {
				explicit_names.insert(generics[i]);
			}
		}
		// Each argument, matched to its parameter, binds what it can
		auto parameter_for = [&](size_t position, InternedString name) -> const Parameter* {
			if (name == nullptr) {
				return position < parameters.size() ? &parameters[position] : nullptr;
			}
			for (const Parameter& parameter : parameters) {
				if (parameter.name != nullptr && *parameter.name == *name) {
					return &parameter;
				}
			}
			return nullptr;
		};
		auto bind = [&](const Parameter* parameter, const Positional& positional) -> Progress {
			if (parameter == nullptr) {
				return Progress::DONE;
			}
			ast::Node* argument = positional.node != nullptr ? positional.node : where;
			const std::string name = text_of(parameter->name);
			const bool compile_time = std::find(generics.begin(), generics.end(), name) != generics.end();
			const bool takes_type = parameter->type != nullptr && is_text(parameter->type->value.value, "type")
				&& parameter->type->children.empty();
			if (compile_time && !takes_type && !positional.has_value) {
				// A compile-time value: a constant, which the instance is made for (docs/types.md)
				if (ast::NodeType::IDENTIFIER == argument->node_type && find_local(checker, argument) != nullptr
					&& !checker.walk.generic_values.contains(text_of(argument->value.value))) {
					error_at(checker, ErrorCode::E4010, argument, std::format("{} is passed to {}, a compile-time parameter, so it must be a constant, not a variable",
						text_of(argument->value.value), name));
					binding_failed = true;
					return Progress::DONE;
				}
				ConstantValue constant;
				Progress progress = evaluate_in(checker.walk, argument, constant);
				if (progress == Progress::FAILED) {
					binding_failed = true;
					return Progress::DONE;
				}
				if (progress != Progress::DONE) {
					return progress;
				}
				bound_values[name] = constant;
				return Progress::DONE;
			}
			/*
			 * A shorthand, like .Second or .{x = 1}, has no type of its own to bind anything with: it's checked
			 * once the instance's parameters say what it is
			 */
			const bool shorthand = !positional.has_value && (ast::NodeType::ENUM_SHORTHAND == argument->node_type
				|| ((ast::NodeType::STRUCT_LITERAL == argument->node_type || ast::NodeType::ARRAY_LITERAL == argument->node_type)
					&& TokenType::SYM_DOT == argument->value.type));
			if (shorthand && !compile_time) {
				return Progress::DONE;
			}
			Value value;
			Progress progress = positional_value(checker, positional, nullptr, value);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (compile_time) {
				if (ValueKind::TYPE == value.kind) {
					if (explicit_names.contains(name)) {
						report_warning(WarningCode::W4000, checker.walk.file_path, argument->value.line_number,
							argument->value.column_number, std::format("{} is given twice", name));
					}
					bound[name] = value.type;
				}
				return Progress::DONE;
			}
			TypeInfo* type = default_type(value);
			if (parameter->is_varargs && type != nullptr) {
				TypeInfo const* array = base_of(type);
				if (array != nullptr && TypeInfoVariant::ARRAY == array->variant) {
					type = static_cast<TypeInfoArray const*>(array)->element_type;
				}
			}
			std::map<std::string, TypeInfo*> inferred;
			unify(checker, parameter->type, type, inferred, bound_values, generics);
			// view_of from a ptr[mut T] is view_of[mut T], whose elements can be changed (docs/types.md, Views of Memory)
			TypeInfo const* pointer = type != nullptr ? base_of(type) : nullptr;
			if (is_text(generic->name, "view_of") && is_compiler_provided(generic->package_path) && inferred.contains("T")
				&& pointer != nullptr && TypeInfoVariant::POINTER == pointer->variant
				&& static_cast<TypeInfoPointer const*>(pointer)->is_mutable) {
				inferred["T"] = mutable_argument(checker.walk, inferred["T"]);
			}
			for (const auto& [generic_name, generic_type] : inferred) {
				if (explicit_names.contains(generic_name)) {
					report_warning(WarningCode::W4000, checker.walk.file_path, argument->value.line_number,
						argument->value.column_number, std::format("{} is given twice", generic_name));
				}
				bound.emplace(generic_name, generic_type);
			}
			return Progress::DONE;
		};
		for (size_t i = 0; i < arguments.positional.size(); ++i) {
			// Past the last parameter, the rest go to a varargs one
			const size_t position = i < parameters.size() || parameters.empty() ? i : parameters.size() - 1;
			Progress progress = bind(parameter_for(position, nullptr), arguments.positional[i]);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		for (const auto& [name, argument] : arguments.named) {
			Progress progress = bind(parameter_for(0, name), Positional{ argument, false, {} });
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		if (binding_failed) {
			callee = poisoned();
			return Progress::DONE;
		}
		// Derived parameters, like E = element_of(C), from what's bound (docs/types.md, Derived Parameters)
		Progress derived = bind_derived(checker.walk, where, generic, bound, bound_values);
		if (derived == Progress::FAILED) {
			callee = poisoned();
			return Progress::DONE;
		}
		if (derived != Progress::DONE) {
			return derived;
		}
		std::vector<TypeInfo*> instance_arguments;
		std::vector<ConstantValue> instance_values;
		for (const std::string& name : generics) {
			auto value = bound_values.find(name);
			if (value != bound_values.end()) {
				instance_arguments.push_back(nullptr);
				instance_values.push_back(value->second);
				continue;
			}
			instance_values.push_back({});
			auto iter = bound.find(name);
			if (iter == bound.end() || iter->second == nullptr) {
				callee = error_at(checker, ErrorCode::E4023, where, std::format("nothing binds {} in a call to {}; give it as {}[...]",
					name, text_of(generic->name), text_of(generic->name)));
				return Progress::DONE;
			}
			instance_arguments.push_back(iter->second);
		}
		Declaration* instance = instance_of(checker.walk, generic, instance_arguments, instance_values);
		// Its constraints, and the functions it's given, checked here, where it's made (docs/types.md, Constraints)
		Progress progress = check_constraints(checker.walk, where, generic, instance);
		if (progress == Progress::DONE) {
			progress = check_function_arguments(checker.walk, where, generic, instance);
		}
		if (progress == Progress::FAILED) {
			callee = poisoned();
			return Progress::DONE;
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		progress = require_resolved(checker.walk, where, instance, Need::RESOLVED);
		if (progress == Progress::FAILED) {
			callee = poisoned();
			return Progress::DONE;
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		auto signature = static_cast<TypeInfoFunction const*>(instance->value_type);
		if (signature == nullptr) {
			callee = poisoned();
			return Progress::DONE;
		}
		std::vector<InternedString> names;
		for (const Parameter& parameter : parameters) {
			names.push_back(parameter.name);
		}
		progress = check_arguments(checker, where, signature, arguments, names, piped);
		if (progress != Progress::DONE) {
			return progress;
		}
		require_context_for(checker, where, signature, instance);
		callee = call_result(signature, instance);
		return Progress::DONE;
	}

	/*
	 * real(x), imag(x), jmag(q) and kmag(q), a complex number's or a quaternion's part; conj(x), its conjugate; abs(x),
	 * its magnitude, as its parts' float, or an integer's or a float's absolute value (docs/types.md, Complex Numbers and
	 * Quaternions). An untyped number is the type it defaults to.
	 */
	static Progress check_number_builtin(Checker& checker, ast::Node* argument, const std::string& name, const Value& given,
		Value& callee) {

		if (ValueKind::POISONED == given.kind) {
			callee = poisoned();
			return Progress::DONE;
		}
		TypeInfo* type = native_of(default_type(given));
		const bool quaternion = is_variant(type, TypeInfoVariant::QUATERNION);
		if (name == "abs" && (is_integer(type) || is_float(type))) {
			callee = typed(type);
			return Progress::DONE;
		}
		if (!is_composite(type) || ((name == "jmag" || name == "kmag") && !quaternion)) {
			const std::string takes = name == "abs" ? "a number" : name == "jmag" || name == "kmag" ? "a quaternion"
				: "a complex number or a quaternion";
			callee = error_at(checker, ErrorCode::E4015, argument, std::format("{} takes {}, not {}", name, takes, describe(given)));
			return Progress::DONE;
		}
		callee = name == "conj" ? typed(type) : typed(static_cast<TypeInfoComposite const*>(base_of(type))->part_type);
		return Progress::DONE;
	}

	// size_of, align_of and the other builtin functions (docs/types.md).
	static Progress check_builtin_call(Checker& checker, ast::Node* where, Value& callee,
		const std::vector<ast::Node*>& arguments) {

		const std::string name = text_of(callee.name);
		if (name == "todo") {
			// todo(message := ..., location := ...): code still to write, which never returns
			if (arguments.size() > 2) {
				callee = error_at(checker, ErrorCode::E4018, where, "todo takes a message, and a location");
				return Progress::DONE;
			}
			if (!arguments.empty()) {
				Value message;
				Progress progress = check_expression(checker, arguments[0], BUILTIN_string, message);
				if (progress != Progress::DONE) {
					return progress;
				}
				require_fit(checker, message, BUILTIN_string, arguments[0], "todo's message");
			}
			callee = nothing();
			callee.never_returns = true;
			return Progress::DONE;
		}
		std::vector<Value> values;
		for (ast::Node* argument : arguments) {
			Value value;
			if (name == "offset_of" && !values.empty()) {
				values.push_back(value); // a member's name, not a value
				continue;
			}
			Progress progress = check_expression(checker, argument, nullptr, value);
			if (progress != Progress::DONE) {
				return progress;
			}
			values.push_back(value);
		}
		const size_t expected_count = name == "offset_of" || name == "types_are_aliases" ? 2 : 1;
		if (values.size() != expected_count) {
			callee = error_at(checker, ErrorCode::E4018, where, std::format("{} takes {} argument{}", name,
				expected_count, expected_count == 1 ? "" : "s"));
			return Progress::DONE;
		}
		if (is_number_builtin(name)) {
			return check_number_builtin(checker, arguments[0], name, values[0], callee);
		}
		// type_info_of and types_are_aliases also take type values, like an any's type
		const bool takes_type = name != "type_of";
		const bool takes_type_values = name == "type_info_of" || name == "types_are_aliases";
		const size_t typed_count = name == "types_are_aliases" ? 2 : 1;
		for (size_t i = 0; i < typed_count; ++i) {
			const bool type_value_given = takes_type_values && ValueKind::VALUE == values[i].kind
				&& is_variant(values[i].type, TypeInfoVariant::TYPE);
			if (takes_type && ValueKind::TYPE != values[i].kind && ValueKind::POISONED != values[i].kind && !type_value_given) {
				callee = error_at(checker, ErrorCode::E4015, arguments[i], std::format("{} takes a type", name));
				return Progress::DONE;
			}
		}
		if (name == "size_of" || name == "align_of" || name == "offset_of") {
			if (ValueKind::TYPE == values[0].kind) {
				Progress progress = require_complete(checker.walk, arguments[0], values[0].type);
				if (progress != Progress::DONE) {
					return progress;
				}
			}
			callee = typed(BUILTIN_usize);
		}
		else if (name == "type_of") {
			callee = typed(BUILTIN_type);
		}
		else if (name == "types_are_aliases") {
			callee = typed(BUILTIN_bool);
		}
		else if (name == "type_info_of") {
			TypeInfo* info = nullptr;
			Progress progress = base_type(checker, where, "compiler", "TypeInfo", info);
			if (progress != Progress::DONE) {
				return progress;
			}
			callee = typed(pointer_to(checker.walk, info, false, false, POINTER_SIZE));
		}
		else {
			callee = typed(values[0].type);
		}
		return Progress::DONE;
	}

	/*
	 * The function an #owned type names to release one, like SharedPtr's #owned(release): looked up in
	 * the file that declares the type (docs/memory.md, Owned Types).
	 */
	// The package and name of the function an #owned type names to release it, or false if it names none.
	static bool release_name_of(Checker& checker, TypeInfo const* type, InternedString& package, InternedString& name) {
		TypeInfo const* base = base_of(type);
		if (base == nullptr || TypeInfoVariant::STRUCT != base->variant) {
			return false;
		}
		auto structure = static_cast<TypeInfoStruct const*>(base);
		if (!structure->is_owned || structure->release_name == nullptr) {
			return false;
		}
		NameRegistry& names = checker.walk.executor.program_info->names;
		const Declaration* declared = structure->instance;
		if (declared == nullptr) {
			std::scoped_lock<std::mutex> lock(names.mutex);
			auto found = names.type_declarations.find(const_cast<TypeInfo*>(base));
			declared = found != names.type_declarations.end() ? found->second : nullptr;
		}
		if (declared == nullptr) {
			return false;
		}
		package = declared->package_path;
		if (structure->release_package != nullptr) {
			package = declared->file != nullptr ? imported_package(declared->file, structure->release_package) : nullptr;
		}
		name = structure->release_name;
		return package != nullptr;
	}

	static Declaration* release_function_of(Checker& checker, TypeInfo const* type) {
		InternedString package = nullptr;
		InternedString name = nullptr;
		if (!release_name_of(checker, type, package, name)) {
			return nullptr;
		}
		NameRegistry& names = checker.walk.executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.mutex);
		auto found = names.declarations.find(std::make_pair(package, name));
		return found != names.declarations.end() ? found->second : nullptr;
	}

	static TypeInfoVector const* vector_type_of(const Value& value);

	// Which argument of an x86_64 intrinsic is an instruction's immediate, counting from 1, or 0 for none.
	static size_t immediate_argument(const Declaration* declaration) {
		if (declaration == nullptr || declaration->package_path == nullptr
			|| !std::string_view(*declaration->package_path).starts_with("<base>")
			|| !std::string_view(*declaration->package_path).ends_with("x86_64")) {
			return 0;
		}
		return is_text(declaration->name, "aes_key_assist") ? 2 : is_text(declaration->name, "carryless_multiply") ? 3 : 0;
	}

	// compiler.declassify and compiler.secret, typed from what they're given (docs/memory.md, Secrets).
	static bool is_secret_function(const Declaration* declaration) {
		const Declaration* generic = declaration != nullptr && declaration->generic != nullptr ? declaration->generic : declaration;
		return is_compiler_function(generic, "declassify") || is_compiler_function(generic, "secret");
	}

	static bool is_vector_intrinsic(const Declaration* declaration) {
		static constexpr std::string_view NAMES[] = {
			"splat", "select", "rotate_lanes", "reduce_add", "reduce_and", "reduce_or", "reduce_xor", "any_true", "all_true",
			"rotate_left", "rotate_right", "byte_swap",
		};
		if (declaration == nullptr || declaration->package_path == nullptr
			|| !std::string_view(*declaration->package_path).starts_with("<base>")
			|| !std::string_view(*declaration->package_path).ends_with("intrinsics")) {
			return false;
		}
		const Declaration* generic = declaration->generic != nullptr ? declaration->generic : declaration;
		return std::find(std::begin(NAMES), std::end(NAMES), text_of(generic->name)) != std::end(NAMES);
	}

	/*
	 * The function type of a call to one of base/intrinsics' vector and bit functions, worked out from
	 * what it's given (docs/types.md, Vectors): its first argument's type, or for splat its generic
	 * argument. Null, with the error reported, when they don't fit.
	 */
	static Progress vector_intrinsic_type(Checker& checker, ast::Node* where, const Value& callee,
		const std::vector<ast::Node*>& arguments, TypeInfo*& result) {

		result = nullptr;
		const std::string name = text_of(callee.declaration->name);
		auto fail = [&](ast::Node* at, std::string message) {
			error_at(checker, ErrorCode::E4015, at != nullptr ? at : where, std::format("intrinsics.{} {}", name, message));
			return Progress::DONE;
		};
		if (name == "splat") {
			TypeInfo* type = callee.generic_arguments.size() == 1 ? callee.generic_arguments[0] : nullptr;
			if (!is_variant(type, TypeInfoVariant::VECTOR) || static_cast<TypeInfoVector const*>(base_of(type))->is_bits) {
				return fail(nullptr, "takes the vector type to fill, like splat[vector[u32, 4]](1)");
			}
			result = plain_function_type(checker.walk, { static_cast<TypeInfoVector const*>(base_of(type))->element_type }, type);
			return Progress::DONE;
		}
		const size_t subject = name == "select" ? 1 : 0;
		if (arguments.size() <= subject) {
			return fail(nullptr, "needs its arguments");
		}
		Value given;
		Progress progress = check_expression(checker, arguments[subject], nullptr, given);
		if (progress != Progress::DONE || ValueKind::POISONED == given.kind) {
			return progress;
		}
		TypeInfoVector const* vector = vector_type_of(given);
		TypeInfo* type = ValueKind::VALUE == given.kind ? given.type : nullptr;
		if (name == "declassify" || name == "secret") {
			TypeInfo* own = default_type(given);
			if (own == nullptr) {
				return fail(arguments[0], std::format("takes a value, not {}", describe(given)));
			}
			// What a #secret alias names is its public form; a #secret struct has none
			TypeInfo* result_type = own;
			while (name == "declassify" && result_type != nullptr && TypeInfoVariant::ALIAS == result_type->variant
				&& static_cast<TypeInfoAlias const*>(result_type)->is_secret) {
				result_type = static_cast<TypeInfoAlias const*>(result_type)->base_type;
			}
			if (name == "declassify" && is_secret_type(result_type)) {
				return fail(arguments[0], std::format("can't make {} public, since a #secret struct has no public form; declassify what's in it",
					to_string(own)));
			}
			result = plain_function_type(checker.walk, { own }, result_type);
			return Progress::DONE;
		}
		// A choice between integers or bools, without a branch
		if (name == "select" && vector == nullptr) {
			TypeInfo* own = default_type(given);
			if (own == nullptr || !(is_integer(own) || is_boolean(own) || is_enum(own))) {
				return fail(arguments[subject], std::format("chooses between vectors, integers, bools or enums, not {}", describe(given)));
			}
			result = plain_function_type(checker.walk, { BUILTIN_bool, own, own }, own);
			return Progress::DONE;
		}
		if (name == "rotate_left" || name == "rotate_right" || name == "byte_swap") {
			TypeInfo const* lane = vector != nullptr && !vector->is_bits ? vector->element_type : type;
			if (lane == nullptr || !is_integer(lane) || (name == "byte_swap" && base_of(lane)->size < 2)) {
				return fail(arguments[0], std::format("takes an integer{}, or a vector of them, not {}",
					name == "byte_swap" ? " of 2 bytes or more" : "", describe(given)));
			}
			result = name == "byte_swap" ? plain_function_type(checker.walk, { type }, type)
				: plain_function_type(checker.walk, { type, BUILTIN_u32 }, type);
			return Progress::DONE;
		}
		if (vector == nullptr || vector->is_bits) {
			return fail(arguments[subject], std::format("takes a vector with lanes, not {}", describe(given)));
		}
		TypeInfo* mask = vector_of(checker.walk, BUILTIN_bool, vector->count);
		if (name == "select") {
			result = plain_function_type(checker.walk, { mask, type, type }, type);
		}
		else if (name == "rotate_lanes") {
			Value count;
			progress = arguments.size() == 2 ? check_expression(checker, arguments[1], BUILTIN_usize, count) : Progress::DONE;
			if (progress != Progress::DONE) {
				return progress;
			}
			if (arguments.size() != 2 || ValueKind::UNTYPED_INTEGER != count.kind || !count.integer_known || count.integer_negative
				|| count.integer_magnitude >= vector->count) {
				return fail(arguments.size() == 2 ? arguments[1] : nullptr, std::format("takes a constant count, from 0 to {}",
					vector->count - 1));
			}
			result = plain_function_type(checker.walk, { type, BUILTIN_usize }, type);
		}
		else if (name == "any_true" || name == "all_true") {
			if (!is_boolean(vector->element_type)) {
				return fail(arguments[0], std::format("takes a vector of bools, not {}", to_string(type)));
			}
			result = plain_function_type(checker.walk, { type }, BUILTIN_bool);
		}
		else {
			if (!is_integer(vector->element_type)) {
				return fail(arguments[0], std::format("takes a vector of integers, not {}", to_string(type)));
			}
			result = plain_function_type(checker.walk, { type }, vector->element_type);
		}
		return Progress::DONE;
	}

	// A call: of a function value, a generic function, a builtin, or a union variant with its values.
	static Progress check_call(Checker& checker, ast::Node* where, const std::vector<ast::Node*>& arguments,
		Value& callee, const std::vector<Value>& piped) {

		/*
		 * compiler.release(value): a call to the function value's type names in #owned(...), so general
		 * code can release what it's given (docs/memory.md, Owned Types)
		 */
		if (ValueKind::GENERIC_FUNCTION == callee.kind && is_compiler_function(callee.declaration, "release") && arguments.size() == 1
			&& piped.empty()) {
			Value argument;
			Progress progress = check_expression(checker, arguments[0], nullptr, argument);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (ValueKind::POISONED == argument.kind) {
				callee = poisoned();
				return Progress::DONE;
			}
			/*
			 * Its type's #owned(...) is known once the type is complete, and the function it names once its package
			 * has declared it, either of which another thread may still be doing
			 */
			progress = complete_subject(checker, arguments[0], argument);
			if (progress != Progress::DONE) {
				return progress;
			}
			InternedString release_package = nullptr;
			InternedString release_name = nullptr;
			if (ValueKind::VALUE == argument.kind && release_name_of(checker, argument.type, release_package, release_name)) {
				progress = require_in(checker.walk, arguments[0], release_package, release_name, Need::DECLARED);
				if (progress != Progress::DONE) {
					return progress;
				}
			}
			Declaration* release = ValueKind::VALUE == argument.kind ? release_function_of(checker, argument.type) : nullptr;
			if (release == nullptr) {
				callee = error_at(checker, ErrorCode::E4035, arguments[0], std::format(
					"compiler.release needs a value of an #owned type that names its release function, not {}", describe(argument)));
				return Progress::DONE;
			}
			callee = declaration_value(checker, release);
		}

		const ValueKind kind = callee.kind;
		if (ValueKind::POISONED == kind) {
			for (ast::Node* argument : arguments) {
				Value ignored;
				Progress progress = check_expression(checker, argument, nullptr, ignored);
				if (progress != Progress::DONE) {
					return progress;
				}
			}
			return Progress::DONE;
		}
		// base/intrinsics' vector and bit functions: a function type worked out from what they're given
		if (ValueKind::GENERIC_FUNCTION == kind && (is_vector_intrinsic(callee.declaration) || is_secret_function(callee.declaration))
			&& piped.empty()) {
			TypeInfo* signature = nullptr;
			Progress progress = vector_intrinsic_type(checker, where, callee, arguments, signature);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (signature == nullptr) {
				callee = poisoned();
				return Progress::DONE;
			}
			Declaration* declaration = callee.declaration;
			callee = typed(signature);
			callee.declaration = declaration;
			return check_call(checker, where, arguments, callee, piped);
		}
		if (ValueKind::GENERIC_FUNCTION == kind) {
			return check_generic_call(checker, where, callee, arguments, piped);
		}
		if (ValueKind::BUILTIN_FUNCTION == kind) {
			return check_builtin_call(checker, where, callee, arguments);
		}
		/*
		 * compiler.require_any(A(T), B(T)) in a #constraint function: each alternative a call to a
		 * constraint, checked as one; the generator brackets them (docs/types.md, Constraints)
		 */
		if (is_compiler_function(callee.declaration, "require_any")) {
			for (ast::Node* alternative : arguments) {
				Value ignored;
				Progress progress = check_expression(checker, alternative, nullptr, ignored);
				if (progress != Progress::DONE) {
					return progress;
				}
			}
			callee = call_result(static_cast<TypeInfoFunction const*>(callee.declaration->value_type), callee.declaration);
			return Progress::DONE;
		}
		/*
		 * compiler.satisfies(constraints): worked out here, a constant, rather than its argument
		 * checked as a call (docs/types.md, Constraints)
		 */
		if (is_compiler_function(callee.declaration, "satisfies")) {
			ConstantValue satisfied;
			Progress progress = evaluate_satisfies(checker.walk, where, arguments, satisfied);
			if (progress == Progress::FAILED) {
				callee = poisoned();
				return Progress::DONE;
			}
			if (progress != Progress::DONE) {
				return progress;
			}
			if (checker.record != nullptr) {
				checker.record->satisfied[where] = satisfied.boolean;
			}
			callee = call_result(static_cast<TypeInfoFunction const*>(callee.declaration->value_type), callee.declaration);
			return Progress::DONE;
		}
		if (ValueKind::VARIANT == kind) {
			auto union_type = static_cast<TypeInfoUnion const*>(base_of(callee.type));
			const UnionVariant& variant = union_type->variants[callee.variant];
			if (arguments.size() != variant.types.size()) {
				callee = error_at(checker, ErrorCode::E4018, where, std::format("{} holds {} values, not {}",
					text_of(variant.name), variant.types.size(), arguments.size()));
				return Progress::DONE;
			}
			for (size_t i = 0; i < arguments.size(); ++i) {
				Value value;
				Progress progress = check_expression(checker, arguments[i], variant.types[i], value);
				if (progress != Progress::DONE) {
					return progress;
				}
				require_fit(checker, value, variant.types[i], arguments[i], text_of(variant.name));
			}
			const size_t index = callee.variant;
			callee = typed(callee.type);
			callee.variant = index;
			return Progress::DONE;
		}
		TypeInfo const* type = ValueKind::VALUE == kind ? base_of(callee.type) : nullptr;
		if (type == nullptr || TypeInfoVariant::FUNCTION != type->variant) {
			callee = error_at(checker, ErrorCode::E4021, where, std::format("{} can't be called", describe(callee)));
			return Progress::DONE;
		}
		auto function = static_cast<TypeInfoFunction const*>(type);
		require_context_for(checker, where, function, callee.declaration);
		std::vector<InternedString> names;
		if (callee.declaration != nullptr && DeclarationKind::FUNCTION == callee.declaration->kind) {
			if (ast::Node* node = function_node(callee.declaration)) {
				for (const Parameter& parameter : parameters_of(node)) {
					names.push_back(parameter.name);
				}
			}
		}
		// An intrinsic is an instruction or two, which takes the same time whatever it's given (docs/memory.md, Secrets)
		const bool intrinsic_call = callee.declaration != nullptr && is_base_package(callee.declaration->package_path)
			&& function_body(callee.declaration->generic != nullptr ? callee.declaration->generic : callee.declaration) == nullptr
			&& callee.declaration->foreign_library == nullptr;
		const bool outer_intrinsic = checker.intrinsic_arguments;
		checker.intrinsic_arguments = intrinsic_call;
		Progress progress = check_arguments(checker, where, function, split_arguments(checker, arguments, piped, where),
			names, piped);
		checker.intrinsic_arguments = outer_intrinsic;
		if (progress != Progress::DONE) {
			return progress;
		}
		bool secret_argument = false;
		for (const ast::Node* argument : arguments) {
			secret_argument = secret_argument || is_secret_node(checker, argument);
		}
		// An instruction's immediate, like x86_64.aes_key_assist's round constant, is a constant
		if (const size_t immediate = immediate_argument(callee.declaration); immediate != 0 && immediate <= arguments.size()) {
			Value constant;
			progress = check_expression(checker, arguments[immediate - 1], BUILTIN_u8, constant);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (ValueKind::POISONED != constant.kind && (ValueKind::UNTYPED_INTEGER != constant.kind || !constant.integer_known)) {
				error_at(checker, ErrorCode::E4015, arguments[immediate - 1], std::format("{}'s {} is part of the instruction, so it's a constant",
					text_of(callee.declaration->name), immediate == 2 ? "round constant" : "selector"));
			}
		}
		Declaration* called = callee.declaration != nullptr && DeclarationKind::FUNCTION == callee.declaration->kind
			? callee.declaration : nullptr;
		const bool declassify = called != nullptr && is_compiler_function(called->generic != nullptr ? called->generic : called, "declassify");
		const bool classify = called != nullptr && is_compiler_function(called->generic != nullptr ? called->generic : called, "secret");
		callee = call_result(function, called);
		callee.is_secret = classify || (intrinsic_call && secret_argument && !declassify);
		return Progress::DONE;
	}

	static bool is_postfix_marker(const ast::Node* node) {
		return ast::NodeType::DOT_ACCESS == node->node_type
			|| ast::NodeType::PAREN_GROUP == node->node_type
			|| ast::NodeType::ARRAY_DIMENSION == node->node_type
			|| (ast::NodeType::UNARY_OPERATOR == node->node_type
				&& TokenType::OPERATOR_DEREFERENCE == node->value.type);
	}

	// x^: what a pointer points to.
	static Progress dereference(Checker& checker, ast::Node* where, Value& value) {
		if (ValueKind::POISONED == value.kind) {
			return Progress::DONE;
		}
		TypeInfo const* type = ValueKind::VALUE == value.kind ? base_of(value.type) : nullptr;
		if (type == nullptr || TypeInfoVariant::POINTER != type->variant
			|| static_cast<TypeInfoPointer const*>(type)->base_type == nullptr) {
			value = error_at(checker, ErrorCode::E4020, where, std::format("{} can't be dereferenced; ^ needs a typed pointer",
				describe(value)));
			return Progress::DONE;
		}
		if (value.is_secret) {
			error_at(checker, ErrorCode::E4037, where, "a secret can't decide which memory is read, which would show in how long it takes");
		}
		auto pointer = static_cast<TypeInfoPointer const*>(type);
		value = typed(pointer->base_type);
		value.is_location = true;
		value.is_mutable = pointer->is_mutable;
		return read_place(checker, where, value);
	}

	/*
	 * A name and what follows it, flat: .member, (arguments), [index] or [type arguments], and ^.
	 * A type with brackets after it, like ptr[int] or Pair[int, string], is a type.
	 */
	static Progress check_postfix(Checker& checker, ast::Node* node, Value& value) {
		size_t next = 0;
		Progress progress = check_name(checker, node, value, next);
		if (progress != Progress::DONE) {
			return progress;
		}
		const bool type_head = ValueKind::TYPE == value.kind
			|| (is_text(node->value.value, "ptr") || std::string_view(*node->value.value).starts_with("relptr")
				|| is_text(node->value.value, "vector"));
		// The head's own value, at the head's qualifier for package.Name, or at the DOT_ACCESS before it
		if (next > 0) {
			record(checker, node->children[next - 1], value);
		}
		if (checker.record != nullptr) {
			CheckedNode& head = checker.record->heads[node];
			store_checked(head, value);
			head.next = next;
		}
		if (type_head && next < node->children.size()
			&& ast::NodeType::ARRAY_DIMENSION == node->children[next]->node_type && find_local(checker, node) == nullptr) {
			/*
			 * A chain after the type and its arguments, like Result[T, E].Error(e): the type alone, then the chain. Every
			 * bracket right after a type is the type's, like i8[10][5]'s, since a type can't be indexed
			 */
			size_t end = next + 1;
			while (end < node->children.size() && (ast::NodeType::ARRAY_DIMENSION == node->children[end]->node_type
				|| !is_postfix_marker(node->children[end]))) {
				++end;
			}
			if (end < node->children.size()) {
				std::vector<ast::Node*> chain(node->children.begin() + static_cast<std::ptrdiff_t>(end), node->children.end());
				node->children.erase(node->children.begin() + static_cast<std::ptrdiff_t>(end), node->children.end());
				TypeInfo* type = nullptr;
				progress = check_type(checker, node, Need::DECLARED, type);
				node->children.insert(node->children.end(), chain.begin(), chain.end());
				if (progress == Progress::FAILED) {
					value = poisoned();
					return Progress::DONE;
				}
				if (progress != Progress::DONE) {
					return progress;
				}
				value = type_value(type);
				if (checker.record != nullptr) {
					CheckedNode& head = checker.record->heads[node];
					store_checked(head, value);
					head.next = end;
				}
				return apply_postfix(checker, node, end, value);
			}
			TypeInfo* type = nullptr;
			progress = check_type(checker, node, Need::DECLARED, type);
			if (progress == Progress::FAILED) {
				value = poisoned();
				return Progress::DONE;
			}
			if (progress != Progress::DONE) {
				return progress;
			}
			value = type_value(type);
			return Progress::DONE;
		}
		return apply_postfix(checker, node, next, value);
	}

	// What follows a value, flat: .member, (arguments), [index] or [type arguments], and ^.
	static Progress apply_postfix(Checker& checker, ast::Node* node, size_t start, Value& value) {
		Progress progress = Progress::DONE;
		for (size_t i = start; i < node->children.size(); ++i) {
			ast::Node* child = node->children[i];
			std::vector<ast::Node*> arguments;
			while (i + 1 < node->children.size() && !is_postfix_marker(node->children[i + 1])) {
				arguments.push_back(node->children[++i]);
			}
			const ast::NodeType type = child->node_type;
			// A call on the right of |> holds its arguments inside its parentheses
			if (ast::NodeType::PAREN_GROUP == type && arguments.empty() && !child->children.empty()) {
				arguments.assign(child->children.begin(), child->children.end());
			}
			// A secret's members and elements are secrets, but not how many it has (docs/memory.md, Secrets)
			// What a pointer points to counts, like key.bytes through a ptr[Key]
			const bool was_secret = value.is_secret || (ValueKind::VALUE == value.kind && reaches_secret(value.type));
			const bool keeps_secret = was_secret && (ast::NodeType::ARRAY_DIMENSION == type || (ast::NodeType::DOT_ACCESS == type
				&& !arguments.empty() && !is_text(arguments[0]->value.value, "count") && !is_text(arguments[0]->value.value, "capacity")));
			if (ast::NodeType::DOT_ACCESS == type) {
				if (arguments.empty()) {
					value = error_at(checker, ErrorCode::E4017, child, "a member's name is missing");
					continue;
				}
				// The member's name is the first of what follows the dot; the rest is unusual
				progress = check_member(checker, arguments[0], arguments[0]->value.value, value);
			}
			else if (ast::NodeType::PAREN_GROUP == type) {
				// The last call in a chain takes what |> passed on its left
				bool last_call = true;
				for (size_t j = i + 1; j < node->children.size(); ++j) {
					if (ast::NodeType::PAREN_GROUP == node->children[j]->node_type) {
						last_call = false;
					}
				}
				std::vector<Value> piped;
				if (last_call) {
					piped = std::move(checker.piped);
					checker.piped.clear();
				}
				progress = check_call(checker, child, arguments, value, piped);
			}
			else if (ast::NodeType::ARRAY_DIMENSION == type) {
				if (ValueKind::GENERIC_FUNCTION == value.kind) {
					// Generic arguments given explicitly, like empty[string]() or push[u8, 4](...)
					for (ast::Node* argument : arguments) {
						if (generic_takes_value(checker.walk.executor.program_info->names, value.declaration, value.generic_arguments.size())) {
							if (ast::NodeType::IDENTIFIER == argument->node_type && find_local(checker, argument) != nullptr
								&& !checker.walk.generic_values.contains(text_of(argument->value.value))) {
								error_at(checker, ErrorCode::E4010, argument, std::format(
									"{} is a variable, but a generic argument that's a value must be a constant", text_of(argument->value.value)));
								progress = Progress::FAILED;
								break;
							}
							ConstantValue constant;
							progress = evaluate_in(checker.walk, argument, constant);
							if (progress != Progress::DONE) {
								break;
							}
							value.generic_arguments.push_back(nullptr);
							value.generic_values.resize(value.generic_arguments.size());
							value.generic_values.back() = constant;
							continue;
						}
						TypeInfo* argument_type = nullptr;
						progress = walk_names(checker.walk, argument, Need::DECLARED);
						if (progress == Progress::DONE) {
							progress = argument_type_of(checker.walk, argument, Need::DECLARED, argument_type);
						}
						if (progress != Progress::DONE) {
							break;
						}
						// Given with mut, like poke[mut int], or a parameter that was (docs/types.md, Mutability in Type Arguments)
						bool given_mut = (ast::NodeType::IDENTIFIER == argument->node_type || ast::NodeType::TYPE == argument->node_type)
							&& checker.walk.generic_mutable.contains(text_of(argument->value.value));
						for (const ast::Node* part : argument->children) {
							given_mut = given_mut || ast::NodeType::MUTABLE == part->node_type;
						}
						if (given_mut) {
							argument_type = mutable_argument(checker.walk, argument_type);
						}
						value.generic_arguments.push_back(argument_type);
					}
					/*
					 * Named with its arguments and not called, like release_in_place[T]: that instance, as a
					 * function value (docs/functions.md)
					 */
					const bool called = i + 1 < node->children.size() && ast::NodeType::PAREN_GROUP == node->children[i + 1]->node_type;
					if (progress == Progress::DONE && !called) {
						Declaration* generic = value.declaration;
						value.generic_values.resize(value.generic_arguments.size());
						Declaration* instance = instance_of(checker.walk, generic, value.generic_arguments, value.generic_values);
						progress = check_constraints(checker.walk, child, generic, instance);
						if (progress == Progress::DONE) {
							progress = check_function_arguments(checker.walk, child, generic, instance);
						}
						if (progress == Progress::DONE) {
							progress = require_resolved(checker.walk, child, instance, Need::RESOLVED);
						}
						if (progress == Progress::DONE) {
							value = declaration_value(checker, instance);
						}
					}
				}
				else {
					progress = check_index(checker, child, arguments, value);
				}
			}
			else {
				progress = dereference(checker, child, value);
			}
			if (progress == Progress::FAILED) {
				value = poisoned();
				progress = Progress::DONE;
			}
			if (progress != Progress::DONE) {
				return progress;
			}
			if (ValueKind::POISONED != value.kind && (keeps_secret || (ValueKind::VALUE == value.kind && is_secret_type(value.type)))) {
				value.is_secret = true;
			}
			// The value so far, at the node after it: a member's name, or the marker
			record(checker, ast::NodeType::DOT_ACCESS == type && !arguments.empty() ? arguments[0] : child, value);
		}
		return Progress::DONE;
	}

	static bool is_comparison(TokenType op) {
		return TokenType::OPERATOR_EQUAL == op || TokenType::OPERATOR_NOT_EQUAL == op
			|| TokenType::SYM_LT == op || TokenType::SYM_GT == op
			|| TokenType::OPERATOR_LESS_THAN_OR_EQUAL == op || TokenType::OPERATOR_GREATER_THAN_OR_EQUAL == op;
	}

	static bool is_shift(TokenType op) {
		return TokenType::OPERATOR_LEFT_SHIFT == op || TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC == op
			|| TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL == op;
	}

	static bool is_bitwise(TokenType op) {
		return TokenType::SYM_AMPERSAND == op || TokenType::OPERATOR_BITWISE_OR == op
			|| TokenType::OPERATOR_BITWISE_XOR == op;
	}

	static bool is_untyped(const Value& value) {
		const ValueKind kind = value.kind;
		return ValueKind::UNTYPED_INTEGER == kind || ValueKind::UNTYPED_FLOAT == kind
			|| ValueKind::UNTYPED_STRING == kind || ValueKind::UNTYPED_BOOLEAN == kind
			|| ValueKind::UNTYPED_COMPLEX == kind || ValueKind::UNTYPED_QUATERNION == kind
			|| ValueKind::NULL_VALUE == kind;
	}

	// An untyped number's place among them: an integer, a float, a complex number, a quaternion; -1 if it isn't one.
	static int number_rank(ValueKind kind) {
		return ValueKind::UNTYPED_INTEGER == kind ? 0 : ValueKind::UNTYPED_FLOAT == kind ? 1
			: ValueKind::UNTYPED_COMPLEX == kind ? 2 : ValueKind::UNTYPED_QUATERNION == kind ? 3 : -1;
	}

	/*
	 * The type two operands share: an untyped one takes the other's type; otherwise one converts
	 * to the other (docs/operators.md: identical or implicitly convertible).
	 */
	static bool common_type(const Value& left, const Value& right, Value& result) {
		if (is_untyped(left) && is_untyped(right)) {
			result = left;
			// Not the left's value: an operator's is worked out by fold_result
			result.integer_known = false;
			// Numbers take the widest kind among them: 1 + 0.5 is a float, 1 + 2i complex
			const int left_rank = number_rank(left.kind);
			const int right_rank = number_rank(right.kind);
			if (right_rank > left_rank) {
				result.kind = right.kind;
			}
			return left.kind == right.kind || (left_rank >= 0 && right_rank >= 0);
		}
		if (is_untyped(left)) {
			result = typed(right.type);
			return fits(left, right.type);
		}
		if (is_untyped(right)) {
			result = typed(left.type);
			return fits(right, left.type);
		}
		if (assignable(right.type, left.type)) {
			result = typed(left.type);
			return true;
		}
		if (assignable(left.type, right.type)) {
			result = typed(right.type);
			return true;
		}
		return false;
	}

	// An operand that's a value of some kind, rather than a type, package or function to call.
	static bool is_operand(const Value& value) {
		return ValueKind::VALUE == value.kind || is_untyped(value);
	}

	// A value's vector type, or null when it isn't a vector.
	static TypeInfoVector const* vector_type_of(const Value& value) {
		if (ValueKind::VALUE != value.kind || !is_variant(value.type, TypeInfoVariant::VECTOR)) {
			return nullptr;
		}
		return static_cast<TypeInfoVector const*>(base_of(value.type));
	}

	/*
	 * An operator on vectors, lane by lane (docs/types.md, Vectors): two of the same vector type, or
	 * one and an untyped literal, which goes in every lane. A shift takes a vector of amounts, or one
	 * unsigned amount for every lane. Comparisons give a vector of bools. v128 to v512 only take the
	 * bitwise operators; integer division isn't on vectors yet, since a lane of 0 has no panic to give.
	 */
	static void check_vector_binary(Checker& checker, ast::Node* node, TokenType op, const Value& left, const Value& right,
		Value& result) {

		const bool vector_left = vector_type_of(left) != nullptr;
		const Value& vector_side = vector_left ? left : right;
		const Value& other = vector_left ? right : left;
		TypeInfo* type = vector_side.type;
		auto vector = vector_type_of(vector_side);
		TypeInfo* lane = vector->element_type;
		const bool integer_lanes = is_integer(lane) && !vector->is_bits;
		const bool float_lanes = is_float(lane);
		const bool bool_lanes = is_boolean(lane);
		result = typed(type);
		if (TokenType::OPERATOR_AND == op || TokenType::OPERATOR_OR == op) {
			result = error_at(checker, ErrorCode::E4020, node, "&& and || take booleans; on vectors, & and | work lane by lane");
			return;
		}
		if (is_shift(op)) {
			const TypeInfoVector* amounts = vector_type_of(right);
			const bool amount_fits = (amounts != nullptr && same_type(right.type, type))
				|| (amounts == nullptr && ValueKind::VALUE == right.kind && is_integer(right.type) && !is_signed(right.type))
				|| (ValueKind::UNTYPED_INTEGER == right.kind && !right.integer_negative);
			if (!vector_left || !integer_lanes || !amount_fits) {
				result = error_at(checker, ErrorCode::E4020, node, std::format(
					"a vector's shift takes integer lanes, shifted by a vector of the same type or one unsigned amount, not {} and {}",
					describe(left), describe(right)));
			}
			return;
		}
		if (ValueKind::VALUE == other.kind && !same_type(other.type, type)) {
			result = error_at(checker, ErrorCode::E4015, node, std::format("{} and {} don't go together", describe(left),
				describe(right)));
			return;
		}
		if (ValueKind::VALUE != other.kind && (vector->is_bits || !fits(other, lane))) {
			if (!in_range(other, lane)) {
				report_out_of_range(checker, other, lane, node);
				result = poisoned();
				return;
			}
			result = error_at(checker, ErrorCode::E4015, node, std::format("{} can't go in every lane of {}", describe(other),
				to_string(type)));
			return;
		}
		if (vector->is_bits) {
			if (!is_bitwise(op)) {
				result = error_at(checker, ErrorCode::E4020, node, std::format("{} only takes &, | and ~; bit_cast it to a vector for lanes",
					to_string(type)));
			}
			return;
		}
		if (is_comparison(op)) {
			const bool ordered = TokenType::OPERATOR_EQUAL != op && TokenType::OPERATOR_NOT_EQUAL != op;
			if (ordered && !(integer_lanes || float_lanes)) {
				result = error_at(checker, ErrorCode::E4020, node, std::format("{} lanes can't be ordered", to_string(lane)));
				return;
			}
			result = typed(vector_of(checker.walk, BUILTIN_bool, vector->count));
			return;
		}
		bool valid = false;
		if (TokenType::OPERATOR_PLUS == op || TokenType::OPERATOR_MINUS == op || TokenType::OPERATOR_MULTIPLY == op) {
			valid = integer_lanes || float_lanes;
		}
		else if (TokenType::OPERATOR_DIVIDE == op) {
			valid = float_lanes;
		}
		else if (is_bitwise(op)) {
			valid = integer_lanes || bool_lanes;
		}
		if (!valid) {
			result = error_at(checker, ErrorCode::E4020, node, std::format("this operator doesn't apply to {}{}", to_string(type),
				TokenType::OPERATOR_DIVIDE == op || TokenType::OPERATOR_MODULUS == op || TokenType::OPERATOR_REMAINDER == op
				? ", since integer division isn't on vectors yet" : ""));
		}
	}

	// A known integer's value, as a sign and a magnitude: anything a u64 or an i64 holds, and their negations.
	struct KnownInteger {
		bool negative = false;
		uint64_t magnitude = 0;
	};

	enum class Folded : uint8_t {
		DONE,
		// Not worked out, like a bitwise operator on a negative, which depends on the type's size
		UNKNOWN,
		TOO_LARGE,
		DIVIDED_BY_ZERO,
	};

	static KnownInteger known_of(const Value& value) {
		return KnownInteger{ value.integer_negative, value.integer_magnitude };
	}

	static Folded add_known(KnownInteger a, KnownInteger b, KnownInteger& result) {
		if (a.negative == b.negative) {
			if (a.magnitude > UINT64_MAX - b.magnitude) {
				return Folded::TOO_LARGE;
			}
			result = { a.negative, a.magnitude + b.magnitude };
		}
		else if (a.magnitude >= b.magnitude) {
			result = { a.negative, a.magnitude - b.magnitude };
		}
		else {
			result = { b.negative, b.magnitude - a.magnitude };
		}
		result.negative = result.negative && result.magnitude != 0;
		return Folded::DONE;
	}

	/*
	 * An operator on two known integers, worked out exactly, as the language defines it (docs/operators.md):
	 * / and % truncated, %% floored, >> filling with the sign. Bitwise operators on negatives, and >>> on
	 * them, depend on the type's size, so they aren't worked out.
	 */
	static Folded fold_integers(TokenType op, KnownInteger a, KnownInteger b, KnownInteger& result) {
		const bool divides = TokenType::OPERATOR_DIVIDE == op || TokenType::OPERATOR_MODULUS == op
			|| TokenType::OPERATOR_REMAINDER == op;
		if (divides && b.magnitude == 0) {
			return Folded::DIVIDED_BY_ZERO;
		}
		if (TokenType::OPERATOR_PLUS == op) {
			return add_known(a, b, result);
		}
		if (TokenType::OPERATOR_MINUS == op) {
			b.negative = !b.negative && b.magnitude != 0;
			return add_known(a, b, result);
		}
		if (TokenType::OPERATOR_MULTIPLY == op) {
			if (a.magnitude != 0 && b.magnitude > UINT64_MAX / a.magnitude) {
				return Folded::TOO_LARGE;
			}
			result = { a.negative != b.negative, a.magnitude * b.magnitude };
		}
		else if (TokenType::OPERATOR_DIVIDE == op) {
			result = { a.negative != b.negative, a.magnitude / b.magnitude };
		}
		else if (TokenType::OPERATOR_MODULUS == op) {
			result = { a.negative, a.magnitude % b.magnitude };
		}
		else if (TokenType::OPERATOR_REMAINDER == op) {
			// Floored: the truncated one, moved to the divisor's sign
			const KnownInteger truncated{ a.negative, a.magnitude % b.magnitude };
			if (truncated.magnitude != 0 && a.negative != b.negative) {
				return add_known(truncated, b, result);
			}
			result = truncated;
		}
		else if (TokenType::OPERATOR_LEFT_SHIFT == op) {
			if (b.negative) {
				return Folded::UNKNOWN;
			}
			if (a.magnitude != 0 && (b.magnitude >= 64 || a.magnitude > (UINT64_MAX >> b.magnitude))) {
				return Folded::TOO_LARGE;
			}
			result = { a.negative, a.magnitude == 0 ? 0 : a.magnitude << b.magnitude };
		}
		else if (TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC == op || TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL == op) {
			if (b.negative || (a.negative && TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL == op)) {
				return Folded::UNKNOWN;
			}
			if (!a.negative) {
				result = { false, b.magnitude >= 64 ? 0 : a.magnitude >> b.magnitude };
			}
			else if (b.magnitude >= 64) {
				result = { true, 1 };
			}
			else {
				// Toward negative infinity, like the sign filling in: -5 >> 1 is -3
				const uint64_t shifted = a.magnitude >> b.magnitude;
				const bool lost = (a.magnitude & ((uint64_t{ 1 } << b.magnitude) - 1)) != 0;
				result = { true, shifted + (lost ? 1 : 0) };
			}
		}
		else if (is_bitwise(op)) {
			if (a.negative || b.negative) {
				return Folded::UNKNOWN;
			}
			result = { false, TokenType::SYM_AMPERSAND == op ? a.magnitude & b.magnitude
				: TokenType::OPERATOR_BITWISE_OR == op ? a.magnitude | b.magnitude : a.magnitude ^ b.magnitude };
		}
		else {
			return Folded::UNKNOWN;
		}
		result.negative = result.negative && result.magnitude != 0;
		return Folded::DONE;
	}

	/*
	 * An operator's untyped integer result, worked out when both sides are known, so it's checked
	 * against the type it becomes, and generated as one constant. One too large for any integer is an
	 * error, and so is dividing by a known zero, whatever the left is.
	 */
	static void fold_result(Checker& checker, ast::Node* node, TokenType op, const Value& left, const Value& right,
		Value& result) {

		// Only ~ itself is worked out in the type it's used as
		result.complement = false;
		const bool right_known = ValueKind::UNTYPED_INTEGER == right.kind && right.integer_known;
		const bool divides = TokenType::OPERATOR_DIVIDE == op || TokenType::OPERATOR_MODULUS == op
			|| TokenType::OPERATOR_REMAINDER == op;
		if (divides && right_known && right.integer_magnitude == 0) {
			result = error_at(checker, ErrorCode::E4015, node, "dividing by zero, which is known here");
			return;
		}
		if (ValueKind::UNTYPED_INTEGER != result.kind) {
			return;
		}
		result.integer_known = false;
		if (ValueKind::UNTYPED_INTEGER != left.kind || !left.integer_known || !right_known) {
			return;
		}
		KnownInteger folded;
		const Folded outcome = fold_integers(op, known_of(left), known_of(right), folded);
		if (Folded::TOO_LARGE == outcome) {
			result = error_at(checker, ErrorCode::E4015, node, std::format("this is too large for any integer, which go up to u64's {}",
				UINT64_MAX));
			return;
		}
		if (Folded::DONE == outcome) {
			result.integer_known = true;
			result.integer_negative = folded.negative;
			result.integer_magnitude = folded.magnitude;
		}
	}

	static Progress check_binary(Checker& checker, ast::Node* node, TypeInfo* expected, Value& result) {
		const TokenType op = node->value.type;
		ast::Node* left_node = node->children[0];
		ast::Node* right_node = node->children[1];
		Value left;
		Value right;
		if (TokenType::KEYWORD_OR_ELSE == op || TokenType::KEYWORD_OR_RETURN == op) {
			Progress progress = check_expression(checker, left_node, nullptr, left);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (ValueKind::POISONED == left.kind) {
				result = poisoned();
				return Progress::DONE;
			}
			progress = complete_subject(checker, left_node, left);
			if (progress != Progress::DONE) {
				return progress;
			}
			TypeInfo* held = ValueKind::VALUE == left.kind ? held_value(left.type) : nullptr;
			if (held == nullptr) {
				result = error_at(checker, ErrorCode::E4020, node, std::format("{} needs an optional or a result, not {}",
					TokenType::KEYWORD_OR_ELSE == op ? "or_else" : "or_return", describe(left)));
				return Progress::DONE;
			}
			if (TokenType::KEYWORD_OR_ELSE == op) {
				progress = check_expression(checker, right_node, held, right);
				if (progress != Progress::DONE) {
					return progress;
				}
				/*
				 * A default that never returns, like a call that stops the program, fits anything. For
				 * Result[void, E], the default is what to do instead: a call that returns nothing.
				 */
				if (held == BUILTIN_void) {
					if (ValueKind::NOTHING != right.kind && !right.never_returns) {
						error_at(checker, ErrorCode::E4015, right_node, std::format(
							"or_else on a result with nothing in Ok takes what to do instead, a call that returns nothing, not {}",
							describe(right)));
					}
				}
				else if (!right.never_returns) {
					require_fit(checker, right, held, right_node, "or_else's default");
				}
			}
			else {
				// What to return from the function instead
				TypeInfo* returned = checker.function != nullptr && checker.function->output.size() == 1
					? checker.function->output[0].type : nullptr;
				progress = check_expression(checker, right_node, returned, right);
				if (progress != Progress::DONE) {
					return progress;
				}
				if (checker.function == nullptr) {
					error_at(checker, ErrorCode::E4020, node, "or_return is only in a function");
				}
				else if (checker.function->output.empty()) {
					if (ValueKind::NOTHING != right.kind && ValueKind::POISONED != right.kind) {
						error_at(checker, ErrorCode::E4015, right_node, "this function returns nothing, so or_return void");
					}
				}
				else if (returned != nullptr) {
					require_fit(checker, right, returned, right_node, "or_return's value");
				}
			}
			result = typed(held);
			return Progress::DONE;
		}
		if (TokenType::OPERATOR_RANGE_EXCLUSIVE == op || TokenType::OPERATOR_RANGE_INCLUSIVE == op) {
			result = error_at(checker, ErrorCode::E4020, node, "a range is only for a for loop, a slice or a case");
			return Progress::DONE;
		}
		if (TokenType::OPERATOR_PIPE == op) {
			// a |> f(b): f(a, b), with every result of a, in order (docs/operators.md, Pipe operator)
			Progress progress = check_expression(checker, left_node, nullptr, left);
			if (progress != Progress::DONE) {
				return progress;
			}
			std::vector<Value> piped;
			if (ValueKind::RESULTS == left.kind) {
				for (TypeInfo* each : left.results) {
					piped.push_back(typed(each));
				}
			}
			else if (ValueKind::NOTHING != left.kind) {
				piped.push_back(left);
			}
			// The call on the right is flat in this node: its function, then (, then its arguments
			if (ast::NodeType::IDENTIFIER != right_node->node_type) {
				result = error_at(checker, ErrorCode::E4021, right_node, "the right of |> is a call");
				return Progress::DONE;
			}
			checker.piped = std::move(piped);
			progress = check_postfix(checker, right_node, result);
			if (progress == Progress::DONE) {
				progress = apply_postfix(checker, node, 2, result);
			}
			if (!checker.piped.empty() && progress == Progress::DONE) {
				error_at(checker, ErrorCode::E4021, right_node, "the right of |> is a call");
			}
			checker.piped.clear();
			return progress;
		}
		// An enum shorthand or literal takes the other side's type, so check that one first
		const bool right_first = ast::NodeType::ENUM_SHORTHAND == left_node->node_type
			|| ast::NodeType::LITERAL == left_node->node_type;
		TypeInfo* operand_expected = is_comparison(op) || TokenType::OPERATOR_AND == op
			|| TokenType::OPERATOR_OR == op ? nullptr : expected;
		Progress progress = check_expression(checker, right_first ? right_node : left_node, operand_expected,
			right_first ? right : left);
		if (progress != Progress::DONE) {
			return progress;
		}
		Value& first = right_first ? right : left;
		TypeInfo* other_expected = ValueKind::VALUE == first.kind && !is_shift(op) ? first.type : operand_expected;
		progress = check_expression(checker, right_first ? left_node : right_node, other_expected,
			right_first ? left : right);
		if (progress != Progress::DONE) {
			return progress;
		}
		if (ValueKind::POISONED == left.kind || ValueKind::POISONED == right.kind) {
			result = is_comparison(op) ? typed(BUILTIN_bool) : poisoned();
			return Progress::DONE;
		}
		/*
		 * An optional compared with what it holds, like error != OsError.NotFound, reads its variants, which
		 * its instance may not have yet if another thread is still making it
		 */
		if (is_comparison(op)) {
			progress = complete_subject(checker, left_node, left);
			if (progress == Progress::DONE) {
				progress = complete_subject(checker, right_node, right);
			}
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		// Type values compare exactly (docs/types.md, Comparing Type Values)
		const bool type_operand = ValueKind::TYPE == left.kind || ValueKind::TYPE == right.kind;
		if (type_operand && (TokenType::OPERATOR_EQUAL == op || TokenType::OPERATOR_NOT_EQUAL == op)) {
			for (const Value* operand : { &left, &right }) {
				if (ValueKind::TYPE != operand->kind && !(ValueKind::VALUE == operand->kind
					&& is_variant(operand->type, TypeInfoVariant::TYPE))) {
					result = error_at(checker, ErrorCode::E4015, node, std::format("a type compares with a type, not {}",
						describe(*operand)));
					return Progress::DONE;
				}
			}
			result = typed(BUILTIN_bool);
			return Progress::DONE;
		}
		if (!is_operand(left) || !is_operand(right)) {
			result = error_at(checker, ErrorCode::E4020, node, std::format("{} and {} aren't values to operate on",
				describe(left), describe(right)));
			return Progress::DONE;
		}
		if (vector_type_of(left) != nullptr || vector_type_of(right) != nullptr) {
			check_vector_binary(checker, node, op, left, right, result);
			return Progress::DONE;
		}
		// Endian-specific values are computed as their native types (docs/types.md, Endian-Specific Types)
		for (Value* operand : { &left, &right }) {
			if (ValueKind::VALUE == operand->kind) {
				operand->type = native_of(operand->type);
			}
		}
		// Raw pointers allow arithmetic with integers (docs/types.md, Pointers)
		const bool raw_left = ValueKind::VALUE == left.kind && is_pointer(left.type)
			&& static_cast<TypeInfoPointer const*>(base_of(left.type))->base_type == nullptr;
		if (raw_left && (TokenType::OPERATOR_PLUS == op || TokenType::OPERATOR_MINUS == op)
			&& (is_integer(default_type(right)))) {
			result = typed(left.type);
			return Progress::DONE;
		}
		if (TokenType::OPERATOR_AND == op || TokenType::OPERATOR_OR == op) {
			for (const Value* operand : { &left, &right }) {
				if (!is_boolean(default_type(*operand)) && ValueKind::UNTYPED_BOOLEAN != operand->kind) {
					result = error_at(checker, ErrorCode::E4015, node, std::format("&& and || take booleans, not {}",
						describe(*operand)));
					return Progress::DONE;
				}
			}
			result = typed(BUILTIN_bool);
			return Progress::DONE;
		}
		if (is_shift(op) && archetype_of(default_type(left)) != nullptr) {
			if (!promised(default_type(left), CAPABILITY_INTEGER)) {
				result = not_promised(checker, node, archetype_of(default_type(left)), "a shift", CAPABILITY_INTEGER);
				return Progress::DONE;
			}
			result = typed(left.type);
			return Progress::DONE;
		}
		if (is_shift(op)) {
			if (!is_integer(default_type(left)) || !(is_integer(default_type(right)) && !is_signed(right.type)
				&& (ValueKind::VALUE != right.kind || !is_signed(right.type)))) {
				result = error_at(checker, ErrorCode::E4020, node, "a shift takes an integer, shifted by an unsigned one");
				return Progress::DONE;
			}
			result = ValueKind::VALUE == left.kind ? typed(left.type) : left;
			fold_result(checker, node, op, left, right, result);
			return Progress::DONE;
		}
		/*
		 * A complex number or a quaternion with a real number in arithmetic, like z * 2.0: the real number as one, of
		 * the float its parts are, or a number that converts to it
		 */
		const bool arithmetic_op = TokenType::OPERATOR_PLUS == op || TokenType::OPERATOR_MINUS == op
			|| TokenType::OPERATOR_MULTIPLY == op || TokenType::OPERATOR_DIVIDE == op;
		for (const auto& [composite, real] : { std::pair<const Value*, const Value*>{ &left, &right }, { &right, &left } }) {
			if (arithmetic_op && ValueKind::VALUE == composite->kind && is_composite(composite->type) && ValueKind::VALUE == real->kind
				&& (is_float(real->type) || is_integer(real->type))) {
				TypeInfo* part = static_cast<TypeInfoComposite const*>(base_of(composite->type))->part_type;
				if (!can_implicitly_convert_to(real->type, part)) {
					result = error_at(checker, ErrorCode::E4015, node, std::format("{} and {} don't go together: the parts of {} are {}",
						describe(left), describe(right), to_string(composite->type), to_string(part)));
					return Progress::DONE;
				}
				result = typed(composite->type);
				return Progress::DONE;
			}
		}
		// A float with an untyped imaginary number, like im * 1i: the complex number or quaternion of that float
		for (const auto& [real, imaginary] : { std::pair<const Value*, const Value*>{ &left, &right }, { &right, &left } }) {
			if (arithmetic_op && ValueKind::VALUE == real->kind && is_float(real->type)
				&& (ValueKind::UNTYPED_COMPLEX == imaginary->kind || ValueKind::UNTYPED_QUATERNION == imaginary->kind)) {
				const size_t size = base_of(real->type)->size;
				const bool quaternion = ValueKind::UNTYPED_QUATERNION == imaginary->kind;
				result = typed(size == 2 ? (quaternion ? BUILTIN_q64 : BUILTIN_c32) : size == 4 ? (quaternion ? BUILTIN_q128 : BUILTIN_c64)
					: (quaternion ? BUILTIN_q256 : BUILTIN_c128));
				return Progress::DONE;
			}
		}
		Value shared;
		if (!common_type(left, right, shared)) {
			// A literal with an archetype that isn't promised to be a number
			TypeInfoArchetype const* archetype = ValueKind::VALUE == left.kind ? archetype_of(left.type) : nullptr;
			archetype = archetype == nullptr && ValueKind::VALUE == right.kind ? archetype_of(right.type) : archetype;
			if (archetype != nullptr && (is_untyped(left) || is_untyped(right))) {
				result = not_promised(checker, node, archetype, "a number", ValueKind::UNTYPED_FLOAT == left.kind
					|| ValueKind::UNTYPED_FLOAT == right.kind ? CAPABILITY_FLOAT : CAPABILITY_ARITHMETIC);
				return Progress::DONE;
			}
			if (report_operand_range(checker, left, right, node)) {
				result = poisoned();
				return Progress::DONE;
			}
			result = error_at(checker, ErrorCode::E4015, node, std::format("{} and {} don't go together",
				describe(left), describe(right)));
			return Progress::DONE;
		}
		TypeInfo* type = default_type(shared);
		// An archetype has the operators its constraints promise (docs/types.md, Checked Bodies)
		if (TypeInfoArchetype const* archetype = archetype_of(type); archetype != nullptr) {
			const bool ordered = TokenType::OPERATOR_EQUAL != op && TokenType::OPERATOR_NOT_EQUAL != op;
			const bool integral = TokenType::OPERATOR_MODULUS == op || TokenType::OPERATOR_REMAINDER == op || is_bitwise(op);
			const uint32_t needed = is_comparison(op) ? (ordered ? CAPABILITY_ORDERING : CAPABILITY_EQUALITY)
				: integral ? CAPABILITY_INTEGER : CAPABILITY_ARITHMETIC;
			if (!promised(type, needed)) {
				const std::string what = is_comparison(op) ? (ordered ? "ordering" : "==") : integral ? "an integer operator" : "arithmetic";
				result = not_promised(checker, node, archetype, what, needed);
				return Progress::DONE;
			}
			result = is_comparison(op) ? typed(BUILTIN_bool) : typed(shared.type);
			return Progress::DONE;
		}
		if (is_comparison(op)) {
			const bool ordered = TokenType::OPERATOR_EQUAL != op && TokenType::OPERATOR_NOT_EQUAL != op;
			if (ordered && (!(is_numeric(type) || is_enum(type) || is_variant(type, TypeInfoVariant::CHAR)) || is_composite(type))) {
				result = error_at(checker, ErrorCode::E4020, node, std::format("{} values can't be ordered", to_string(type)));
				return Progress::DONE;
			}
			result = typed(BUILTIN_bool);
			return Progress::DONE;
		}
		const bool arithmetic = TokenType::OPERATOR_PLUS == op || TokenType::OPERATOR_MINUS == op
			|| TokenType::OPERATOR_MULTIPLY == op || TokenType::OPERATOR_DIVIDE == op;
		const bool integral = TokenType::OPERATOR_MODULUS == op || TokenType::OPERATOR_REMAINDER == op;
		bool valid = false;
		if (arithmetic) {
			valid = is_numeric(type) || ((TokenType::OPERATOR_PLUS == op || TokenType::OPERATOR_MINUS == op) && is_enum(type))
				|| (TokenType::OPERATOR_PLUS == op && ValueKind::UNTYPED_STRING == shared.kind);
		}
		else if (integral) {
			valid = is_integer(type);
		}
		else if (is_bitwise(op)) {
			valid = is_integer(type) || is_enum(type);
		}
		if (!valid) {
			result = error_at(checker, ErrorCode::E4020, node, std::format("this operator doesn't apply to {}",
				describe(shared)));
			return Progress::DONE;
		}
		result = is_untyped(shared) ? shared : typed(shared.type);
		fold_result(checker, node, op, left, right, result);
		return Progress::DONE;
	}

	static Progress check_unary(Checker& checker, ast::Node* node, TypeInfo* expected, Value& result) {
		const TokenType op = node->value.type;
		if (node->children.empty()) {
			result = error_at(checker, ErrorCode::E4020, node, "an operator needs its operand");
			return Progress::DONE;
		}
		ast::Node* operand_node = node->children[0];
		Value operand;
		TypeInfo* operand_expected = TokenType::OPERATOR_MINUS == op || TokenType::OPERATOR_PLUS == op
			|| TokenType::OPERATOR_BITWISE_XOR == op ? expected : nullptr;
		Progress progress = check_expression(checker, operand_node, operand_expected, operand);
		if (progress != Progress::DONE) {
			return progress;
		}
		if (ValueKind::POISONED == operand.kind) {
			result = poisoned();
			return Progress::DONE;
		}
		// ?, is_some and the like read an optional's or result's variants, which its instance may not have yet
		progress = complete_subject(checker, operand_node, operand);
		if (progress != Progress::DONE) {
			return progress;
		}
		if (TokenType::SYM_QUESTION == op && ValueKind::TYPE != operand.kind) {
			require_public(checker, operand_node, "whether ? returns");
		}
		if (TokenType::SYM_QUESTION == op) {
			if (ValueKind::TYPE == operand.kind) {
				// T? as a type
				TypeInfo* optional = nullptr;
				progress = optional_of(checker.walk, node, operand.type, Need::DECLARED, optional);
				if (progress != Progress::DONE) {
					return progress;
				}
				result = type_value(optional);
				return Progress::DONE;
			}
			// x?: the value, or return what's missing from the function
			TypeInfo* held = ValueKind::VALUE == operand.kind ? held_value(operand.type) : nullptr;
			if (held == nullptr) {
				result = error_at(checker, ErrorCode::E4020, node, std::format("? needs an optional or a result, not {}",
					describe(operand)));
				return Progress::DONE;
			}
			const bool returns_one = checker.function != nullptr && checker.function->output.size() == 1;
			TypeInfo* returned = returns_one ? checker.function->output[0].type : nullptr;
			const bool same_kind = returned != nullptr
				&& ((builtin_union(operand.type, "Optional") != nullptr && builtin_union(returned, "Optional") != nullptr)
					|| (builtin_union(operand.type, "Result") != nullptr && builtin_union(returned, "Result") != nullptr));
			if (!same_kind) {
				error_at(checker, ErrorCode::E4020, node,
					"? returns what's missing, so the function must return an optional or a result like it");
			}
			result = typed(held);
			return Progress::DONE;
		}
		if (TokenType::KEYWORD_IS_SOME == op || TokenType::KEYWORD_IS_NONE == op) {
			if (ValueKind::VALUE != operand.kind || builtin_union(operand.type, "Optional") == nullptr) {
				result = error_at(checker, ErrorCode::E4020, node, std::format("is_some and is_none need an optional, not {}",
					describe(operand)));
				return Progress::DONE;
			}
			result = typed(BUILTIN_bool);
			return Progress::DONE;
		}
		if (TokenType::KEYWORD_OR_BREAK == op || TokenType::KEYWORD_OR_CONTINUE == op) {
			TypeInfo* held = ValueKind::VALUE == operand.kind ? held_value(operand.type) : nullptr;
			if (held == nullptr) {
				result = error_at(checker, ErrorCode::E4020, node, std::format("or_break and or_continue need an optional or a result, not {}",
					describe(operand)));
				return Progress::DONE;
			}
			if ((TokenType::KEYWORD_OR_BREAK == op ? checker.breakables : checker.loops) == 0) {
				error_at(checker, ErrorCode::E4022, node, "or_break and or_continue are only in a loop");
			}
			result = typed(held);
			return Progress::DONE;
		}
		if (TokenType::SYM_AMPERSAND == op) {
			if (!operand.is_location) {
				result = error_at(checker, ErrorCode::E4020, node, "& needs a location, like a variable or a field");
				return Progress::DONE;
			}
			if (operand.is_secret && !is_secret_type(operand.type)) {
				error_at(checker, ErrorCode::E4037, node, std::format(
					"a pointer to {} would lose that this is a secret; give it a #secret type", to_string(operand.type)));
			}
			// A relative pointer's place: a pointer to the relative pointer stored there
			TypeInfo* pointed = operand.stored_type != nullptr ? operand.stored_type : operand.type;
			result = typed(pointer_to(checker.walk, pointed, operand.is_mutable && !operand.is_context, false, POINTER_SIZE));
			return Progress::DONE;
		}
		if (TokenType::OPERATOR_DEREFERENCE == op) {
			result = operand;
			return dereference(checker, node, result);
		}
		TypeInfo* type = native_of(default_type(operand));
		// -v on integer or float lanes, ~v on integer or bool lanes, or the bits of v128 to v512
		if (TypeInfoVector const* vector = vector_type_of(operand); vector != nullptr) {
			const bool integer_lanes = is_integer(vector->element_type);
			const bool valid = TokenType::OPERATOR_BITWISE_XOR == op ? (integer_lanes || is_boolean(vector->element_type))
				: (TokenType::OPERATOR_MINUS == op || TokenType::OPERATOR_PLUS == op)
				&& !vector->is_bits && (integer_lanes || is_float(vector->element_type));
			result = valid ? typed(type) : error_at(checker, ErrorCode::E4020, node, std::format("this operator doesn't apply to {}",
				to_string(type)));
			return Progress::DONE;
		}
		if (TokenType::OPERATOR_NOT == op) {
			if (!is_boolean(type) && ValueKind::UNTYPED_BOOLEAN != operand.kind) {
				result = error_at(checker, ErrorCode::E4015, node, std::format("! takes a boolean, not {}", describe(operand)));
				return Progress::DONE;
			}
			result = ValueKind::UNTYPED_BOOLEAN == operand.kind ? operand : typed(type);
			return Progress::DONE;
		}
		if (TypeInfoArchetype const* archetype = archetype_of(type); archetype != nullptr
			&& (TokenType::OPERATOR_BITWISE_XOR == op || TokenType::OPERATOR_MINUS == op || TokenType::OPERATOR_PLUS == op)) {
			const uint32_t needed = TokenType::OPERATOR_BITWISE_XOR == op ? CAPABILITY_INTEGER : CAPABILITY_ARITHMETIC;
			result = promised(type, needed) ? typed(type)
				: not_promised(checker, node, archetype, TokenType::OPERATOR_BITWISE_XOR == op ? "~" : "a sign", needed);
			return Progress::DONE;
		}
		if (TokenType::OPERATOR_BITWISE_XOR == op && !is_integer(type)) {
			result = error_at(checker, ErrorCode::E4020, node, std::format("~ takes an integer, not {}", describe(operand)));
			return Progress::DONE;
		}
		if ((TokenType::OPERATOR_MINUS == op || TokenType::OPERATOR_PLUS == op) && !is_numeric(type)) {
			result = error_at(checker, ErrorCode::E4020, node, std::format("this operator takes a number, not {}",
				describe(operand)));
			return Progress::DONE;
		}
		result = is_untyped(operand) ? operand : typed(type);
		result.complement = false;
		if (ValueKind::UNTYPED_INTEGER == result.kind && TokenType::OPERATOR_BITWISE_XOR == op && result.integer_known
			&& !result.integer_negative) {
			result.complement = true;
			result.complemented = result.integer_magnitude;
		}
		if (ValueKind::UNTYPED_INTEGER == result.kind && TokenType::OPERATOR_MINUS == op) {
			result.integer_negative = !result.integer_negative && result.integer_magnitude != 0;
		}
		else if (ValueKind::UNTYPED_INTEGER == result.kind && TokenType::OPERATOR_BITWISE_XOR == op) {
			// ~x is -x - 1, whatever the type's size: ~5 is -6, and ~-6 is 5
			if (result.integer_negative) {
				result.integer_negative = false;
				result.integer_magnitude -= 1;
			}
			else if (result.integer_magnitude == UINT64_MAX) {
				result.integer_known = false;
			}
			else {
				result.integer_negative = true;
				result.integer_magnitude += 1;
			}
		}
		return Progress::DONE;
	}

	// Whether a cast from one type to another makes sense (docs/operators.md, Casting operators).
	static bool castable(TypeInfo const* from, TypeInfo const* to) {
		from = base_of(from);
		to = base_of(to);
		if (from == nullptr || to == nullptr) {
			return true;
		}
		auto scalar = [](TypeInfo const* type) {
			const TypeInfoVariant variant = type->variant;
			return TypeInfoVariant::INTEGER == variant || TypeInfoVariant::FLOAT == variant || promised(type, CAPABILITY_ARITHMETIC)
				|| TypeInfoVariant::ENUM == variant || TypeInfoVariant::BOOLEAN == variant
				|| TypeInfoVariant::CHAR == variant || TypeInfoVariant::POINTER == variant
				|| TypeInfoVariant::FUNCTION == variant;
		};
		// A view of the same elements, whether they can be changed or not, as a pointer can be cast to ptr[mut T]
		const bool views = TypeInfoVariant::ARRAY == from->variant && TypeInfoVariant::ARRAY == to->variant
			&& ArrayType::VIEW == static_cast<TypeInfoArray const*>(from)->array_type
			&& ArrayType::VIEW == static_cast<TypeInfoArray const*>(to)->array_type
			&& same_type(static_cast<TypeInfoArray const*>(from)->element_type, static_cast<TypeInfoArray const*>(to)->element_type);
		// Complex numbers to another size, quaternions too, and a real number to either, as its real part
		const bool composites = is_composite(to) && (from->variant == to->variant
			|| TypeInfoVariant::INTEGER == from->variant || TypeInfoVariant::FLOAT == from->variant);
		return from == to || assignable(const_cast<TypeInfo*>(from), const_cast<TypeInfo*>(to))
			|| (scalar(from) && scalar(to)) || views || composites;
	}

	// cast[T](x), bit_cast[T](x) and auto_cast(x), then anything after it, like ^ or .member.
	static Progress check_cast(Checker& checker, ast::Node* node, TypeInfo* expected, Value& result) {
		// (x).member and the like: x as it is, then the chain
		if (TokenType::SYM_LPAREN == node->value.type) {
			Value value;
			Progress progress = check_expression(checker, node->children[0], expected, value);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (checker.record != nullptr) {
				store_checked(checker.record->heads[node], ValueKind::VALUE == value.kind ? value : typed(default_type(value)));
			}
			result = value;
			return apply_postfix(checker, node, 1, result);
		}
		const bool automatic = TokenType::KEYWORD_AUTO_CAST == node->value.type;
		ast::Node* target_node = automatic ? nullptr : node->children[0];
		ast::Node* value_node = node->children[automatic ? 0 : 1];
		const size_t rest = automatic ? 1 : 2;
		TypeInfo* target = expected;
		if (!automatic) {
			Progress progress = check_type(checker, target_node, Need::RESOLVED, target);
			if (progress == Progress::FAILED) {
				result = poisoned();
				return Progress::DONE;
			}
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		Value value;
		Progress progress = check_expression(checker, value_node, nullptr, value);
		if (progress != Progress::DONE) {
			return progress;
		}
		if (target == nullptr) {
			result = error_at(checker, ErrorCode::E4015, node, "auto_cast needs to know the type it's converting to");
			return Progress::DONE;
		}
		// The type it converts to, as the cast's head
		if (checker.record != nullptr) {
			store_checked(checker.record->heads[node], typed(target));
		}
		if (ValueKind::POISONED == value.kind || report_relative(checker, node, target, "this cast")) {
			result = typed(target);
			return apply_postfix(checker, node, rest, result);
		}
		TypeInfo* source = default_type(value);
		/*
		 * A pointer to a secret made a pointer to what isn't one would read it as public (docs/memory.md,
		 * Secrets). rawptr is the way past this, on purpose, where it shows.
		 */
		if (is_pointer(source) && is_pointer(target) && reaches_secret(source) && !reaches_secret(target)
			&& static_cast<TypeInfoPointer const*>(base_of(target))->base_type != nullptr) {
			error_at(checker, ErrorCode::E4037, node, std::format("a cast from {} to {} would read a secret as public",
				to_string(source), to_string(target)));
		}
		if (TokenType::KEYWORD_BIT_CAST == node->value.type) {
			if (source != nullptr && source->complete && target->complete && source->size != target->size) {
				error_at(checker, ErrorCode::E4020, node, std::format("bit_cast needs types of the same size, not {} ({} bytes) and {} ({})",
					to_string(source), source->size, to_string(target), target->size));
			}
		}
		else if (!is_untyped(value) && !castable(source, target)) {
			TypeInfoArchetype const* archetype = archetype_of(source) != nullptr ? archetype_of(source) : archetype_of(target);
			if (archetype != nullptr) {
				not_promised(checker, node, archetype, "a cast", CAPABILITY_ARITHMETIC);
			}
			else {
				error_at(checker, ErrorCode::E4020, node, std::format("{} can't be cast to {}", to_string(source), to_string(target)));
			}
		}
		result = typed(target);
		return apply_postfix(checker, node, rest, result);
	}

	// The type a struct or array literal names, like Pair[int, string] in Pair[int, string].{1, "one"}.
	static Progress literal_type(Checker& checker, ast::Node* node, TypeInfo*& result) {
		// Its type's names, not its values', which are checked as values
		Progress progress = Progress::DONE;
		bool head_was_package = false;
		ast::Node* qualifier = node->children.size() >= 2 && ast::NodeType::DOT_ACCESS == node->children[0]->node_type
			? node->children[1] : nullptr;
		progress = require_qualified(checker.walk, node, node->value.value, qualifier, Need::RESOLVED, head_was_package);
		if (progress != Progress::DONE) {
			return progress;
		}
		ast::Node* binding = head_was_package ? qualifier : node;
		TypeInfo* named = nullptr;
		auto parameter = checker.walk.generic_types.find(text_of(node->value.value));
		auto bound = checker.walk.bindings.find(binding);
		if (parameter != checker.walk.generic_types.end()) {
			named = parameter->second;
		}
		else if (bound != checker.walk.bindings.end()) {
			Declaration* declaration = bound->second;
			if (DeclarationKind::GENERIC_TYPE == declaration->kind) {
				std::vector<ast::Node*> argument_nodes;
				for (ast::Node* child : node->children) {
					if (ast::NodeType::GENERIC_TAG == child->node_type) {
						argument_nodes.insert(argument_nodes.end(), child->children.begin(), child->children.end());
					}
				}
				std::vector<TypeInfo*> arguments;
				std::vector<ConstantValue> values;
				progress = generic_type_arguments(checker.walk, declaration, argument_nodes, [&](ast::Node* argument, TypeInfo*& type) {
					return check_type(checker, argument, Need::DECLARED, type);
				}, arguments, values);
				if (progress != Progress::DONE) {
					return progress;
				}
				return instance_type(checker.walk, node, declaration, arguments, Need::RESOLVED, result, values);
			}
			named = declaration->type_value;
		}
		else if (is_text(node->value.value, "vector") && !head_was_package) {
			// vector[u32, 4].{...}
			std::vector<ast::Node*> argument_nodes;
			for (ast::Node* child : node->children) {
				if (ast::NodeType::GENERIC_TAG == child->node_type) {
					argument_nodes.insert(argument_nodes.end(), child->children.begin(), child->children.end());
				}
			}
			return vector_type(checker.walk, node, argument_nodes, result);
		}
		else {
			named = builtin_type(text_of(binding->value.value));
		}
		if (named == nullptr) {
			report_error(ErrorCode::E4013, checker.walk.file_path, node->value.line_number, node->value.column_number,
				std::format("{} isn't a type", text_of(binding->value.value)));
			return Progress::FAILED;
		}
		result = named;
		return require_complete(checker.walk, node, named);
	}

	// Type.{values} or Type.{name = value}: a struct's fields, all in order, or some by name.
	static Progress check_struct_literal(Checker& checker, ast::Node* node, TypeInfo* expected, Value& result) {
		TypeInfo* type = nullptr;
		Progress progress = Progress::DONE;
		// .{...}: a struct of the type expected there
		if (TokenType::SYM_DOT == node->value.type) {
			if (expected == nullptr) {
				result = error_at(checker, ErrorCode::E4015, node, ".{...} needs a known struct type here");
				return Progress::DONE;
			}
			type = expected;
			/*
			 * As literal_type waits for a named type: the type expected, like a view's elements from a
			 * signature, which only needs its types declared, may still be being laid out on another thread
			 */
			TypeInfo const* known = base_of(type);
			if (known == nullptr || !known->complete) {
				progress = require_complete(checker.walk, node, known != nullptr ? const_cast<TypeInfo*>(known) : type);
			}
		}
		else {
			progress = literal_type(checker, node, type);
		}
		if (progress == Progress::FAILED) {
			result = poisoned();
			return Progress::DONE;
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		report_relative(checker, node, type, "this literal");
		TypeInfo const* base = base_of(type);
		ast::Node* list = nullptr;
		for (ast::Node* child : node->children) {
			if (ast::NodeType::LIST == child->node_type) {
				list = child;
			}
		}
		result = typed(type);
		// vector[u32, 4].{a, b, c, d}: each lane, in order, or .{} for zeros (docs/types.md, Vectors)
		if (base != nullptr && TypeInfoVariant::VECTOR == base->variant) {
			auto vector = static_cast<TypeInfoVector const*>(base);
			const size_t given = list != nullptr ? list->children.size() : 0;
			if (given != 0 && (vector->is_bits || given != vector->count)) {
				result = error_at(checker, ErrorCode::E4015, node, vector->is_bits
					? std::format("{} is written .{{}} for zeros, or bit_cast from a vector with lanes", to_string(type))
					: std::format("{} takes all {} lanes, not {}", to_string(type), vector->count, given));
				return Progress::DONE;
			}
			for (size_t i = 0; i < given; ++i) {
				Value lane;
				progress = check_expression(checker, list->children[i], vector->element_type, lane);
				if (progress != Progress::DONE) {
					return progress;
				}
				require_fit(checker, lane, vector->element_type, list->children[i], "a lane");
			}
			return Progress::DONE;
		}
		if (base == nullptr || TypeInfoVariant::STRUCT != base->variant) {
			result = error_at(checker, ErrorCode::E4015, node, std::format("{} isn't a struct, for a struct literal",
				to_string(type)));
			return Progress::DONE;
		}
		auto structure = static_cast<TypeInfoStruct const*>(base);
		if (list == nullptr) {
			return Progress::DONE;
		}
		size_t position = 0;
		bool any_named = false;
		for (ast::Node* element : list->children) {
			const bool named = ast::NodeType::BINARY_OPERATOR == element->node_type && is_assign(element)
				&& element->children.size() == 2;
			const StructMember* member = nullptr;
			ast::Node* value_node = element;
			if (named) {
				any_named = true;
				member = find_member(structure, element->children[0]->value.value);
				value_node = element->children[1];
				if (member == nullptr) {
					error_at(checker, ErrorCode::E4017, element->children[0], std::format("{} has no field {}",
						to_string(type), text_of(element->children[0]->value.value)));
				}
			}
			else {
				if (any_named) {
					error_at(checker, ErrorCode::E4018, element, "values in order come before named ones");
				}
				member = position < structure->members.size() ? &structure->members[position] : nullptr;
				++position;
				if (member == nullptr) {
					error_at(checker, ErrorCode::E4018, element, std::format("{} has only {} fields",
						to_string(type), structure->members.size()));
				}
			}
			Value value;
			progress = check_expression(checker, value_node, member != nullptr ? member->member_type : nullptr, value);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (member != nullptr) {
				require_fit(checker, value, member->member_type, value_node, text_of(member->name));
				// A field holds a secret by its type, like an assignment to it (docs/memory.md, Secrets)
				require_secret_fits(checker, value.is_secret, member->member_type, is_secret_type(type), value_node,
					std::format("{}", text_of(member->name)));
			}
		}
		if (position > 0 && position < structure->members.size() && !any_named) {
			error_at(checker, ErrorCode::E4018, node, std::format("{} has {} fields: give all of them in order, or some by name",
				to_string(type), structure->members.size()));
		}
		return Progress::DONE;
	}

	// Type.[values]: a static array of them.
	static Progress check_array_literal(Checker& checker, ast::Node* node, Value& result) {
		TypeInfo* element = nullptr;
		Progress progress = literal_type(checker, node, element);
		if (progress == Progress::FAILED) {
			result = poisoned();
			return Progress::DONE;
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		size_t count = 0;
		for (ast::Node* child : node->children) {
			if (ast::NodeType::LIST != child->node_type) {
				continue;
			}
			for (ast::Node* value_node : child->children) {
				Value value;
				progress = check_expression(checker, value_node, element, value);
				if (progress != Progress::DONE) {
					return progress;
				}
				require_fit(checker, value, element, value_node, "an element");
				++count;
			}
		}
		result = typed(array_of(checker.walk, element, ArrayType::STATIC, count));
		return Progress::DONE;
	}

	// .Name, or .Name(values): an enum member or a union variant of the type expected there.
	static Progress check_enum_shorthand(Checker& checker, ast::Node* node, TypeInfo* expected, Value& result) {
		InternedString name = node->value.value;
		// Where an optional of an enum or union goes, a member of what it holds, but its own Some and None
		if (builtin_union(expected, "Optional") != nullptr && !is_text(name, "Some") && !is_text(name, "None")) {
			TypeInfo* held = held_value(expected);
			TypeInfo const* inside = held != nullptr ? base_of(held) : nullptr;
			if (inside != nullptr && (TypeInfoVariant::ENUM == inside->variant || TypeInfoVariant::UNION == inside->variant)) {
				expected = held;
			}
		}
		TypeInfo const* type = base_of(expected);
		if (type == nullptr) {
			result = error_at(checker, ErrorCode::E4015, node, std::format(".{} needs a known enum or union type here", text_of(name)));
			return Progress::DONE;
		}
		std::vector<ast::Node*> arguments;
		bool called = false;
		for (ast::Node* child : node->children) {
			if (ast::NodeType::PAREN_GROUP == child->node_type) {
				called = true;
			}
			else if (called) {
				arguments.push_back(child);
			}
		}
		Value value = type_value(expected);
		Progress progress = check_member(checker, node, name, value);
		if (progress != Progress::DONE) {
			return progress;
		}
		if (ValueKind::VARIANT == value.kind) {
			progress = check_call(checker, node, arguments, value, {});
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		result = value;
		return Progress::DONE;
	}

	// Whether a VARIANT is one holding nothing, which is a value of its union as it's written.
	static bool takes_no_values(const Value& value) {
		TypeInfo const* union_type = base_of(value.type);
		if (union_type == nullptr || TypeInfoVariant::UNION != union_type->variant) {
			return false;
		}
		const std::vector<UnionVariant>& variants = static_cast<TypeInfoUnion const*>(union_type)->variants;
		return value.variant < variants.size() && variants[value.variant].types.empty();
	}

	// if as an expression: each branch's block ends with its value.
	static Progress check_if_expression(Checker& checker, ast::Node* node, TypeInfo* expected, Value& result) {
		Value condition;
		Progress progress = check_expression(checker, node->children[0], BUILTIN_bool, condition);
		if (progress != Progress::DONE) {
			return progress;
		}
		require_fit(checker, condition, BUILTIN_bool, node->children[0], "if's condition");
		require_public(checker, node->children[0], "if's condition");
		result = poisoned();
		TypeInfo* type = expected;
		for (size_t i = 1; i < node->children.size(); ++i) {
			ast::Node* branch = node->children[i];
			if (ast::NodeType::ELSE == branch->node_type && !branch->children.empty()) {
				branch = branch->children[0];
			}
			Value value;
			if (ast::NodeType::IF == branch->node_type) {
				progress = check_if_expression(checker, branch, type, value);
			}
			else {
				bool continues = true;
				checker.scopes.emplace_back();
				progress = check_block(checker, branch, continues, &value, type);
				checker.scopes.pop_back();
			}
			if (progress != Progress::DONE) {
				return progress;
			}
			// A variant without values, written as Union.Variant, is a value of its union
			if (ValueKind::VARIANT == value.kind && value.type != nullptr && takes_no_values(value)) {
				value = typed(value.type);
			}
			if (type == nullptr && ValueKind::POISONED != value.kind) {
				type = default_type(value);
				result = typed(type);
			}
			else if (ValueKind::POISONED != value.kind) {
				require_fit(checker, value, type, branch, "each branch of if");
				result = typed(type);
			}
		}
		return Progress::DONE;
	}

	static Progress check_match(Checker& checker, ast::Node* node, TypeInfo* expected, Value* result, bool& continues);

	// An integer literal's value, like 0xff or 1_000: false when it's too large for a u64.
	static bool literal_value(std::string_view text, uint64_t& value) {
		uint64_t radix = 10;
		if (text.size() > 2 && text[0] == '0' && (text[1] == 'x' || text[1] == 'o' || text[1] == 'b')) {
			radix = text[1] == 'x' ? 16 : text[1] == 'o' ? 8 : 2;
			text.remove_prefix(2);
		}
		value = 0;
		for (char c : text) {
			if (c == '_') {
				continue;
			}
			const uint64_t digit = c >= '0' && c <= '9' ? static_cast<uint64_t>(c - '0')
				: c >= 'a' && c <= 'f' ? static_cast<uint64_t>(c - 'a' + 10)
				: static_cast<uint64_t>(c - 'A' + 10);
			if (value > (UINT64_MAX - digit) / radix) {
				return false;
			}
			value = value * radix + digit;
		}
		return true;
	}

	static Progress check_literal(Checker& checker, ast::Node* node, Value& result) {
		const TokenType token = node->value.type;
		if (TokenType::LITERAL_INTEGER == token) {
			result.kind = ValueKind::UNTYPED_INTEGER;
			if (!literal_value(text_of(node->value.value), result.integer_magnitude)) {
				result = error_at(checker, ErrorCode::E4015, node, std::format("{} is too large for any integer, which go up to u64's {}",
					text_of(node->value.value), UINT64_MAX));
				return Progress::DONE;
			}
			result.integer_known = true;
		}
		else if (TokenType::LITERAL_FLOATING_POINT == token) {
			result.kind = ValueKind::UNTYPED_FLOAT;
		}
		else if (TokenType::LITERAL_IMAGINARY == token) {
			// 2i is complex; 2j and 2k only a quaternion has
			const std::string text = text_of(node->value.value);
			result.kind = !text.empty() && text.back() == 'i' ? ValueKind::UNTYPED_COMPLEX : ValueKind::UNTYPED_QUATERNION;
		}
		else if (TokenType::LITERAL_STRING == token) {
			result.kind = ValueKind::UNTYPED_STRING;
		}
		else if (TokenType::LITERAL_CHAR == token) {
			result = typed(BUILTIN_char);
		}
		else if (TokenType::KEYWORD_TRUE == token || TokenType::KEYWORD_FALSE == token) {
			result.kind = ValueKind::UNTYPED_BOOLEAN;
		}
		else if (TokenType::KEYWORD_NULL == token) {
			result.kind = ValueKind::NULL_VALUE;
		}
		else {
			result = error_at(checker, ErrorCode::E4024, node, "this literal isn't supported yet");
		}
		return Progress::DONE;
	}

	static Progress check_expression_inner(Checker& checker, ast::Node* node, TypeInfo* expected, Value& result);
	static Progress check_quote(Checker& checker, ast::Node* node, Value& result);
	static Progress insert_code(Checker& checker, ast::Node* insert, ast::Node*& inserted);
	static void become(Checker& checker, ast::Node* node, const ast::Node* inserted);
	static bool is_macro_call(const ast::Node* node);
	static Progress expand_macro(Checker& checker, ast::Node* node);

	// #insert, or the #expand a macro call becomes
	static bool is_insertion(const ast::Node* node) {
		return ast::NodeType::DIRECTIVE == node->node_type
			&& (is_text(node->value.value, "#insert") || is_text(node->value.value, "#expand"));
	}

	static bool is_assign(const ast::Node* node);

	/*
	 * Whether what an expression works out takes after a secret it's worked out from: an operator's
	 * operands, a cast's value, parentheses, and a literal's parts (docs/memory.md, Secrets).
	 */
	static bool inherits_secret(const Checker& checker, const ast::Node* node, const Value& result) {
		const ast::NodeType type = node->node_type;
		const TokenType op = node->value.type;
		if (ast::NodeType::BINARY_OPERATOR == type) {
			if (is_assign(node) || TokenType::OPERATOR_PIPE == op) {
				return false;
			}
			return std::any_of(node->children.begin(), node->children.end(), [&](const ast::Node* child) {
				return is_secret_node(checker, child);
			});
		}
		if (ast::NodeType::UNARY_OPERATOR == type) {
			return TokenType::SYM_AMPERSAND != op && TokenType::OPERATOR_DEREFERENCE != op && !node->children.empty()
				&& is_secret_node(checker, node->children[0]);
		}
		if (ast::NodeType::CAST == type || ast::NodeType::PAREN_GROUP == type) {
			return !node->children.empty() && is_secret_node(checker, node->children.back());
		}
		// A struct's fields say whether they hold secrets; a vector's lanes and an array's elements take after them
		if (ast::NodeType::STRUCT_LITERAL == type && !(ValueKind::VALUE == result.kind && is_variant(result.type, TypeInfoVariant::VECTOR))) {
			return false;
		}
		if (ast::NodeType::STRUCT_LITERAL == type || ast::NodeType::ARRAY_LITERAL == type) {
			for (const ast::Node* child : node->children) {
				if (ast::NodeType::LIST != child->node_type) {
					continue;
				}
				for (const ast::Node* part : child->children) {
					const ast::Node* given = ast::NodeType::BINARY_OPERATOR == part->node_type && is_assign(part)
						&& part->children.size() == 2 ? part->children[1] : part;
					if (is_secret_node(checker, given)) {
						return true;
					}
				}
			}
		}
		return false;
	}

	// What an operator can't do with a secret: divide, and decide whether the right side runs.
	static void check_secret_operator(Checker& checker, const ast::Node* node) {
		if (ast::NodeType::BINARY_OPERATOR != node->node_type || node->children.size() != 2) {
			return;
		}
		const TokenType op = node->value.type;
		const bool any = is_secret_node(checker, node->children[0]) || is_secret_node(checker, node->children[1]);
		if (any && (TokenType::OPERATOR_DIVIDE == op || TokenType::OPERATOR_MODULUS == op || TokenType::OPERATOR_REMAINDER == op
			|| TokenType::OPERATOR_ASSIGN_DIV == op || TokenType::OPERATOR_ASSIGN_MOD == op
			|| TokenType::OPERATOR_ASSIGN_REMAINDER == op)) {
			error_at(checker, ErrorCode::E4037, node, "a secret can't be divided or divide, since dividing takes longer for some values");
		}
		if (TokenType::OPERATOR_AND == op || TokenType::OPERATOR_OR == op || TokenType::KEYWORD_OR_ELSE == op
			|| TokenType::KEYWORD_OR_RETURN == op) {
			require_public(checker, node->children[0], "whether the right side runs");
		}
	}

	static Progress check_expression(Checker& checker, ast::Node* node, TypeInfo* expected, Value& result) {
		Progress progress = check_expression_inner(checker, node, expected, result);
		if (progress == Progress::DONE) {
			if (ValueKind::POISONED != result.kind) {
				if (ValueKind::VALUE == result.kind && is_secret_type(result.type)) {
					result.is_secret = true;
				}
				else if (!result.is_secret && inherits_secret(checker, node, result)) {
					result.is_secret = true;
				}
			}
			check_secret_operator(checker, node);
			if (result.is_secret) {
				checker.secret_nodes.insert(node);
				note_secret(checker, node);
			}
			record(checker, node, result);
		}
		return progress;
	}

	static Progress check_expression_inner(Checker& checker, ast::Node* node, TypeInfo* expected, Value& result) {
		result = poisoned();
		const ast::NodeType type = node->node_type;
		if (ast::NodeType::LITERAL == type) {
			return check_literal(checker, node, result);
		}
		if (ast::NodeType::IDENTIFIER == type) {
			if (is_macro_call(node)) {
				Progress progress = expand_macro(checker, node);
				if (progress != Progress::DONE) {
					return progress == Progress::FAILED ? Progress::DONE : progress;
				}
				return check_expression(checker, node, expected, result);
			}
			return check_postfix(checker, node, result);
		}
		if (ast::NodeType::TYPE == type) {
			TypeInfo* named = nullptr;
			Progress progress = check_type(checker, node, Need::DECLARED, named);
			if (progress == Progress::DONE) {
				result = type_value(named);
			}
			return progress == Progress::FAILED ? Progress::DONE : progress;
		}
		if (ast::NodeType::BINARY_OPERATOR == type
			&& (node->children.size() == 2 || TokenType::OPERATOR_PIPE == node->value.type)) {
			if (is_assign(node)) {
				result = error_at(checker, ErrorCode::E4020, node, "an assignment isn't a value here");
				return Progress::DONE;
			}
			return check_binary(checker, node, expected, result);
		}
		if (ast::NodeType::UNARY_OPERATOR == type) {
			return check_unary(checker, node, expected, result);
		}
		if (ast::NodeType::PAREN_GROUP == type && node->children.size() == 1) {
			return check_expression(checker, node->children[0], expected, result);
		}
		if (ast::NodeType::CAST == type) {
			return check_cast(checker, node, expected, result);
		}
		if (ast::NodeType::STRUCT_LITERAL == type) {
			return check_struct_literal(checker, node, expected, result);
		}
		if (ast::NodeType::ARRAY_LITERAL == type) {
			return check_array_literal(checker, node, result);
		}
		if (ast::NodeType::ENUM_SHORTHAND == type) {
			return check_enum_shorthand(checker, node, expected, result);
		}
		if (ast::NodeType::IF == type) {
			return check_if_expression(checker, node, expected, result);
		}
		if (ast::NodeType::MATCH == type) {
			bool continues = true;
			return check_match(checker, node, expected, &result, continues);
		}
		if (ast::NodeType::VOID == type) {
			result = nothing();
			return Progress::DONE;
		}
		if (ast::NodeType::FUNCTION == type) {
			TypeInfo* function = nullptr;
			Progress progress = check_type(checker, node, Need::DECLARED, function);
			if (progress == Progress::DONE) {
				result = type_value(function);
			}
			return progress == Progress::FAILED ? Progress::DONE : progress;
		}
		if (ast::NodeType::DIRECTIVE == type) {
			if (is_text(node->value.value, "#code")) {
				return check_quote(checker, node, result);
			}
			if (is_insertion(node)) {
				ast::Node* inserted = nullptr;
				Progress progress = insert_code(checker, node, inserted);
				if (progress != Progress::DONE) {
					result = poisoned();
					return progress == Progress::FAILED ? Progress::DONE : progress;
				}
				if (ast::NodeType::BLOCK == inserted->node_type || is_code_list(inserted)) {
					result = error_at(checker, ErrorCode::E4014, node, std::format("{} puts {} here, where an expression goes: "
						"quote an expression, with #code(...)", is_text(node->value.value, "#expand") ? "the macro" : "#insert",
						is_code_list(inserted) ? "a list" : "statements"));
					return Progress::DONE;
				}
				become(checker, node, inserted);
				return check_expression(checker, node, expected, result);
			}
			if (is_text(node->value.value, "#caller_location")) {
				TypeInfo* location = nullptr;
				Progress progress = base_type(checker, node, "runtime", "SourceCodeLocation", location);
				if (progress == Progress::DONE) {
					result = typed(location);
				}
				return progress;
			}
			// LIBRARY :: #library("name"), for #foreign functions (docs/directives.md, #foreign)
			if (is_text(node->value.value, "#library")) {
				ast::Node* name = nullptr;
				for (ast::Node* child : node->children) {
					if (ast::NodeType::PAREN_GROUP != child->node_type) {
						name = child;
					}
				}
				if (name == nullptr || ast::NodeType::LITERAL != name->node_type || TokenType::LITERAL_STRING != name->value.type) {
					result = error_at(checker, ErrorCode::E4014, node, "#library needs a string, the library's name");
					return Progress::DONE;
				}
				TypeInfo* library = nullptr;
				Progress progress = base_type(checker, node, "runtime", "ForeignLibrary", library);
				if (progress == Progress::DONE) {
					result = typed(library);
				}
				return progress;
			}
			if (is_text(node->value.value, "#is_compile_time")) {
				result = typed(BUILTIN_bool);
				return Progress::DONE;
			}
			if (is_text(node->value.value, "#file_path")) {
				// The path of the file it's in, as a string
				result = typed(BUILTIN_string);
				return Progress::DONE;
			}
			if (is_text(node->value.value, "#file_data")) {
				// The file's bytes, as many as it has when it's compiled
				const std::filesystem::path path = file_data_path(checker.walk.file_path, node);
				if (path.empty()) {
					result = error_at(checker, ErrorCode::E4014, node, "#file_data needs a string, the file's path");
					return Progress::DONE;
				}
				std::error_code error;
				const uintmax_t size = std::filesystem::file_size(path, error);
				if (error) {
					result = error_at(checker, ErrorCode::E4028, node, std::format("{}: {}", path.string(), error.message()));
					return Progress::DONE;
				}
				result = typed(array_of(checker.walk, BUILTIN_u8, ArrayType::STATIC, static_cast<size_t>(size)));
				return Progress::DONE;
			}
			if (is_text(node->value.value, "#run") && !node->children.empty()) {
				// The type of what it runs; it's run when its code is generated, once, as a constant
				return check_expression(checker, node->children[0], expected, result);
			}
		}
		if (ast::NodeType::UNINITIALIZED == type) {
			result.kind = ValueKind::POISONED;
			return Progress::DONE;
		}
		result = error_at(checker, ErrorCode::E4024, node, std::format("{} isn't supported in an expression yet",
			ast::name_of(type)));
		return Progress::DONE;
	}

	/*
	 * #code (docs/compilation.md, Code Values): its children are what its #inserts splice, checked where
	 * the quote is, each something code can hold: code, a type, or a literal's value. The quote itself
	 * isn't checked until it's inserted. It's a compiler.Code, made by compiler.quote_code.
	 */
	static Progress check_quote(Checker& checker, ast::Node* node, Value& result) {
		TypeInfo* code = nullptr;
		Progress progress = base_type(checker, node, "compiler", "Code", code);
		if (progress != Progress::DONE) {
			return progress;
		}
		for (ast::Node* splice : node->children) {
			Value value;
			progress = check_expression(checker, splice, nullptr, value);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (ValueKind::POISONED == value.kind) {
				continue;
			}
			TypeInfo* spliced = usual_type(value);
			TypeInfo const* base_spliced = spliced != nullptr ? get_base_type(spliced) : nullptr;
			const TypeInfoVariant variant = base_spliced != nullptr ? base_spliced->variant : TypeInfoVariant::VOID;
			const bool fits = base_spliced == get_base_type(code)
				|| TypeInfoVariant::TYPE == variant || TypeInfoVariant::INTEGER == variant || TypeInfoVariant::FLOAT == variant
				|| TypeInfoVariant::BOOLEAN == variant || TypeInfoVariant::CHAR == variant || TypeInfoVariant::ENUM == variant
				|| TypeInfoVariant::STRING == variant;
			if (!fits) {
				error_at(checker, ErrorCode::E4014, splice, std::format("{} can't be put into code: #insert takes a compiler.Code, a type, "
					"or a number, boolean, character, string or enum member, which becomes a literal", describe(value)));
			}
		}
		Declaration* quote_code = nullptr;
		progress = base_declaration(checker.walk, node, "compiler", "quote_code", quote_code);
		if (progress == Progress::DONE) {
			progress = require_resolved(checker.walk, node, quote_code, Need::RESOLVED);
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		result = typed(code);
		result.called = static_cast<TypeInfoFunction const*>(get_base_type(quote_code->value_type));
		result.called_declaration = quote_code;
		return Progress::DONE;
	}

	// Whether the body being checked is a generic's, or an instance of one, which share one tree.
	static bool in_generic(Checker& checker) {
		Declaration* owner = checker.walk.owner;
		if (!checker.walk.generic_types.empty() || !checker.walk.generic_values.empty()) {
			return true;
		}
		if (owner == nullptr) {
			return false;
		}
		if (owner->generic != nullptr) {
			return true;
		}
		FunctionParts parts;
		if (owner->node != nullptr && function_parts(owner->node, parts) && parts.signature != nullptr) {
			for (const ast::Node* child : parts.signature->children) {
				if (ast::NodeType::GENERIC_TAG == child->node_type) {
					return true;
				}
			}
		}
		return false;
	}

	/*
	 * #insert outside a quote (docs/compilation.md, Code Values): its code, run once at compile time, copied
	 * for this place, with where it was written and where it's put. FAILED once reported. Printed when the
	 * command line asks to see what's inserted here (--show-inserted).
	 */
	static Progress insert_code(Checker& checker, ast::Node* insert, ast::Node*& inserted) {
		inserted = nullptr;
		// A generic's instances share its tree, which an insertion would change for all of them
		if (in_generic(checker)) {
			error_at(checker, ErrorCode::E4024, insert, "#insert in a generic's body isn't supported yet");
			return Progress::FAILED;
		}
		const ast::Node* tree = nullptr;
		Progress progress = code_to_insert(checker.walk, insert, tree);
		if (progress != Progress::DONE) {
			return progress;
		}
		ProgramInfo* program = checker.walk.executor.program_info;
		const std::shared_ptr<const ast::Origin> origin = program->made_nodes.origin(insert);
		ast::InsertionSite site{ origin != nullptr ? origin->file : checker.walk.file_path, insert->value.line_number,
			insert->value.column_number };
		inserted = const_cast<ast::Node*>(copy_to_insert(program->made_nodes, program->quotes, tree, site, origin.get(),
			is_text(insert->value.value, "#expand")));
		if (inserted == nullptr) {
			return Progress::FAILED;
		}
		show_inserted(checker.walk.executor.global_data->options, site, inserted, program->quotes);
		return Progress::DONE;
	}

	// The node becomes what was inserted at it, in place, so whatever holds it holds that.
	static void become(Checker& checker, ast::Node* node, const ast::Node* inserted) {
		node->node_type = inserted->node_type;
		node->value = inserted->value;
		node->type = inserted->type;
		node->children = inserted->children;
		ast::NodeStore& made = checker.walk.executor.program_info->made_nodes;
		made.set_origin(node, made.origin(inserted));
	}

	// How many insertions deep code can be put, so a macro that expands to itself stops
	static constexpr size_t MAX_INSERTION_DEPTH = 64;

	// Where a macro call's ! is, name!(arguments) or package.name!(arguments), or the end if it isn't one.
	static size_t macro_bang(const ast::Node* node) {
		for (size_t i = 0; i + 1 < node->children.size(); ++i) {
			const ast::Node* child = node->children[i];
			if (ast::NodeType::UNARY_OPERATOR == child->node_type && TokenType::OPERATOR_NOT == child->value.type
				&& child->children.empty() && ast::NodeType::PAREN_GROUP == node->children[i + 1]->node_type) {
				return i;
			}
		}
		return node->children.size();
	}

	static bool is_macro_call(const ast::Node* node) {
		return ast::NodeType::IDENTIFIER == node->node_type && macro_bang(node) < node->children.size();
	}

	// The #inserts in a macro's argument, which splice into it as in a quote, not counting those in a #code within it.
	static void argument_splices(ast::Node* node, std::vector<ast::Node*>& found) {
		for (ast::Node* child : node->children) {
			if (ast::NodeType::DIRECTIVE == child->node_type) {
				if (is_text(child->value.value, "#insert")) {
					found.push_back(child);
					continue;
				}
				if (is_text(child->value.value, "#code")) {
					continue;
				}
			}
			argument_splices(child, found);
		}
	}

	/*
	 * A macro call, name!(arguments) (docs/compilation.md, Macros), becomes #expand of a call to the #macro
	 * function, run at compile time like #insert's, each argument for a compiler.Code parameter quoted as
	 * the caller's code. What it gives is put in place hygienically. FAILED once reported.
	 */
	static Progress expand_macro(Checker& checker, ast::Node* node) {
		ProgramInfo* program = checker.walk.executor.program_info;
		ast::NodeStore& made = program->made_nodes;
		const size_t bang = macro_bang(node);
		const std::shared_ptr<const ast::Origin> origin = made.origin(node);
		if (origin != nullptr && origin->inserted.size() >= MAX_INSERTION_DEPTH) {
			error_at(checker, ErrorCode::E4039, node, std::format("macros expand {} deep here; one may be expanding to itself",
				MAX_INSERTION_DEPTH));
			return Progress::FAILED;
		}
		ast::Node* qualifier = bang == 2 && ast::NodeType::DOT_ACCESS == node->children[0]->node_type
			&& ast::NodeType::IDENTIFIER == node->children[1]->node_type ? node->children[1] : nullptr;
		if (bang != 0 && qualifier == nullptr) {
			error_at(checker, ErrorCode::E4039, node, "a macro is called by its name, or package.name: name!(...)");
			return Progress::FAILED;
		}
		size_t end = bang + 2;
		while (end < node->children.size() && !is_postfix_marker(node->children[end])) {
			++end;
		}
		if (end != node->children.size()) {
			error_at(checker, ErrorCode::E4039, node->children[end], "nothing can follow a macro call");
			return Progress::FAILED;
		}
		bool head_was_package = false;
		Progress progress = require_qualified(checker.walk, node, node->value.value, qualifier, Need::RESOLVED, head_was_package);
		if (progress != Progress::DONE) {
			return progress;
		}
		const ast::Node* named = head_was_package ? qualifier : node;
		auto bound = checker.walk.bindings.find(named);
		Declaration* macro = bound != checker.walk.bindings.end() ? bound->second : nullptr;
		if (macro == nullptr || !is_macro_function(macro)) {
			error_at(checker, ErrorCode::E4039, node, std::format("{} isn't a #macro; call it without !", text_of(named->value.value)));
			return Progress::FAILED;
		}
		auto function = static_cast<TypeInfoFunction const*>(macro->value_type != nullptr ? get_base_type(macro->value_type) : nullptr);
		if (function == nullptr || TypeInfoVariant::FUNCTION != function->variant) {
			error_at(checker, ErrorCode::E4024, node, "a generic macro isn't supported yet");
			return Progress::FAILED;
		}
		TypeInfo* code = nullptr;
		progress = base_type(checker, node, "compiler", "Code", code);
		if (progress != Progress::DONE) {
			return progress;
		}
		// The call, without the !, its compiler.Code arguments quoted
		const std::string file = origin != nullptr ? origin->file : checker.walk.file_path;
		std::vector<ast::Node*> children(node->children.begin(), node->children.end());
		children.erase(children.begin() + static_cast<std::ptrdiff_t>(bang));
		size_t position = 0;
		ast::Node* call = nullptr;
		{
			const std::unique_lock<std::mutex> lock = made.hold();
			for (size_t i = bang + 1; i < children.size(); ++i) {
				ast::Node** argument = &children[i];
				TypeInfo* parameter = nullptr;
				if (ast::NodeType::BINARY_OPERATOR == (*argument)->node_type && is_assign(*argument) && (*argument)->children.size() == 2
					&& ast::NodeType::IDENTIFIER == (*argument)->children[0]->node_type) {
					const InternedString name = (*argument)->children[0]->value.value;
					for (const FunctionInput& input : function->input) {
						if (input.name != nullptr && *input.name == *name) {
							parameter = input.type;
						}
					}
					argument = &(*argument)->children[1];
				}
				else if (position < function->input.size()) {
					parameter = function->input[position++].type;
				}
				if (parameter == nullptr || get_base_type(parameter) != get_base_type(code)) {
					continue;
				}
				Token word = (*argument)->value;
				word.type = TokenType::DIRECTIVE;
				word.value = intern(std::string("#code"));
				ast::Node* quote = made.make(ast::NodeType::DIRECTIVE, word);
				std::vector<ast::Node*> splices;
				if (is_insertion(*argument)) {
					splices.push_back(*argument);
				}
				else {
					argument_splices(*argument, splices);
				}
				for (ast::Node* splice : splices) {
					if (!splice->children.empty()) {
						quote->children.push_back(splice->children.front());
						splice->children.erase(splice->children.begin());
					}
				}
				program->quotes.set(quote, *argument, file, true);
				*argument = quote;
			}
			call = made.make(ast::NodeType::IDENTIFIER, node->value);
			call->children.assign(children.begin(), children.end());
		}
		if (origin != nullptr) {
			made.set_origin(call, origin);
		}
		node->node_type = ast::NodeType::DIRECTIVE;
		node->value.type = TokenType::DIRECTIVE;
		node->value.value = intern(std::string("#expand"));
		node->children.clear();
		node->children.push_back(call);
		return Progress::DONE;
	}

	// ---------------------------------------------------------------------------------------------
	// Statements

	// Whether a value can be assigned to, reporting why not.
	static bool require_assignable(Checker& checker, const Value& target, const ast::Node* where) {
		if (ValueKind::POISONED == target.kind) {
			return false;
		}
		if (target.is_context) {
			error_at(checker, ErrorCode::E4016, where, "the context can't be changed; push a new one with push_context");
			return false;
		}
		if (!target.is_location) {
			error_at(checker, ErrorCode::E4016, where, std::format("{} isn't a location to assign to", describe(target)));
			return false;
		}
		// A type parameter, in a body checked before any instance, changes only if it's promised mut
		if (!target.is_mutable && archetype_of(target.type) != nullptr) {
			TypeInfoArchetype const* archetype = archetype_of(target.type);
			not_promised(checker, where, archetype, "writing through a pointer", std::format("constrain {} with compiler.Mutable",
				to_string(archetype)));
			return false;
		}
		if (!target.is_mutable) {
			error_at(checker, ErrorCode::E4016, where,
				"this can't be changed: it's a constant, or reached through a ptr without mut");
			return false;
		}
		return true;
	}

	static TokenType operator_of_assignment(TokenType op) {
		const std::pair<TokenType, TokenType> pairs[] = {
			{ TokenType::OPERATOR_ASSIGN_ADD, TokenType::OPERATOR_PLUS },
			{ TokenType::OPERATOR_ASSIGN_SUB, TokenType::OPERATOR_MINUS },
			{ TokenType::OPERATOR_ASSIGN_MUL, TokenType::OPERATOR_MULTIPLY },
			{ TokenType::OPERATOR_ASSIGN_DIV, TokenType::OPERATOR_DIVIDE },
			{ TokenType::OPERATOR_ASSIGN_MOD, TokenType::OPERATOR_MODULUS },
			{ TokenType::OPERATOR_ASSIGN_REMAINDER, TokenType::OPERATOR_REMAINDER },
			{ TokenType::OPERATOR_ASSIGN_BITWISE_AND, TokenType::SYM_AMPERSAND },
			{ TokenType::OPERATOR_ASSIGN_BITWISE_OR, TokenType::OPERATOR_BITWISE_OR },
			{ TokenType::OPERATOR_ASSIGN_BITWISE_XOR, TokenType::OPERATOR_BITWISE_XOR },
			{ TokenType::OPERATOR_ASSIGN_LEFT_SHIFT, TokenType::OPERATOR_LEFT_SHIFT },
			{ TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC, TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC },
			{ TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL, TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL },
			{ TokenType::OPERATOR_ASSIGN_AND, TokenType::OPERATOR_AND },
			{ TokenType::OPERATOR_ASSIGN_OR, TokenType::OPERATOR_OR },
		};
		for (const auto& [assignment, operation] : pairs) {
			if (assignment == op) {
				return operation;
			}
		}
		return TokenType::INVALID;
	}

	static bool is_assignment(const ast::Node* node) {
		return ast::NodeType::BINARY_OPERATOR == node->node_type && node->children.size() == 2
			&& (is_assign(node) || TokenType::INVALID != operator_of_assignment(node->value.type));
	}

	// The values on the right of an assignment or definition: several, or one call's several results.
	static Progress check_values(Checker& checker, ast::Node* node, const std::vector<TypeInfo*>& expected,
		std::vector<Value>& values) {

		std::vector<ast::Node*> nodes;
		if (ast::NodeType::LIST == node->node_type) {
			nodes.assign(node->children.begin(), node->children.end());
		}
		else {
			nodes.push_back(node);
		}
		for (size_t i = 0; i < nodes.size(); ++i) {
			Value value;
			TypeInfo* hint = nodes.size() == 1 && expected.size() == 1 ? expected[0]
				: i < expected.size() && nodes.size() == expected.size() ? expected[i] : nullptr;
			Progress progress = check_expression(checker, nodes[i], hint, value);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (ValueKind::RESULTS == value.kind) {
				for (TypeInfo* result : value.results) {
					values.push_back(typed(result));
				}
			}
			else {
				values.push_back(value);
			}
		}
		return Progress::DONE;
	}

	// a = b, a, b = b, a, and a += b (docs/operators.md, Assignment operators).
	static Progress check_assignment(Checker& checker, ast::Node* node) {
		ast::Node* left_node = node->children[0];
		ast::Node* right_node = node->children[1];
		std::vector<ast::Node*> targets;
		if (ast::NodeType::LIST == left_node->node_type) {
			targets.assign(left_node->children.begin(), left_node->children.end());
		}
		else {
			targets.push_back(left_node);
		}
		std::vector<Value> target_values;
		std::vector<TypeInfo*> types;
		for (ast::Node* target : targets) {
			Value value;
			if (ast::NodeType::UNDERSCORE == target->node_type) {
				target_values.push_back(poisoned());
				types.push_back(nullptr);
				continue;
			}
			Progress progress = check_expression(checker, target, nullptr, value);
			if (progress != Progress::DONE) {
				return progress;
			}
			require_assignable(checker, value, target);
			target_values.push_back(value);
			types.push_back(ValueKind::VALUE == value.kind ? value.type : nullptr);
		}
		if (ast::NodeType::MATCH == right_node->node_type) {
			// docs/control_flow.md, Match: assign inside the arms instead
			error_at(checker, ErrorCode::E4020, right_node, "match can't be the right side of an assignment; assign inside its arms");
		}
		std::vector<Value> values;
		if (is_assignment(right_node)) {
			// Chained, right to left: the right one's targets are the values
			Progress progress = check_assignment(checker, right_node);
			if (progress != Progress::DONE) {
				return progress;
			}
			progress = check_values(checker, right_node->children[0], types, values);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		else {
			Progress progress = check_values(checker, right_node, types, values);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		if (values.size() != 1 && values.size() != targets.size()) {
			error_at(checker, ErrorCode::E4018, node, std::format("{} values for {} targets; give one, or one each",
				values.size(), targets.size()));
			return Progress::DONE;
		}
		const TokenType op = operator_of_assignment(node->value.type);
		for (size_t i = 0; i < targets.size(); ++i) {
			const Value& value = values.size() == 1 ? values[0] : values[i];
			if (ValueKind::POISONED == target_values[i].kind) {
				continue;
			}
			require_secret_fits(checker, value.is_secret, types[i], target_values[i].is_secret, targets[i],
				"what's assigned to");
			if (TokenType::INVALID == op) {
				// A relative pointer's place takes the pointer it's set to; anything else with one in it isn't copied
				if (target_values[i].stored_type == nullptr && report_relative(checker, targets[i], types[i], "this assignment")) {
					continue;
				}
				require_fit(checker, value, types[i], targets[i], "this assignment");
				continue;
			}
			// An endian-specific integer is computed as its native type, and stored with a cast that shows the swap
			if (types[i] != nullptr && native_of(types[i]) != types[i]) {
				error_at(checker, ErrorCode::E4020, targets[i], std::format(
					"{} has no arithmetic of its own: compute in {}, and store with a cast (docs/types.md, Endian-Specific Types)",
					to_string(types[i]), to_string(native_of(types[i]))));
				continue;
			}
			Value shared;
			if (!common_type(target_values[i], value, shared) && ValueKind::POISONED != value.kind
				&& !report_operand_range(checker, target_values[i], value, targets[i])) {
				error_at(checker, ErrorCode::E4015, targets[i], std::format("{} and {} don't go together",
					describe(target_values[i]), describe(value)));
			}
		}
		return Progress::DONE;
	}

	// A definition's parts: its names, the type written, whether it's a constant (:) or a variable
	// (= or none), and its value.
	struct LocalDefinition {
		std::vector<ast::Node*> names;
		ast::Node* type = nullptr;
		bool is_constant = false;
		ast::Node* value = nullptr;
	};

	static LocalDefinition parts_of(ast::Node* definition) {
		LocalDefinition result;
		ast::Node* names = definition->children[0];
		if (ast::NodeType::LIST == names->node_type) {
			result.names.assign(names->children.begin(), names->children.end());
		}
		else {
			result.names.push_back(names);
		}
		for (size_t i = 1; i < definition->children.size(); ++i) {
			ast::Node* child = definition->children[i];
			if (ast::NodeType::COLON == child->node_type) {
				result.is_constant = true;
				result.value = i + 1 < definition->children.size() ? definition->children[i + 1] : nullptr;
				break;
			}
			if (ast::NodeType::IDENTIFIER == child->node_type && is_assign(child)) {
				result.value = i + 1 < definition->children.size() ? definition->children[i + 1] : nullptr;
				break;
			}
			if (result.type == nullptr) {
				result.type = child;
			}
		}
		return result;
	}

	static Progress check_nested_function(Checker& checker, ast::Node* definition, ast::Node* function, Value& result);

	// x : T = value, x := value, x :: value, x : T : value, x : T (docs/functions.md, types.md).
	static Progress check_definition(Checker& checker, ast::Node* definition) {
		const LocalDefinition parts = parts_of(definition);
		TypeInfo* type = nullptr;
		if (parts.type != nullptr) {
			Progress progress = check_held_type(checker, parts.type, Need::RESOLVED, type);
			if (progress == Progress::FAILED) {
				type = nullptr;
			}
			else if (progress != Progress::DONE) {
				return progress;
			}
		}
		std::vector<Value> values;
		if (parts.value != nullptr && ast::NodeType::FUNCTION == parts.value->node_type) {
			Value function;
			Progress progress = check_nested_function(checker, definition, parts.value, function);
			if (progress != Progress::DONE) {
				return progress;
			}
			values.push_back(function);
		}
		else if (parts.value != nullptr && (ast::NodeType::STRUCT == parts.value->node_type
			|| ast::NodeType::UNION == parts.value->node_type || ast::NodeType::ENUM == parts.value->node_type)) {
			error_at(checker, ErrorCode::E4024, parts.value, "types declared inside a function aren't supported yet");
			values.push_back(poisoned());
		}
		else if (parts.value != nullptr && ast::NodeType::UNINITIALIZED == parts.value->node_type) {
			values.push_back(typed(type));
		}
		else if (parts.value != nullptr) {
			std::vector<TypeInfo*> expected(parts.names.size(), type);
			Progress progress = check_values(checker, parts.value, expected, values);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		if (!values.empty() && values.size() != 1 && values.size() != parts.names.size()) {
			error_at(checker, ErrorCode::E4018, definition, std::format("{} values for {} names; give one, or one each",
				values.size(), parts.names.size()));
		}
		for (size_t i = 0; i < parts.names.size(); ++i) {
			Value value = values.empty() ? typed(type) : values.size() == 1 ? values[0]
				: i < values.size() ? values[i] : poisoned();
			// A local made from a secret holds one (docs/memory.md, Secrets)
			const bool secret = value.is_secret;
			if (type != nullptr) {
				if (!values.empty()) {
					require_fit(checker, value, type, parts.value, text_of(parts.names[i]->value.value));
				}
				value = typed(type);
			}
			else if (ValueKind::NOTHING == value.kind || ValueKind::PACKAGE == value.kind
				|| ValueKind::BUILTIN_FUNCTION == value.kind || ValueKind::VARIANT == value.kind) {
				error_at(checker, ErrorCode::E4015, definition, std::format("{} has no value to define {} with",
					describe(value), text_of(parts.names[i]->value.value)));
				value = poisoned();
			}
			else if (!parts.is_constant && is_untyped(value)) {
				// A variable takes the untyped value's usual type
				require_default_range(checker, value, definition);
				value = typed(default_type(value));
			}
			if (!parts.is_constant && ValueKind::TYPE == value.kind) {
				value = typed(BUILTIN_type);
			}
			value.never_returns = false;
			value.is_location = ValueKind::VALUE == value.kind;
			value.is_mutable = !parts.is_constant && ValueKind::VALUE == value.kind;
			value.is_context = false;
			value.is_secret = ValueKind::POISONED != value.kind && (secret || (ValueKind::VALUE == value.kind && is_secret_type(value.type)));
			// A nested function is its declaration, called as one, not a local's storage
			const bool nested_function = parts.value != nullptr && ast::NodeType::FUNCTION == parts.value->node_type
				&& value.declaration != nullptr;
			if (nested_function) {
				value.is_location = false;
				value.is_mutable = false;
			}
			if (ValueKind::VALUE == value.kind && !parts.is_constant) {
				report_relative(checker, parts.names[i], value.type, std::format("variable {}", text_of(parts.names[i]->value.value)));
			}
			declare_local(checker, parts.names[i], parts.names[i]->value.value, value);
			if (nested_function && !checker.scopes.back().locals.empty()) {
				checker.scopes.back().locals.back().value.local = nullptr;
			}
		}
		return Progress::DONE;
	}

	static Progress check_return(Checker& checker, ast::Node* node) {
		if (checker.function == nullptr) {
			error_at(checker, ErrorCode::E4020, node, "return is only in a function");
			return Progress::DONE;
		}
		const std::vector<FunctionOutput>& outputs = checker.function->output;
		if (node->children.size() == 1 && ast::NodeType::VOID == node->children[0]->node_type) {
			if (!outputs.empty()) {
				error_at(checker, ErrorCode::E4004, node, std::format("this function returns {} values, not void",
					outputs.size()));
			}
			return Progress::DONE;
		}
		if (node->children.empty() && outputs.empty()) {
			return Progress::DONE;
		}
		std::vector<TypeInfo*> expected;
		for (const FunctionOutput& output : outputs) {
			expected.push_back(output.type);
		}
		std::vector<Value> values;
		for (size_t i = 0; i < node->children.size(); ++i) {
			Value value;
			TypeInfo* hint = node->children.size() == expected.size() ? expected[i]
				: node->children.size() == 1 && expected.size() == 1 ? expected[0] : nullptr;
			Progress progress = check_expression(checker, node->children[i], hint, value);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (ValueKind::RESULTS == value.kind) {
				for (TypeInfo* result : value.results) {
					values.push_back(typed(result));
				}
			}
			else if (ValueKind::NOTHING != value.kind) {
				values.push_back(value);
			}
		}
		if (outputs.empty()) {
			error_at(checker, ErrorCode::E4004, node, "this function returns nothing; use return void");
			return Progress::DONE;
		}
		for (const Value& value : values) {
			if (ValueKind::POISONED == value.kind) {
				return Progress::DONE;
			}
		}
		if (values.size() != outputs.size()) {
			error_at(checker, ErrorCode::E4004, node, std::format("this function returns {} values, not {}",
				outputs.size(), values.size()));
			return Progress::DONE;
		}
		for (size_t i = 0; i < values.size(); ++i) {
			require_fit(checker, values[i], outputs[i].type, node->children.size() == values.size() ? node->children[i] : node,
				"the returned value");
			require_secret_fits(checker, values[i].is_secret, outputs[i].type, false,
				node->children.size() == values.size() ? node->children[i] : node, "the result");
		}
		return Progress::DONE;
	}

	static Progress check_condition(Checker& checker, ast::Node* node, std::string_view what) {
		Value condition;
		Progress progress = check_expression(checker, node, BUILTIN_bool, condition);
		if (progress != Progress::DONE) {
			return progress;
		}
		require_public(checker, node, std::format("{}'s condition", what));
		if (!is_boolean(default_type(condition)) && ValueKind::UNTYPED_BOOLEAN != condition.kind
			&& ValueKind::POISONED != condition.kind) {
			error_at(checker, ErrorCode::E4015, node, std::format("{} needs a boolean, not {}", what, describe(condition)));
		}
		return Progress::DONE;
	}

	// if, else if and else: whether control can continue after is whether any branch can.
	std::filesystem::path file_data_path(std::string_view including_file, const ast::Node* directive) {
		const ast::Node* argument = nullptr;
		for (const ast::Node* child : directive->children) {
			if (ast::NodeType::PAREN_GROUP != child->node_type) {
				argument = child;
			}
		}
		if (argument == nullptr || ast::NodeType::LITERAL != argument->node_type
			|| TokenType::LITERAL_STRING != argument->value.type) {
			return {};
		}
		// The lexer keeps a string literal's quotes
		std::string_view text(*argument->value.value);
		const std::filesystem::path relative(std::string(text.substr(1, text.size() - 2)));
		return (std::filesystem::path(including_file).parent_path() / relative).lexically_normal();
	}

	static Progress check_if(Checker& checker, ast::Node* node, bool& continues) {
		Progress progress = check_condition(checker, node->children[0], "if");
		if (progress != Progress::DONE) {
			return progress;
		}
		bool has_else = false;
		bool any_continues = false;
		for (size_t i = 1; i < node->children.size(); ++i) {
			ast::Node* branch = node->children[i];
			if (ast::NodeType::ELSE == branch->node_type && !branch->children.empty()) {
				has_else = true;
				branch = branch->children[0];
			}
			bool branch_continues = true;
			if (ast::NodeType::IF == branch->node_type) {
				progress = check_if(checker, branch, branch_continues);
			}
			else {
				checker.scopes.emplace_back();
				progress = check_block(checker, branch, branch_continues, nullptr, nullptr);
				checker.scopes.pop_back();
			}
			if (progress != Progress::DONE) {
				return progress;
			}
			any_continues = any_continues || branch_continues;
		}
		continues = any_continues || !has_else;
		return Progress::DONE;
	}

	// What a for loop goes through gives each value, and an index.
	static Progress check_for(Checker& checker, ast::Node* node) {
		std::vector<ast::Node*> names;
		ast::Node* iterable = nullptr;
		ast::Node* body = nullptr;
		bool after_in = false;
		for (ast::Node* child : node->children) {
			const ast::NodeType type = child->node_type;
			if (ast::NodeType::IN == type) {
				after_in = true;
			}
			else if (!after_in) {
				names.push_back(child);
			}
			else if (ast::NodeType::BLOCK == type) {
				body = child;
			}
			else if (ast::NodeType::DIRECTIVE == type && !is_text(child->value.value, "#reverse")) {
				// #reverse is a for loop's only directive (docs/control_flow.md)
				error_at(checker, ErrorCode::E4020, child, std::format("a for loop takes #reverse, not {}", text_of(child->value.value)));
			}
			else if (ast::NodeType::DIRECTIVE != type && iterable == nullptr) {
				iterable = child;
			}
		}
		if (iterable == nullptr || body == nullptr || names.empty()) {
			error_at(checker, ErrorCode::E4020, node, "a for loop needs a name, in, what to go through, and a body");
			return Progress::DONE;
		}
		Value element = poisoned();
		bool by_reference_allowed = false;
		bool element_mutable = false;
		const TokenType op = iterable->value.type;
		if (ast::NodeType::BINARY_OPERATOR == iterable->node_type
			&& (TokenType::OPERATOR_RANGE_EXCLUSIVE == op || TokenType::OPERATOR_RANGE_INCLUSIVE == op)) {
			Value low;
			Value high;
			Progress progress = check_expression(checker, iterable->children[0], nullptr, low);
			if (progress != Progress::DONE) {
				return progress;
			}
			progress = check_expression(checker, iterable->children[1], ValueKind::VALUE == low.kind ? low.type : nullptr, high);
			if (progress != Progress::DONE) {
				return progress;
			}
			require_public(checker, iterable->children[0], "where a loop starts");
			require_public(checker, iterable->children[1], "how many times a loop runs");
			Value shared;
			if (ValueKind::POISONED != low.kind && ValueKind::POISONED != high.kind
				&& (!common_type(low, high, shared) || !is_integer(default_type(shared)))) {
				error_at(checker, ErrorCode::E4015, iterable, "a range's bounds are integers of one type");
			}
			else if (ValueKind::POISONED != low.kind && ValueKind::POISONED != high.kind) {
				element = typed(default_type(shared));
				// Each bound in range of the element, like 0..<0xffff_ffff_ffff_ffff, which int can't hold
				if (!in_range(low, element.type)) {
					report_out_of_range(checker, low, element.type, iterable->children[0]);
				}
				else if (!in_range(high, element.type)) {
					report_out_of_range(checker, high, element.type, iterable->children[1]);
				}
			}
		}
		else {
			Value collection;
			Progress progress = check_expression(checker, iterable, nullptr, collection);
			if (progress != Progress::DONE) {
				return progress;
			}
			TypeInfo const* type = ValueKind::VALUE == collection.kind ? base_of(collection.type) : nullptr;
			if (type != nullptr && TypeInfoVariant::ARRAY == type->variant) {
				element = typed(static_cast<TypeInfoArray const*>(type)->element_type);
				// A secret's elements are secrets; how many there are isn't
				element.is_secret = collection.is_secret || is_secret_type(element.type);
				const bool elsewhere = ArrayType::STATIC != static_cast<TypeInfoArray const*>(type)->array_type;
				by_reference_allowed = collection.is_location || elsewhere;
				// A view's elements by its type; an array's by what holds it (docs/types.md, Mutability)
				element_mutable = ArrayType::VIEW == static_cast<TypeInfoArray const*>(type)->array_type
					? static_cast<TypeInfoArray const*>(type)->is_mutable : collection.is_mutable;
			}
			else if (type != nullptr && TypeInfoVariant::STRING == type->variant) {
				element = typed(BUILTIN_char);
			}
			else if (TypeInfoArchetype const* archetype = archetype_of(type); archetype != nullptr) {
				if (archetype->element != nullptr) {
					element = typed(archetype->element);
					by_reference_allowed = collection.is_location;
					element_mutable = collection.is_mutable;
				}
				else {
					not_promised(checker, iterable, archetype, "a for loop", std::format("constrain it with compiler.ViewOf({}, ...)",
						to_string(archetype)));
				}
			}
			else if (ValueKind::POISONED != collection.kind) {
				error_at(checker, ErrorCode::E4020, iterable, std::format("a for loop goes through a range or an array, not {}",
					describe(collection)));
			}
		}
		checker.scopes.emplace_back();
		for (size_t i = 0; i < names.size(); ++i) {
			ast::Node* name = names[i];
			if (i == 1) {
				declare_local(checker, name, name->value.value, typed(BUILTIN_usize));
				continue;
			}
			if (ast::NodeType::UNARY_OPERATOR == name->node_type && TokenType::SYM_AMPERSAND == name->value.type
				&& !name->children.empty()) {
				if (!by_reference_allowed && ValueKind::POISONED != element.kind) {
					error_at(checker, ErrorCode::E4020, name, "& in a for loop needs an array to point into");
				}
				if (element.is_secret && !is_secret_type(element.type)) {
					error_at(checker, ErrorCode::E4037, name, std::format(
						"a pointer to {} would lose that these are secrets; make the elements a #secret type", to_string(element.type)));
				}
				Value reference = ValueKind::VALUE == element.kind
					? typed(pointer_to(checker.walk, element.type, element_mutable, false, POINTER_SIZE)) : poisoned();
				declare_local(checker, name->children[0], name->children[0]->value.value, reference);
				continue;
			}
			declare_local(checker, name, name->value.value, element);
		}
		checker.loops += 1;
		checker.breakables += 1;
		bool continues = true;
		Progress progress = check_block(checker, body, continues, nullptr, nullptr);
		checker.loops -= 1;
		checker.breakables -= 1;
		checker.scopes.pop_back();
		return progress;
	}

	// Whether a block has a break for the loop it's in, which lets control continue after the loop.
	static bool has_break(const ast::Node* node, size_t depth) {
		const ast::NodeType type = node->node_type;
		if (ast::NodeType::UNARY_OPERATOR == type && TokenType::KEYWORD_OR_BREAK == node->value.type && depth == 0) {
			return true;
		}
		if (ast::NodeType::BREAK == type) {
			if (node->children.empty()) {
				return depth == 0;
			}
			const ast::Node* count = node->children[0];
			if (ast::NodeType::KEYWORD_ALL == count->node_type) {
				return true;
			}
			return count->value.value != nullptr && std::stoul(std::string(std::string_view(*count->value.value))) > depth;
		}
		if (ast::NodeType::FUNCTION == type) {
			return false;
		}
		const bool is_loop = ast::NodeType::LOOP == type || ast::NodeType::FOR_LOOP == type
			|| ast::NodeType::SWITCH == type;
		for (const ast::Node* child : node->children) {
			if (has_break(child, is_loop ? depth + 1 : depth)) {
				return true;
			}
		}
		return false;
	}

	// loop, with with and while (docs/control_flow.md, While).
	static Progress check_loop(Checker& checker, ast::Node* node, bool& continues) {
		checker.scopes.emplace_back();
		ast::Node* body = nullptr;
		ast::Node* condition = nullptr;
		for (ast::Node* child : node->children) {
			if (ast::NodeType::WITH_CLAUSE == child->node_type) {
				for (ast::Node* list : child->children) {
					for (ast::Node* statement : list->children) {
						bool ignored = true;
						Progress progress = check_statement(checker, statement, ignored);
						if (progress != Progress::DONE) {
							checker.scopes.pop_back();
							return progress;
						}
					}
				}
			}
			else if (ast::NodeType::BLOCK == child->node_type) {
				body = child;
			}
			else if (ast::NodeType::WHILE_CLAUSE == child->node_type && !child->children.empty()) {
				condition = child->children[0];
			}
		}
		Progress progress = Progress::DONE;
		if (condition != nullptr) {
			progress = check_condition(checker, condition, "while");
		}
		if (progress == Progress::DONE && body != nullptr) {
			checker.loops += 1;
			checker.breakables += 1;
			checker.scopes.emplace_back();
			bool body_continues = true;
			progress = check_block(checker, body, body_continues, nullptr, nullptr);
			checker.scopes.pop_back();
			checker.loops -= 1;
			checker.breakables -= 1;
		}
		checker.scopes.pop_back();
		// A loop without a condition only ends with a break
		continues = condition != nullptr || (body != nullptr && has_break(body, 0));
		return progress;
	}

	static bool is_wildcard(const ast::Node* node) {
		return ast::NodeType::UNDERSCORE == node->node_type;
	}

	/*
	 * One case's value against what's matched: a literal or range of it, an enum member, or a
	 * union's variant with names for its values, which the arm can use.
	 */
	// A pattern that names a variant's value rather than testing it: a plain name, with nothing after it.
	static bool is_binding(const ast::Node* pattern) {
		return ast::NodeType::IDENTIFIER == pattern->node_type && pattern->children.empty();
	}

	static Progress check_case_value(Checker& checker, ast::Node* pattern, const Value& subject,
		std::set<std::string>& covered) {

		if (is_wildcard(pattern)) {
			covered.insert("_");
			return Progress::DONE;
		}
		TypeInfo const* type = ValueKind::VALUE == subject.kind ? base_of(subject.type) : nullptr;
		const TokenType op = pattern->value.type;
		if (ast::NodeType::BINARY_OPERATOR == pattern->node_type
			&& (TokenType::OPERATOR_RANGE_EXCLUSIVE == op || TokenType::OPERATOR_RANGE_INCLUSIVE == op)) {
			for (ast::Node* bound : pattern->children) {
				Value value;
				Progress progress = check_expression(checker, bound, subject.type, value);
				if (progress != Progress::DONE) {
					return progress;
				}
				require_fit(checker, value, subject.type, bound, "a case");
			}
			return Progress::DONE;
		}
		// A union's variant, like Ok(value) or .Error(_)
		if (type != nullptr && TypeInfoVariant::UNION == type->variant
			&& (ast::NodeType::IDENTIFIER == pattern->node_type || ast::NodeType::ENUM_SHORTHAND == pattern->node_type)) {
			auto union_type = static_cast<TypeInfoUnion const*>(type);
			const UnionVariant* variant = nullptr;
			for (const UnionVariant& each : union_type->variants) {
				if (*each.name == *pattern->value.value) {
					variant = &each;
				}
			}
			if (variant == nullptr) {
				error_at(checker, ErrorCode::E4017, pattern, std::format("{} has no variant {}", to_string(subject.type),
					text_of(pattern->value.value)));
				return Progress::DONE;
			}
			std::vector<ast::Node*> bindings;
			for (ast::Node* child : pattern->children) {
				if (ast::NodeType::PAREN_GROUP == child->node_type) {
					bindings.assign(child->children.begin(), child->children.end());
				}
			}
			if (!bindings.empty() && bindings.size() != variant->types.size()) {
				error_at(checker, ErrorCode::E4018, pattern, std::format("{} holds {} values, not {}", text_of(variant->name),
					variant->types.size(), bindings.size()));
				return Progress::DONE;
			}
			/*
			 * Each value: named, ignored, or a pattern it must match too, like Error(.NotFound). An arm
			 * with one of those doesn't cover the whole variant by itself: for a variant of one value,
			 * what it covers is kept as Variant(covered), so arms like Some(.None) and Some(Some(x))
			 * can cover it together (exhaustive).
			 */
			bool whole_variant = true;
			for (size_t i = 0; i < bindings.size(); ++i) {
				if (is_wildcard(bindings[i])) {
					continue;
				}
				if (is_binding(bindings[i])) {
					declare_local(checker, bindings[i], bindings[i]->value.value, typed(variant->types[i]));
					continue;
				}
				whole_variant = false;
				std::set<std::string> nested;
				Progress progress = check_case_value(checker, bindings[i], typed(variant->types[i]), nested);
				if (progress != Progress::DONE) {
					return progress;
				}
				if (bindings.size() == 1) {
					for (const std::string& inner : nested) {
						covered.insert(std::format("{}({})", text_of(variant->name), inner));
					}
				}
			}
			if (whole_variant) {
				covered.insert(text_of(variant->name));
			}
			return Progress::DONE;
		}
		Value value;
		Progress progress = check_expression(checker, pattern, subject.type, value);
		if (progress != Progress::DONE) {
			return progress;
		}
		if (ValueKind::VALUE == subject.kind) {
			require_fit(checker, value, subject.type, pattern, "a case");
		}
		if (ast::NodeType::ENUM_SHORTHAND == pattern->node_type) {
			covered.insert(text_of(pattern->value.value));
		}
		else if (ast::NodeType::LITERAL == pattern->node_type && is_boolean(subject.type)) {
			covered.insert(TokenType::KEYWORD_TRUE == pattern->value.type ? "true" : "false");
		}
		return Progress::DONE;
	}

	// Whether the cases cover every value: every enum member, union variant or boolean, or _.
	static bool exhaustive(const Value& subject, const std::set<std::string>& covered) {
		if (covered.contains("_")) {
			return true;
		}
		TypeInfo const* type = ValueKind::VALUE == subject.kind ? base_of(subject.type) : nullptr;
		if (type == nullptr) {
			return true;
		}
		if (TypeInfoVariant::ENUM == type->variant) {
			for (InternedString member : static_cast<TypeInfoEnum const*>(type)->members) {
				if (!covered.contains(text_of(member))) {
					return false;
				}
			}
			return true;
		}
		if (TypeInfoVariant::UNION == type->variant) {
			for (const UnionVariant& variant : static_cast<TypeInfoUnion const*>(type)->variants) {
				const std::string name = text_of(variant.name);
				if (covered.contains(name)) {
					continue;
				}
				// Covered by the patterns on its value, like Some(.None) and Some(Some(x))
				if (variant.types.size() != 1) {
					return false;
				}
				std::set<std::string> inner;
				const std::string prefix = name + "(";
				for (const std::string& each : covered) {
					if (each.starts_with(prefix) && each.ends_with(")")) {
						inner.insert(each.substr(prefix.size(), each.size() - prefix.size() - 1));
					}
				}
				if (inner.empty() || !exhaustive(typed(variant.types[0]), inner)) {
					return false;
				}
			}
			return true;
		}
		if (TypeInfoVariant::BOOLEAN == type->variant) {
			return covered.contains("true") && covered.contains("false");
		}
		return false;
	}

	// The kinds of values match and switch go through (docs/control_flow.md).
	static bool can_match_on(const Value& subject, bool unions) {
		TypeInfo const* type = ValueKind::VALUE == subject.kind ? base_of(subject.type) : nullptr;
		if (type == nullptr) {
			return ValueKind::POISONED == subject.kind;
		}
		const TypeInfoVariant variant = type->variant;
		return TypeInfoVariant::INTEGER == variant || TypeInfoVariant::CHAR == variant
			|| TypeInfoVariant::STRING == variant || TypeInfoVariant::ENUM == variant
			|| TypeInfoVariant::BOOLEAN == variant || (unions && TypeInfoVariant::UNION == variant);
	}

	/*
	 * match (docs/control_flow.md, Match): each arm's values, then its result, which is a value, a
	 * block, or a statement like return. As a value, it's what the arms give; it must cover
	 * everything its subject can be.
	 */
	/*
	 * Wait until what's matched has its variants or members: a type a signature only needed
	 * declared, like a call's Result, may still be being laid out on another thread.
	 */
	static Progress complete_subject(Checker& checker, ast::Node* where, const Value& subject) {
		if (ValueKind::VALUE != subject.kind || subject.type == nullptr) {
			return Progress::DONE;
		}
		TypeInfo const* type = base_of(subject.type);
		if (type != nullptr && type->complete) {
			return Progress::DONE;
		}
		// An alias another thread hasn't resolved yet has no base to look at: wait for the alias itself
		return require_complete(checker.walk, where, const_cast<TypeInfo*>(type != nullptr ? type : subject.type));
	}

	/*
	 * The patterns or cases #inserts among a match's or switch's put there, in their place, before they're
	 * checked (docs/compilation.md, Code Values). FAILED once reported.
	 */
	static Progress insert_cases(Checker& checker, ast::Node* cases, std::string_view word) {
		ast::NodeStore& made = checker.walk.executor.program_info->made_nodes;
		for (size_t i = 0; i < cases->children.size(); ++i) {
			ast::Node* insert = cases->children[i];
			if (ast::NodeType::DIRECTIVE != insert->node_type || !is_text(insert->value.value, "#insert") || insert->children.empty()) {
				continue;
			}
			ast::Node* inserted = nullptr;
			Progress progress = insert_code(checker, insert, inserted);
			if (progress != Progress::DONE) {
				return progress;
			}
			std::vector<ast::Node*> items;
			if (!named_items(inserted, ast::NodeType::LIST, word, items)) {
				report_at(ErrorCode::E4014, checker.walk.file_path, &made, insert, std::format(
					"#insert among a {}'s {} puts {} there: quote them with #code {} {{ ... }}",
					word == "patterns" ? "match" : "switch", word, word, word));
				return Progress::FAILED;
			}
			auto at = cases->children.erase(cases->children.begin() + static_cast<std::ptrdiff_t>(i));
			cases->children.insert(at, items.begin(), items.end());
			--i;
		}
		return Progress::DONE;
	}

	static Progress check_match(Checker& checker, ast::Node* node, TypeInfo* expected, Value* result, bool& continues) {
		if (node->children.size() > 1) {
			Progress inserted = insert_cases(checker, node->children[1], "patterns");
			if (inserted == Progress::FAILED && result != nullptr) {
				*result = poisoned();
			}
			if (inserted != Progress::DONE) {
				return inserted == Progress::FAILED ? Progress::DONE : inserted;
			}
		}
		Value subject;
		Progress progress = check_expression(checker, node->children[0], nullptr, subject);
		if (progress == Progress::DONE) {
			progress = complete_subject(checker, node->children[0], subject);
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		require_public(checker, node->children[0], "which arm of a match runs");
		if (!can_match_on(subject, true)) {
			error_at(checker, ErrorCode::E4020, node->children[0], std::format("match goes through integers, characters, strings, enums, unions and booleans, not {}",
				describe(subject)));
		}
		std::set<std::string> covered;
		TypeInfo* type = expected;
		bool any_continues = false;
		if (result != nullptr) {
			*result = poisoned();
		}
		for (ast::Node* list : node->children) {
			if (ast::NodeType::LIST != list->node_type) {
				continue;
			}
			for (ast::Node* arm : list->children) {
				if (arm->children.empty()) {
					continue;
				}
				checker.scopes.emplace_back();
				for (size_t i = 0; i + 1 < arm->children.size(); ++i) {
					progress = check_case_value(checker, arm->children[i], subject, covered);
					if (progress != Progress::DONE) {
						checker.scopes.pop_back();
						return progress;
					}
				}
				ast::Node* outcome = arm->children.back();
				bool arm_continues = true;
				Value value = nothing();
				const ast::NodeType outcome_type = outcome->node_type;
				if (ast::NodeType::BLOCK == outcome_type) {
					checker.scopes.emplace_back();
					progress = check_block(checker, outcome, arm_continues, result != nullptr ? &value : nullptr, type);
					checker.scopes.pop_back();
				}
				else if (ast::NodeType::RETURN == outcome_type || ast::NodeType::BREAK == outcome_type
					|| ast::NodeType::CONTINUE == outcome_type || is_assignment(outcome)) {
					progress = check_statement(checker, outcome, arm_continues);
				}
				else {
					progress = check_expression(checker, outcome, type, value);
					arm_continues = !value.never_returns;
				}
				checker.scopes.pop_back();
				if (progress != Progress::DONE) {
					return progress;
				}
				any_continues = any_continues || arm_continues;
				if (result != nullptr && arm_continues && ValueKind::NOTHING != value.kind && ValueKind::POISONED != value.kind) {
					if (type == nullptr) {
						type = default_type(value);
					}
					else {
						require_fit(checker, value, type, outcome, "each arm of match");
					}
					*result = typed(type);
				}
			}
		}
		if (!exhaustive(subject, covered) && ValueKind::POISONED != subject.kind) {
			error_at(checker, ErrorCode::E4026, node, "match must cover every value it can be; add the missing cases, or case _");
		}
		continues = any_continues;
		return Progress::DONE;
	}

	/*
	 * switch (docs/control_flow.md, Switch): each case's values, then its statements. Control
	 * continues after it unless it has case _ and no case can finish.
	 */
	static Progress check_switch(Checker& checker, ast::Node* node, bool& continues) {
		if (node->children.size() > 1) {
			Progress inserted = insert_cases(checker, node->children[1], "cases");
			if (inserted != Progress::DONE) {
				return inserted == Progress::FAILED ? Progress::DONE : inserted;
			}
		}
		bool any_continues = false;
		Value subject;
		Progress progress = check_expression(checker, node->children[0], nullptr, subject);
		if (progress == Progress::DONE) {
			progress = complete_subject(checker, node->children[0], subject);
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		require_public(checker, node->children[0], "which case of a switch runs");
		if (!can_match_on(subject, false)) {
			error_at(checker, ErrorCode::E4020, node->children[0], std::format("switch goes through integers, characters, strings and enums, not {}",
				describe(subject)));
		}
		std::set<std::string> covered;
		for (ast::Node* list : node->children) {
			if (ast::NodeType::LIST != list->node_type) {
				continue;
			}
			for (ast::Node* entry : list->children) {
				if (ast::NodeType::SWITCH_CASE != entry->node_type || entry->children.empty()) {
					continue;
				}
				checker.scopes.emplace_back();
				for (size_t i = 0; i + 1 < entry->children.size(); ++i) {
					progress = check_case_value(checker, entry->children[i], subject, covered);
					if (progress != Progress::DONE) {
						checker.scopes.pop_back();
						return progress;
					}
				}
				bool case_continues = true;
				checker.breakables += 1;
				progress = check_block(checker, entry->children.back(), case_continues, nullptr, nullptr);
				checker.breakables -= 1;
				checker.scopes.pop_back();
				if (progress != Progress::DONE) {
					return progress;
				}
				any_continues = any_continues || case_continues || has_break(entry->children.back(), 0);
			}
		}
		// Once every case is checked, so it's reported once: a #fall_through goes on into the case after it
		for (ast::Node* list : node->children) {
			if (ast::NodeType::LIST != list->node_type) {
				continue;
			}
			for (size_t at = 0; at < list->children.size(); ++at) {
				ast::Node* entry = list->children[at];
				if (ast::NodeType::DIRECTIVE == entry->node_type && is_text(entry->value.value, "#fall_through")
					&& (at + 1 == list->children.size() || ast::NodeType::SWITCH_CASE != list->children[at + 1]->node_type)) {
					error_at(checker, ErrorCode::E4002, entry, "#fall_through needs a case after it to fall through to");
				}
			}
		}
		continues = any_continues || !covered.contains("_");
		return Progress::DONE;
	}

	/*
	 * push_context name (field = value, ...) or push_context name from value (docs/control_flow.md,
	 * Push Context): a new context for the block, named.
	 */
	static Progress check_push_context(Checker& checker, ast::Node* node, bool& continues) {
		TypeInfo* context = nullptr;
		Progress progress = base_type(checker, node, "runtime", "Context", context);
		if (progress != Progress::DONE) {
			return progress;
		}
		ast::Node* name = node->children.empty() ? nullptr : node->children[0];
		ast::Node* body = node->children.empty() ? nullptr : node->children.back();
		bool from = false;
		for (size_t i = 1; i + 1 < node->children.size(); ++i) {
			ast::Node* part = node->children[i];
			if (ast::NodeType::KEYWORD_FROM == part->node_type) {
				// from value: a whole context, which is the from's child
				from = true;
				if (!part->children.empty()) {
					Value value;
					progress = check_expression(checker, part->children[0], context, value);
					if (progress != Progress::DONE) {
						return progress;
					}
					require_fit(checker, value, context, part->children[0], "push_context ... from");
				}
				continue;
			}
			if (ast::NodeType::LIST == part->node_type && !from) {
				if (!checker.has_context) {
					error_at(checker, ErrorCode::E4027, node, "there's no context to copy here; push a whole one with push_context ... from");
				}
				if (part->children.empty()) {
					error_at(checker, ErrorCode::E4018, part, "push_context lists at least one field");
				}
				std::set<std::string> seen;
				auto structure = static_cast<TypeInfoStruct const*>(base_of(context));
				for (ast::Node* field : part->children) {
					if (!is_assign(field) || field->children.size() != 2) {
						error_at(checker, ErrorCode::E4018, field, "push_context lists fields as name = value");
						continue;
					}
					InternedString field_name = field->children[0]->value.value;
					if (!seen.insert(text_of(field_name)).second) {
						error_at(checker, ErrorCode::E4018, field, std::format("{} is listed twice", text_of(field_name)));
					}
					const StructMember* member = find_member(structure, field_name);
					if (member == nullptr) {
						error_at(checker, ErrorCode::E4017, field->children[0], std::format("the context has no field {}",
							text_of(field_name)));
					}
					Value value;
					progress = check_expression(checker, field->children[1], member != nullptr ? member->member_type : nullptr,
						value);
					if (progress != Progress::DONE) {
						return progress;
					}
					if (member != nullptr) {
						require_fit(checker, value, member->member_type, field->children[1], text_of(field_name));
					}
				}
				continue;
			}
			// from value: a whole context
			Value value;
			progress = check_expression(checker, part, context, value);
			if (progress != Progress::DONE) {
				return progress;
			}
			require_fit(checker, value, context, part, "push_context ... from");
		}
		checker.scopes.emplace_back();
		Value named = typed(context);
		named.is_location = true;
		named.is_context = true;
		if (name != nullptr && ast::NodeType::IDENTIFIER == name->node_type) {
			declare_local(checker, name, name->value.value, named);
		}
		const bool had_context = checker.has_context;
		checker.has_context = true;
		progress = body != nullptr && ast::NodeType::BLOCK == body->node_type
			? check_block(checker, body, continues, nullptr, nullptr) : Progress::DONE;
		checker.has_context = had_context;
		checker.scopes.pop_back();
		return progress;
	}

	// #assert condition: a compile-time constant that must be true (docs/directives.md).
	static Progress check_assert(Checker& checker, ast::Node* node) {
		if (node->children.empty()) {
			error_at(checker, ErrorCode::E4020, node, "#assert needs a condition");
			return Progress::DONE;
		}
		Progress progress = check_condition(checker, node->children[0], "#assert");
		if (progress != Progress::DONE) {
			return progress;
		}
		ConstantValue value;
		progress = evaluate_in(checker.walk, node->children[0], value);
		if (progress == Progress::DONE && ConstantValue::Kind::BOOLEAN == value.kind && !value.boolean) {
			error_at(checker, ErrorCode::E4010, node, "#assert's condition is false");
		}
		return progress == Progress::FAILED ? Progress::DONE : progress;
	}

	static Progress check_statement(Checker& checker, ast::Node* statement, bool& continues) {
		continues = true;
		const ast::NodeType type = statement->node_type;
		if (ast::NodeType::DEFINITION == type) {
			return check_definition(checker, statement);
		}
		if (is_assignment(statement)) {
			return check_assignment(checker, statement);
		}
		if (ast::NodeType::RETURN == type) {
			continues = false;
			return check_return(checker, statement);
		}
		if (ast::NodeType::BREAK == type || ast::NodeType::CONTINUE == type) {
			continues = false;
			const size_t available = ast::NodeType::BREAK == type ? checker.breakables : checker.loops;
			if (available == 0) {
				error_at(checker, ErrorCode::E4022, statement, std::format("{} is only in a loop",
					ast::NodeType::BREAK == type ? "break" : "continue"));
				return Progress::DONE;
			}
			// break 2 leaves two loops, so it has to be in at least two; break all, any
			if (ast::NodeType::BREAK == type && !statement->children.empty()
				&& ast::NodeType::LITERAL == statement->children[0]->node_type) {
				const ast::Node* count_node = statement->children[0];
				const unsigned long count = std::stoul(std::string(std::string_view(*count_node->value.value)));
				if (count == 0 || count > available) {
					error_at(checker, ErrorCode::E4022, count_node, std::format("break {} needs to be in {} loops, but it's in {}",
						count, count, available));
				}
			}
			return Progress::DONE;
		}
		if (ast::NodeType::IF == type) {
			return check_if(checker, statement, continues);
		}
		if (ast::NodeType::FOR_LOOP == type) {
			return check_for(checker, statement);
		}
		if (ast::NodeType::LOOP == type) {
			return check_loop(checker, statement, continues);
		}
		if (ast::NodeType::DEFER == type) {
			bool ignored = true;
			for (ast::Node* deferred : statement->children) {
				Progress progress = check_statement(checker, deferred, ignored);
				if (progress != Progress::DONE) {
					return progress;
				}
			}
			return Progress::DONE;
		}
		if (ast::NodeType::BLOCK == type) {
			checker.scopes.emplace_back();
			Progress progress = check_block(checker, statement, continues, nullptr, nullptr);
			checker.scopes.pop_back();
			return progress;
		}
		if (ast::NodeType::MATCH == type) {
			return check_match(checker, statement, nullptr, nullptr, continues);
		}
		if (ast::NodeType::SWITCH == type) {
			return check_switch(checker, statement, continues);
		}
		if (ast::NodeType::PUSH_CONTEXT == type) {
			return check_push_context(checker, statement, continues);
		}
		if (ast::NodeType::DIRECTIVE == type) {
			if (is_text(statement->value.value, "#assert")) {
				return check_assert(checker, statement);
			}
			if (is_text(statement->value.value, "#run")) {
				Value ignored;
				return statement->children.empty() ? Progress::DONE
					: check_expression(checker, statement->children[0], nullptr, ignored);
			}
			if (is_insertion(statement)) {
				ast::Node* inserted = nullptr;
				Progress progress = insert_code(checker, statement, inserted);
				if (progress != Progress::DONE) {
					return progress == Progress::FAILED ? Progress::DONE : progress;
				}
				become(checker, statement, inserted);
				return check_statement(checker, statement, continues);
			}
			// An #if chain is decided where its block is checked (check_block); any other directive here has nothing to check
			return Progress::DONE;
		}
		Value value;
		Progress progress = check_expression(checker, statement, nullptr, value);
		continues = !value.never_returns;
		return progress;
	}

	/*
	 * Decides an #if chain in a body (docs/directives.md): each condition, a compile-time constant,
	 * in order, giving the BLOCK of the first that's true, or of #else, or null.
	 */
	static Progress pick_branch(Checker& checker, const std::vector<ast::Node*>& chain, ast::Node*& picked) {
		picked = nullptr;
		for (ast::Node* branch : chain) {
			if (branch->children.empty()) {
				continue;
			}
			if (is_text(branch->value.value, "#else")) {
				picked = branch->children.back();
				return Progress::DONE;
			}
			ConstantValue condition;
			Progress progress = evaluate_in(checker.walk, branch->children[0], condition);
			if (progress == Progress::FAILED) {
				return Progress::DONE;
			}
			if (progress != Progress::DONE) {
				return progress;
			}
			if (ConstantValue::Kind::BOOLEAN != condition.kind) {
				error_at(checker, ErrorCode::E4010, branch, "an #if condition must be true or false");
				return Progress::DONE;
			}
			if (condition.boolean) {
				picked = branch->children.back();
				return Progress::DONE;
			}
		}
		return Progress::DONE;
	}

	/*
	 * A block's statements in order. Code after one that can't continue (return, break, a call to a
	 * #never_returns function) is unreachable. For a block used as a value, its last statement is
	 * its value.
	 */
	// Whether an expression uses an archetype or an unknown value, which only an instance knows.
	static bool uses_open_parameters(const Checker& checker, const ast::Node* node) {
		if ((ast::NodeType::IDENTIFIER == node->node_type || ast::NodeType::TYPE == node->node_type) && node->value.value != nullptr) {
			const std::string name = text_of(node->value.value);
			auto type = checker.walk.generic_types.find(name);
			if (type != checker.walk.generic_types.end() && archetype_of(type->second) != nullptr) {
				return true;
			}
			auto value = checker.walk.generic_values.find(name);
			if (value != checker.walk.generic_values.end() && ConstantValue::Kind::UNKNOWN == value->second.kind) {
				return true;
			}
		}
		for (const ast::Node* child : node->children) {
			if (ast::NodeType::BLOCK != child->node_type && uses_open_parameters(checker, child)) {
				return true;
			}
		}
		return false;
	}

	static Progress check_block(Checker& checker, ast::Node* block, bool& continues, Value* last_value,
		TypeInfo* expected) {

		continues = true;
		bool reported = false;
		for (size_t i = 0; i < block->children.size(); ++i) {
			ast::Node* statement = block->children[i];
			// A macro call, as #insert of what the macro gives
			if (is_macro_call(statement)) {
				Progress progress = expand_macro(checker, statement);
				if (progress == Progress::FAILED) {
					continue;
				}
				if (progress != Progress::DONE) {
					return progress;
				}
			}
			// #insert: the statements it puts here, among the block's, so what they define is seen after them
			if (is_insertion(statement) && !statement->children.empty()) {
				ast::Node* inserted = nullptr;
				Progress progress = insert_code(checker, statement, inserted);
				if (progress == Progress::FAILED) {
					continue;
				}
				if (progress != Progress::DONE) {
					return progress;
				}
				auto at = block->children.begin() + static_cast<std::ptrdiff_t>(i);
				at = block->children.erase(at);
				if (ast::NodeType::BLOCK == inserted->node_type || is_code_list(inserted)) {
					block->children.insert(at, inserted->children.begin(), inserted->children.end());
				}
				else {
					block->children.insert(at, inserted);
				}
				// Checked from where it was, which may now be nothing at all
				--i;
				continue;
			}
			if (!continues && !reported) {
				error_at(checker, ErrorCode::E4025, statement, "this can't be reached");
				reported = true;
			}
			if (ast::NodeType::DIRECTIVE == statement->node_type && is_text(statement->value.value, "#if")) {
				// An #if chain: the branch its conditions pick, as if written here
				std::vector<ast::Node*> chain{ statement };
				while (i + 1 < block->children.size()
					&& ast::NodeType::DIRECTIVE == block->children[i + 1]->node_type
					&& (is_text(block->children[i + 1]->value.value, "#else_if")
						|| is_text(block->children[i + 1]->value.value, "#else"))) {
					chain.push_back(block->children[++i]);
					if (is_text(chain.back()->value.value, "#else")) {
						break;
					}
				}
				// Deciding on an archetype or an unknown value is left to the instances, which check the branch they take
				bool open = false;
				for (ast::Node* branch : chain) {
					open = open || uses_open_parameters(checker, branch);
				}
				if (open) {
					checker.undecided = true;
					continue;
				}
				ast::Node* picked = nullptr;
				Progress progress = pick_branch(checker, chain, picked);
				if (progress != Progress::DONE) {
					return progress;
				}
				// Which branch, by its BLOCK, for generating only that one's code
				Value chosen = nothing();
				chosen.variant = chain.size();
				for (size_t branch = 0; branch < chain.size(); ++branch) {
					if (!chain[branch]->children.empty() && chain[branch]->children.back() == picked) {
						chosen.variant = branch;
					}
				}
				record(checker, statement, chosen);
				if (picked != nullptr) {
					bool branch_continues = true;
					progress = check_block(checker, picked, branch_continues, nullptr, nullptr);
					if (progress != Progress::DONE) {
						return progress;
					}
					continues = continues && branch_continues;
				}
				continue;
			}
			const bool is_last = i + 1 == block->children.size();
			if (is_last && last_value != nullptr && ast::NodeType::DEFINITION != statement->node_type
				&& !is_assignment(statement) && ast::NodeType::RETURN != statement->node_type
				&& ast::NodeType::BREAK != statement->node_type && ast::NodeType::CONTINUE != statement->node_type
				&& ast::NodeType::FOR_LOOP != statement->node_type && ast::NodeType::LOOP != statement->node_type
				&& ast::NodeType::BLOCK != statement->node_type) {
				Progress progress = check_expression(checker, statement, expected, *last_value);
				if (progress != Progress::DONE) {
					return progress;
				}
				continues = !last_value->never_returns;
				continue;
			}
			bool statement_continues = true;
			Progress progress = check_statement(checker, statement, statement_continues);
			if (progress != Progress::DONE) {
				return progress;
			}
			continues = continues && statement_continues;
		}
		return Progress::DONE;
	}

	// ---------------------------------------------------------------------------------------------
	// Functions

	// Parameters as locals, which can't be assigned; varargs as a view of them; named results as variables.
	static void declare_parameters(Checker& checker, ast::Node* function, TypeInfoFunction const* type) {
		const std::vector<Parameter> parameters = parameters_of(function);
		if (checker.record != nullptr) {
			for (const Parameter& parameter : parameters) {
				checker.record->parameters.push_back(parameter.node);
			}
		}
		for (size_t i = 0; i < parameters.size() && i < type->input.size(); ++i) {
			// A compile-time parameter, like T: type, is what its generic parameter is bound to
			auto bound = checker.walk.generic_types.find(text_of(parameters[i].name));
			if (bound != checker.walk.generic_types.end()) {
				declare_local(checker, parameters[i].node, parameters[i].name, type_value(bound->second));
				continue;
			}
			// Or a constant, like count in buffer :: fn[count](count: usize)
			if (checker.walk.generic_values.contains(text_of(parameters[i].name))) {
				declare_local(checker, parameters[i].node, parameters[i].name, typed(type->input[i].type));
				continue;
			}
			TypeInfo* parameter_type = type->input[i].type;
			if (type->input[i].is_varargs && parameter_type != nullptr) {
				parameter_type = array_of(checker.walk, parameter_type, ArrayType::VIEW, 0);
			}
			Value value = parameter_type != nullptr ? typed(parameter_type) : poisoned();
			value.is_location = true;
			declare_local(checker, parameters[i].node, parameters[i].name, value);
		}
		for (const FunctionOutput& output : type->output) {
			// A named result's key is its entry in the type, which lives as long as the program
			const void* key = output.name != nullptr ? static_cast<const void*>(&output) : nullptr;
			if (checker.record != nullptr) {
				checker.record->outputs.push_back(key);
			}
			if (output.name != nullptr) {
				Value value = typed(output.type);
				value.is_location = true;
				value.is_mutable = true;
				declare_local(checker, key, output.name, value);
			}
		}
	}

	// Entry points start without a context (docs/control_flow.md, Functions Without a Context).
	// Whether a function starts without a context: #no_context, or an interrupt or entry function.
	static bool starts_without_context(TypeInfoFunction const* function) {
		const std::string convention = text_of(function->calling_convention);
		return function->no_context || convention.find("entry") != std::string::npos
			|| convention.find("interrupt") != std::string::npos;
	}

	/*
	 * A function's body: every path that finishes returns its results, and a #never_returns one
	 * can't finish at all (docs/directives.md).
	 */
	/*
	 * In an instance, each value in the generic list that isn't also a parameter, like capacity in
	 * fn[T, capacity: usize]: a constant of its declared type (docs/types.md, Values in Generic Lists).
	 */
	static Progress declare_generic_values(Checker& checker, ast::Node* function_node) {
		for (ast::Node* child : function_node->children) {
			if (ast::NodeType::GENERIC_TAG != child->node_type) {
				continue;
			}
			for (ast::Node* parameter : child->children) {
				/*
				 * A derived value, like bits = size_of(T) * 8: an untyped constant, which takes the
				 * type it's used as, like C :: 5 (docs/types.md, Derived Parameters)
				 */
				if (ast::NodeType::DERIVED_PARAMETER == parameter->node_type) {
					auto derived = checker.walk.generic_values.find(text_of(parameter->value.value));
					if (derived == checker.walk.generic_values.end() || find_local(checker, parameter) != nullptr) {
						continue;
					}
					Value constant;
					if (ConstantValue::Kind::INTEGER == derived->second.kind) {
						constant.kind = ValueKind::UNTYPED_INTEGER;
					}
					else if (ConstantValue::Kind::BOOLEAN == derived->second.kind) {
						constant.kind = ValueKind::UNTYPED_BOOLEAN;
					}
					else {
						error_at(checker, ErrorCode::E4014, parameter, std::format("{} can only be derived as a type, an integer or a boolean",
							text_of(parameter->value.value)));
						continue;
					}
					declare_local(checker, parameter, parameter->value.value, constant);
					if (checker.record != nullptr) {
						checker.record->generic_constants[parameter] = derived->second;
					}
					continue;
				}
				if (ast::NodeType::COLON != parameter->node_type || parameter->children.size() < 2) {
					continue;
				}
				ast::Node* name = parameter->children[0];
				auto value = checker.walk.generic_values.find(text_of(name->value.value));
				if (value == checker.walk.generic_values.end() || find_local(checker, name) != nullptr) {
					continue;
				}
				TypeInfo* type = nullptr;
				Progress progress = check_type(checker, parameter->children[1], Need::DECLARED, type);
				if (progress != Progress::DONE) {
					return progress;
				}
				declare_local(checker, name, name->value.value, typed(type));
				if (checker.record != nullptr) {
					checker.record->generic_constants[name] = value->second;
				}
			}
		}
		return Progress::DONE;
	}

	/*
	 * Each parameter's default (docs/functions.md, Default Values): a call that leaves the parameter
	 * out runs it, in the caller, with the caller's context. It's checked here, with the function's
	 * names and before its parameters are declared, so it can't use them, and what checking finds is
	 * the function's, for the generator to use at each such call.
	 */
	static Progress check_parameter_defaults(Checker& checker, ast::Node* function_node, TypeInfoFunction const* type) {
		const bool had_context = checker.has_context;
		checker.has_context = true;
		size_t index = 0;
		for (ast::Node* list : function_node->children) {
			if (ast::NodeType::LIST != list->node_type) {
				continue;
			}
			for (ast::Node* parameter : list->children) {
				const bool has_default = ast::NodeType::BINARY_OPERATOR == parameter->node_type && is_assign(parameter)
					&& parameter->children.size() == 2;
				ast::Node* names_node = has_default ? parameter->children[0] : parameter;
				// One input per name: a, b : int = 0 is two, with the same default
				size_t count = 1;
				if (ast::NodeType::COLON == names_node->node_type) {
					for (ast::Node* part : names_node->children) {
						if (ast::NodeType::IDENTIFIER == part->node_type) {
							break;
						}
						if (ast::NodeType::LIST == part->node_type) {
							count = part->children.size();
							break;
						}
					}
				}
				if (has_default && index < type->input.size()) {
					ast::Node* value_node = parameter->children[1];
					Value value;
					Progress progress = check_expression(checker, value_node, type->input[index].type, value);
					if (progress != Progress::DONE) {
						checker.has_context = had_context;
						return progress;
					}
					require_fit(checker, value, type->input[index].type, value_node, "this default");
				}
				index += count;
			}
			break;
		}
		checker.has_context = had_context;
		return Progress::DONE;
	}

	/*
	 * The parameter a positional value goes to after parameter's, past any with defaults that follow a variadic one,
	 * which are only given by name; inputs.size() if there's none (docs/functions.md, Variable Arguments).
	 */
	static size_t next_positional(const std::vector<FunctionInput>& inputs, size_t parameter) {
		bool after_variadic = inputs[parameter].is_varargs;
		size_t next = parameter + 1;
		while (next < inputs.size() && after_variadic && inputs[next].has_default) {
			++next;
		}
		return next;
	}

	/*
	 * Variadic parameters with others after them are only allowed where a call can always tell where each one's values
	 * end: its type and those of the parameters a value after them could go to can't be taken for each other, up to the
	 * first one that isn't variadic, since each variadic one may be given nothing; and a parameter between two groups
	 * can't be taken for the variadic one after it. A parameter with a default after a variadic one is only given by name,
	 * so it's left out (docs/functions.md, Variable Arguments). A type a generic's body doesn't know yet is checked at each
	 * instance.
	 */
	static void check_variadic_boundaries(Checker& checker, ast::Node* where, TypeInfoFunction const* type) {
		const std::vector<FunctionInput>& inputs = type->input;
		const auto known = [](TypeInfo* each) {
			return each != nullptr && archetype_of(each) == nullptr;
		};
		const auto check_pair = [&](size_t first, size_t second) {
			if (!known(inputs[first].type) || !known(inputs[second].type) || !could_be_either(inputs[first].type, inputs[second].type)) {
				return;
			}
			const size_t variadic = inputs[first].is_varargs ? first : second;
			error_at(checker, ErrorCode::E4014, where, std::format("{} and {} can't be next to each other: a value could be taken "
				"for a {} or a {}, so a call couldn't tell where {}'s values end (docs/functions.md, Variable Arguments)",
				text_of(inputs[first].name), text_of(inputs[second].name), to_string(inputs[first].type), to_string(inputs[second].type),
				text_of(inputs[variadic].name)));
		};
		bool after_group = false;
		for (size_t i = 0; i < inputs.size(); ++i) {
			if (!inputs[i].is_varargs) {
				// One between two groups, like b in fn(a: A..., b: B, c: C...)
				if (after_group && !inputs[i].has_default && i + 1 < inputs.size() && inputs[i + 1].is_varargs) {
					check_pair(i, i + 1);
				}
				after_group = after_group && inputs[i].has_default;
				continue;
			}
			after_group = true;
			for (size_t j = next_positional(inputs, i); j < inputs.size(); j = next_positional(inputs, j)) {
				check_pair(i, j);
				if (!inputs[j].is_varargs) {
					break;
				}
			}
		}
	}

	static Progress check_function_body(Checker& checker, ast::Node* function_node, ast::Node* body,
		TypeInfoFunction const* type, const ast::Node* where) {

		Progress defaults = check_parameter_defaults(checker, function_node, type);
		if (defaults != Progress::DONE) {
			return defaults;
		}
		for (const FunctionInput& input : type->input) {
			report_relative(checker, function_node, input.type, input.name != nullptr
				? std::format("parameter {}", text_of(input.name)) : std::string("a parameter"));
		}
		for (const FunctionOutput& output : type->output) {
			report_relative(checker, function_node, output.type, "a result");
		}
		check_variadic_boundaries(checker, function_node, type);
		checker.scopes.emplace_back();
		declare_parameters(checker, function_node, type);
		Progress declared = declare_generic_values(checker, function_node);
		if (declared != Progress::DONE) {
			checker.scopes.pop_back();
			return declared;
		}
		checker.function = const_cast<TypeInfoFunction*>(type);
		checker.has_context = !starts_without_context(type);
		bool continues = true;
		checker.scopes.emplace_back();
		Progress progress = check_block(checker, body, continues, nullptr, nullptr);
		checker.scopes.pop_back();
		checker.scopes.pop_back();
		if (progress != Progress::DONE) {
			return progress;
		}
		if (checker.undecided) {
			// What an #if left to the instances may be what returns
		}
		else if (continues && type->never_returns) {
			error_at(checker, ErrorCode::E4019, where, "a #never_returns function can't finish; end it with a call that doesn't return, or a loop");
		}
		else if (continues && !type->output.empty()) {
			error_at(checker, ErrorCode::E4019, where, "this function can finish without returning its results; a stub calls todo()");
		}
		return Progress::DONE;
	}

	/*
	 * A function declared inside a function (docs/functions.md, Nesting Functions): a declaration of its own,
	 * resolved, checked and generated as one at the top level would be, without its name in the package. It
	 * sees the package's names, not the function's locals.
	 */
	static Progress check_nested_function(Checker& checker, ast::Node* definition, ast::Node* function, Value& result) {
		for (const ast::Node* child : function->children) {
			if (ast::NodeType::GENERIC_TAG == child->node_type) {
				result = error_at(checker, ErrorCode::E4024, function, "a generic function declared inside a function isn't supported yet");
				return Progress::DONE;
			}
		}
		if (ast::NodeType::LIST == definition->children[0]->node_type) {
			result = error_at(checker, ErrorCode::E4018, definition, "a function declared inside a function has one name");
			return Progress::DONE;
		}
		Declaration* nested = nested_declaration(checker.walk, definition);
		Progress progress = require_resolved(checker.walk, definition, nested, Need::RESOLVED);
		if (progress == Progress::FAILED) {
			result = poisoned();
			return Progress::DONE;
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		result = declaration_value(checker, nested);
		return Progress::DONE;
	}

	ast::Node* function_body(const Declaration* function) {
		bool after = false;
		for (ast::Node* child : function->node->children) {
			if (ast::NodeType::FUNCTION == child->node_type) {
				after = true;
			}
			else if (after && ast::NodeType::BLOCK == child->node_type) {
				return child;
			}
		}
		return nullptr;
	}

	Progress check_type_defaults(WorkThreadData& executor, Declaration* type) {
		TypeInfo const* base = get_base_type_or_alias(type->type_value);
		if (base == nullptr || TypeInfoVariant::FUNCTION != base->variant) {
			return Progress::DONE;
		}
		Progress result = Progress::DONE;
		for (const FunctionInput& input : static_cast<TypeInfoFunction const*>(base)->input) {
			if (input.default_value == nullptr || input.default_in_body) {
				continue;
			}
			Progress progress = check_type_default(executor, input);
			if (Progress::PARKED == progress) {
				return progress;
			}
			if (Progress::FAILED == progress) {
				result = progress;
			}
		}
		return result;
	}

	Progress check_body(WorkThreadData& executor, Declaration* function) {
		Declaration* generic = function->generic != nullptr ? function->generic : function;
		Walk walk{
			executor,
			function->package_path,
			function->file_name,
			function->file,
			nullptr,
			nullptr,
			file_path_of(function->package_path, function->file_name),
			{},
			{},
			{},
		};
		ast::Node* function_node_ = function_node(generic);
		ast::Node* body = function_body(generic);
		auto type = static_cast<TypeInfoFunction const*>(function->value_type);
		if (function_node_ == nullptr || body == nullptr || type == nullptr) {
			return Progress::DONE;
		}
		/*
		 * A constrained generic's body is checked once with archetypes, which have only what its
		 * constraints promise. What that body calls with them is only an instance in name: its own
		 * body is checked at real instances (docs/types.md, Checked Bodies).
		 */
		NameRegistry& registry = executor.program_info->names;
		const bool early = is_early_instance(function);
		if (function->generic != nullptr && !early && has_archetype_arguments(function)) {
			return Progress::DONE;
		}
		if (early) {
			Progress promised = promise_archetypes(walk, function);
			if (promised != Progress::DONE) {
				return promised;
			}
		}
		// A body the early check found errors in has them reported once, there, so instances wait for it
		if (function->generic != nullptr && !early) {
			Declaration* first = early_instance(registry, function->generic);
			if (first != nullptr) {
				Progress waited = wait_for_body(walk, function->node, first);
				if (waited != Progress::DONE) {
					return waited;
				}
			}
			if (early_check_failed(registry, function->generic)) {
				return Progress::DONE;
			}
		}
		/*
		 * An instance whose constraints aren't satisfied isn't checked: where it's used says why
		 * (docs/types.md, Constraints)
		 */
		if (function->generic != nullptr) {
			Progress satisfied = check_constraints(walk, function->node, function->generic, function, true);
			if (satisfied != Progress::DONE) {
				return satisfied;
			}
		}
		// An instance's generic parameters
		if (function->generic != nullptr) {
			const std::vector<std::string> names = generic_names(function_node_);
			for (size_t i = 0; i < names.size() && i < function->generic_arguments.size(); ++i) {
				if (function->generic_arguments[i] != nullptr) {
					bind_generic_type(walk, names[i], function->generic_arguments[i]);
				}
				else if (i < function->generic_values.size()) {
					walk.generic_values[names[i]] = function->generic_values[i];
				}
				walk.locals.push_back(intern(names[i]));
			}
		}
		// Its parameters' and results' types, which the signature only needed declared, laid out
		for (const FunctionInput& input : type->input) {
			Progress progress = require_complete(walk, function->node, input.type);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		for (const FunctionOutput& output : type->output) {
			Progress progress = require_complete(walk, function->node, output.type);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		auto checked = std::make_shared<CheckedBody>();
		checked->made = &executor.program_info->made_nodes;
		Checker checker(walk);
		checker.record = checked.get();
		const Options* options = executor.global_data->options;
		// Without startup code, the program starts at its entry function, before there's a context
		const bool entry = options != nullptr && !options->startup_code && function->generic == nullptr
			&& text_of(function->name) == options->entry && *function->package_path == *intern(options->input.string());
		if (entry && !starts_without_context(type)) {
			error_at(checker, ErrorCode::E4027, function->node, std::format(
				"{} is where the program starts, without a context: mark it #no_context (with #calling_convention(.c))",
				text_of(function->name)));
		}
		// A SlopOS program's entry takes its grants as parameters (docs/compilation.md, Entry Parameters)
		const bool slop_os_entry = options != nullptr && options->startup_code && OSType::SlopOS == options->os
			&& function->generic == nullptr && text_of(function->name) == options->entry
			&& *function->package_path == *intern(options->input.string());
		if (slop_os_entry) {
			for (const FunctionInput& input : type->input) {
				if (entry_grant_of(input.type).kind.empty()) {
					error_at(checker, ErrorCode::E4014, function->node, std::format(
						"{} is given from the program's startup grants, so it's a handle: a 4-byte distinct alias or struct, or an optional of one, not {}",
						text_of(input.name), to_string(input.type)));
				}
			}
		}
		checker.constant_time = marked_constant_time(generic->node);
		// A secret parameter or result is working with secrets, used or not (docs/memory.md, Secrets)
		for (const FunctionInput& input : type->input) {
			checker.saw_secret = checker.saw_secret || reaches_secret(input.type);
		}
		for (const FunctionOutput& output : type->output) {
			checker.saw_secret = checker.saw_secret || reaches_secret(output.type);
		}
		/*
		 * Not a generic's instance, like new_array[Key]: its signature is the generic's, which can't say,
		 * and its body is checked by the rules like any other
		 */
		if (checker.saw_secret && !checker.constant_time && function->generic == nullptr) {
			error_at(checker, ErrorCode::E4037, function->node, std::format(
				"{} takes or gives a secret, so it's marked #constant_time", text_of(function->name)));
		}
		const size_t errors_before = thread_error_count();
		Progress progress = check_function_body(checker, function_node_, body, type, function->node);
		/*
		 * #constant_time without a secret, maybe left behind when one moved elsewhere. Not for a generic's
		 * instances, since #constant_time on a generic says its secret instances are what it's for
		 */
		if (progress == Progress::DONE && checker.constant_time && !checker.saw_secret && function->generic == nullptr) {
			report_warning(WarningCode::W4002, checker.walk.file_path, function->node->value.line_number,
				function->node->value.column_number, std::format(
					"{} is #constant_time, but works with no secret: no #secret parameter or result, and none in its body",
					text_of(function->name)));
		}
		// Then what points into the stack, once everything in the body is known (docs/memory.md)
		if (progress == Progress::DONE && thread_error_count() == errors_before) {
			check_stack_pointers(*checked, body, type, checker.walk.file_path);
			// And that every index is in bounds (docs/types.md, Bounds Checking)
			check_bounds(*checked, body, type, checker.walk.file_path);
			/*
			 * And that each owner is released or moved (docs/memory.md, Owned Types), except in base/compiler's
			 * forget, duplicate and take, which are how owners are made and ended outside the rules
			 */
			const bool primitive = generic->package_path != nullptr && std::string_view(*generic->package_path).starts_with("<base>")
				&& std::string_view(*generic->package_path).ends_with("compiler");
			if (!primitive) {
				check_ownership(*checked, function_node_, body, type, checker.walk.file_path);
			}
		}
		if (early && progress != Progress::PARKED) {
			finish_early_check(registry, function, progress != Progress::DONE || thread_error_count() != errors_before);
		}
		if (progress == Progress::DONE && thread_error_count() == errors_before && !early) {
			std::scoped_lock<std::mutex> lock(registry.mutex);
			function->checked = checked;
		}
		return progress;
	}

	Progress check_top_level_run(WorkThreadData& executor, const FileLocation& file, ast::Node* expression,
		CheckedBody* record) {

		Walk walk{
			executor,
			file.package_path,
			file.file_name,
			find_file(executor.program_info, file.package_path, file.file_name),
			nullptr,
			nullptr,
			file_path_of(file.package_path, file.file_name),
			{},
			{},
			{},
		};
		TypeInfo* ignored = nullptr;
		return check_compile_time_expression(walk, expression, record, ignored);
	}

	Progress check_compile_time_expression(Walk& walk, ast::Node* expression, CheckedBody* record, TypeInfo*& type) {
		Progress ready = require_compile_time_runtime(walk, expression);
		if (ready != Progress::DONE) {
			return ready;
		}
		Walk inner = walk;
		Checker checker(inner);
		checker.record = record;
		checker.scopes.emplace_back();
		const size_t errors_before = thread_error_count();
		Value value;
		Progress progress = check_expression(checker, expression, nullptr, value);
		if (progress == Progress::DONE && thread_error_count() != errors_before) {
			return Progress::FAILED;
		}
		type = ValueKind::VALUE == value.kind || is_untyped(value) ? default_type(value) : nullptr;
		return progress;
	}

	Progress check_top_level_assert(WorkThreadData& executor, const FileLocation& file, ast::Node* node) {
		Walk walk{
			executor,
			file.package_path,
			file.file_name,
			find_file(executor.program_info, file.package_path, file.file_name),
			nullptr,
			nullptr,
			file_path_of(file.package_path, file.file_name),
			{},
			{},
			{},
		};
		Checker checker(walk);
		checker.scopes.emplace_back();
		return check_assert(checker, node);
	}

	TypeInfo* usual_type(const Value& value) {
		return default_type(value);
	}

	Progress check_constant(Walk& walk, ast::Node* value, TypeInfo* expected, Value& result, CheckedBody* record_into) {
		Checker checker(walk);
		checker.record = record_into;
		checker.scopes.emplace_back();
		Progress progress = check_expression(checker, value, expected, result);
		if (progress == Progress::DONE && expected != nullptr) {
			require_fit(checker, result, expected, value, "the constant's value");
		}
		return progress;
	}
}
