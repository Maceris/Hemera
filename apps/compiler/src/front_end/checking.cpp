#include <algorithm>
#include <format>
#include <map>
#include <set>

#include "error/reporting.h"
#include "front_end/checking.h"
#include "front_end/format_spec.h"
#include "front_end/front_end.h"
#include "front_end/bounds.h"
#include "front_end/ownership.h"
#include "front_end/stack_pointers.h"
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
		explicit Checker(Walk& walk_)
			: walk{ walk_ }
		{}
	};

	static bool is_text(InternedString value, std::string_view text) {
		return value != nullptr && std::string_view(*value) == text;
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
		report_error(code, checker.walk.file_path, where->value.line_number, where->value.column_number,
			std::move(details));
		return poisoned();
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
		checked.declaration = value.declaration;
		checked.local = value.local;
		checked.called = value.called;
		checked.called_declaration = value.called_declaration;
		checked.variant = value.variant;
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
		checker.scopes.back().locals.push_back({ name, std::move(value) });
	}

	static const Local* find_local(const Checker& checker, InternedString name) {
		for (auto scope = checker.scopes.rbegin(); scope != checker.scopes.rend(); ++scope) {
			for (auto local = scope->locals.rbegin(); local != scope->locals.rend(); ++local) {
				if (*local->name == *name) {
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
			return "an integer";
		}
		if (ValueKind::UNTYPED_FLOAT == kind) {
			return "a floating point number";
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
		if (TypeInfoVariant::ARRAY == source->variant && TypeInfoVariant::ARRAY == target->variant) {
			auto a = static_cast<TypeInfoArray const*>(source);
			auto b = static_cast<TypeInfoArray const*>(target);
			return ArrayType::VIEW == b->array_type && same_type(a->element_type, b->element_type);
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
				|| ValueKind::UNTYPED_BOOLEAN == kind || ValueKind::TYPE == kind;
		}
		if (ValueKind::VALUE == kind) {
			return assignable(value.type, type);
		}
		if (ValueKind::UNTYPED_INTEGER == kind) {
			return is_integer(type) || is_float(type) || promised(type, CAPABILITY_ARITHMETIC);
		}
		if (ValueKind::UNTYPED_FLOAT == kind) {
			return is_float(type) || promised(type, CAPABILITY_FLOAT);
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

	// Reports a value that can't be used as type. Returns whether it fits.
	static bool require_fit(Checker& checker, const Value& value, TypeInfo* type, const ast::Node* where,
		std::string_view what) {

		if (fits(value, type)) {
			return true;
		}
		error_at(checker, ErrorCode::E4015, where, std::format("{} needs {}, not {}", what, to_string(type),
			describe(value)));
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
		value.kind = Untyped::INTEGER == untyped ? ValueKind::UNTYPED_INTEGER
			: Untyped::FLOAT == untyped ? ValueKind::UNTYPED_FLOAT
			: Untyped::STRING == untyped ? ValueKind::UNTYPED_STRING
			: Untyped::BOOLEAN == untyped ? ValueKind::UNTYPED_BOOLEAN
			: ValueKind::POISONED;
		(void)checker;
		return value;
	}

	static bool is_builtin_function(std::string_view name) {
		return name == "size_of" || name == "align_of" || name == "offset_of" || name == "type_of"
			|| name == "type_info_of" || name == "types_are_aliases" || name == "max_value"
			|| name == "min_value" || name == "todo";
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
		if (const Local* local = find_local(checker, name)) {
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
		if (is_pointer_name(text_of(name))) {
			// ptr or a relative pointer, which is a type once it's given what it points to
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
				return Progress::DONE;
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
		TypeInfo const* type = base_of(value.type);
		bool is_mutable = value.is_mutable;
		if (TypeInfoVariant::POINTER == type->variant && static_cast<TypeInfoPointer const*>(type)->base_type != nullptr) {
			is_mutable = static_cast<TypeInfoPointer const*>(type)->is_mutable;
			type = base_of(static_cast<TypeInfoPointer const*>(type)->base_type);
		}
		TypeInfo* element = nullptr;
		if (TypeInfoVariant::ARRAY == type->variant) {
			element = static_cast<TypeInfoArray const*>(type)->element_type;
			if (ArrayType::STATIC != static_cast<TypeInfoArray const*>(type)->array_type) {
				is_mutable = true;
			}
		}
		else if (TypeInfoVariant::STRING == type->variant) {
			element = BUILTIN_char;
			is_mutable = false;
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
			value = typed(array_of(checker.walk, element, ArrayType::VIEW, 0));
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
		value = typed(element);
		value.is_location = true;
		value.is_mutable = is_mutable;
		return Progress::DONE;
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
		std::string text = text_of(literal->value.value);
		if (text.size() >= 2 && text.front() == '"' && text.back() == '"') {
			text = text.substr(1, text.size() - 2);
		}
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
			const FunctionInput& input = function->input[parameter];
			TypeInfo* expected = input.type;
			if (input.is_varargs && expected != nullptr) {
				/*
				 * Each remaining value is one of the varargs, unless the first is a view of them,
				 * which is passed on whole, and the values after it go to the parameters after
				 * the varargs (docs/functions.md, Variable Arguments).
				 */
				Value value;
				Progress progress = positional_value(checker, positional, expected, value);
				if (progress != Progress::DONE) {
					return progress;
				}
				TypeInfo const* passed = ValueKind::VALUE == value.kind ? base_of(value.type) : nullptr;
				const bool passed_on = !given[parameter] && passed != nullptr && TypeInfoVariant::ARRAY == passed->variant
					&& ArrayType::VIEW == static_cast<TypeInfoArray const*>(passed)->array_type
					&& same_type(static_cast<TypeInfoArray const*>(passed)->element_type, expected);
				given[parameter] = true;
				if (passed_on) {
					format_values_known = false;
					++parameter;
					continue;
				}
				format_values.emplace_back(argument, value);
				require_fit(checker, value, expected, argument, std::format("{}", text_of(input.name)));
				require_stays(checker, value, input, function, argument);
				continue;
			}
			Value value;
			Progress progress = positional_value(checker, positional, expected, value);
			if (progress != Progress::DONE) {
				return progress;
			}
			require_fit(checker, value, expected, argument,
				input.name != nullptr ? std::format("{}", text_of(input.name)) : std::string("the argument"));
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
				if (ast::NodeType::IDENTIFIER == argument->node_type && find_local(checker, argument->value.value) != nullptr
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
		callee = call_result(signature, instance);
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
		// type_info_of also takes a type value, like an any's type
		const bool takes_type = name != "type_of";
		const bool type_value_given = name == "type_info_of" && ValueKind::VALUE == values[0].kind
			&& is_variant(values[0].type, TypeInfoVariant::TYPE);
		if (takes_type && ValueKind::TYPE != values[0].kind && ValueKind::POISONED != values[0].kind && !type_value_given) {
			callee = error_at(checker, ErrorCode::E4015, arguments[0], std::format("{} takes a type", name));
			return Progress::DONE;
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
	static Declaration* release_function_of(Checker& checker, TypeInfo const* type) {
		TypeInfo const* base = base_of(type);
		if (base == nullptr || TypeInfoVariant::STRUCT != base->variant) {
			return nullptr;
		}
		auto structure = static_cast<TypeInfoStruct const*>(base);
		if (!structure->is_owned || structure->release_name == nullptr) {
			return nullptr;
		}
		NameRegistry& names = checker.walk.executor.program_info->names;
		const Declaration* declared = structure->instance;
		if (declared == nullptr) {
			std::scoped_lock<std::mutex> lock(names.mutex);
			auto found = names.type_declarations.find(const_cast<TypeInfo*>(base));
			declared = found != names.type_declarations.end() ? found->second : nullptr;
		}
		if (declared == nullptr) {
			return nullptr;
		}
		InternedString package = declared->package_path;
		if (structure->release_package != nullptr) {
			package = declared->file != nullptr ? imported_package(declared->file, structure->release_package) : nullptr;
		}
		std::scoped_lock<std::mutex> lock(names.mutex);
		auto found = package != nullptr ? names.declarations.find(std::make_pair(package, structure->release_name))
			: names.declarations.end();
		return found != names.declarations.end() ? found->second : nullptr;
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
		// Without a context, only what takes none can be called: intrinsics, and #no_context functions
		if (!checker.has_context && !function->no_context) {
			const bool intrinsic = callee.declaration != nullptr && is_base_package(callee.declaration->package_path)
				&& function_body(callee.declaration) == nullptr;
			if (!intrinsic) {
				error_at(checker, ErrorCode::E4027, where,
					"without a context, only intrinsics and #no_context functions can be called; push one with push_context ... from first");
			}
		}
		std::vector<InternedString> names;
		if (callee.declaration != nullptr && DeclarationKind::FUNCTION == callee.declaration->kind) {
			if (ast::Node* node = function_node(callee.declaration)) {
				for (const Parameter& parameter : parameters_of(node)) {
					names.push_back(parameter.name);
				}
			}
		}
		Progress progress = check_arguments(checker, where, function, split_arguments(checker, arguments, piped, where),
			names, piped);
		if (progress != Progress::DONE) {
			return progress;
		}
		Declaration* called = callee.declaration != nullptr && DeclarationKind::FUNCTION == callee.declaration->kind
			? callee.declaration : nullptr;
		callee = call_result(function, called);
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
	static void dereference(Checker& checker, ast::Node* where, Value& value) {
		if (ValueKind::POISONED == value.kind) {
			return;
		}
		TypeInfo const* type = ValueKind::VALUE == value.kind ? base_of(value.type) : nullptr;
		if (type == nullptr || TypeInfoVariant::POINTER != type->variant
			|| static_cast<TypeInfoPointer const*>(type)->base_type == nullptr) {
			value = error_at(checker, ErrorCode::E4020, where, std::format("{} can't be dereferenced; ^ needs a typed pointer",
				describe(value)));
			return;
		}
		auto pointer = static_cast<TypeInfoPointer const*>(type);
		value = typed(pointer->base_type);
		value.is_location = true;
		value.is_mutable = pointer->is_mutable;
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
			|| (is_text(node->value.value, "ptr") || std::string_view(*node->value.value).starts_with("relptr"));
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
			&& ast::NodeType::ARRAY_DIMENSION == node->children[next]->node_type && find_local(checker, node->value.value) == nullptr) {
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
							if (ast::NodeType::IDENTIFIER == argument->node_type && find_local(checker, argument->value.value) != nullptr
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
						progress = check_type(checker, argument, Need::DECLARED, argument_type);
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
				dereference(checker, child, value);
			}
			if (progress == Progress::FAILED) {
				value = poisoned();
				progress = Progress::DONE;
			}
			if (progress != Progress::DONE) {
				return progress;
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
			|| ValueKind::NULL_VALUE == kind;
	}

	/*
	 * The type two operands share: an untyped one takes the other's type; otherwise one converts
	 * to the other (docs/operators.md: identical or implicitly convertible).
	 */
	static bool common_type(const Value& left, const Value& right, Value& result) {
		if (is_untyped(left) && is_untyped(right)) {
			result = left;
			if (ValueKind::UNTYPED_FLOAT == right.kind) {
				result.kind = ValueKind::UNTYPED_FLOAT;
			}
			return left.kind == right.kind || (ValueKind::UNTYPED_INTEGER == left.kind || ValueKind::UNTYPED_FLOAT == left.kind)
				== (ValueKind::UNTYPED_INTEGER == right.kind || ValueKind::UNTYPED_FLOAT == right.kind);
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
		// Raw and relative pointers allow arithmetic with integers (docs/types.md, Pointers)
		const bool raw_left = ValueKind::VALUE == left.kind && is_pointer(left.type)
			&& (static_cast<TypeInfoPointer const*>(base_of(left.type))->base_type == nullptr
				|| static_cast<TypeInfoPointer const*>(base_of(left.type))->is_relative);
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
			return Progress::DONE;
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
			if (ordered && !(is_numeric(type) || is_enum(type) || is_variant(type, TypeInfoVariant::CHAR))) {
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
			result = typed(pointer_to(checker.walk, operand.type, operand.is_mutable && !operand.is_context, false,
				POINTER_SIZE));
			return Progress::DONE;
		}
		if (TokenType::OPERATOR_DEREFERENCE == op) {
			result = operand;
			dereference(checker, node, result);
			return Progress::DONE;
		}
		TypeInfo* type = default_type(operand);
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
		return from == to || assignable(const_cast<TypeInfo*>(from), const_cast<TypeInfo*>(to))
			|| (scalar(from) && scalar(to));
	}

	// cast[T](x), bit_cast[T](x) and auto_cast(x), then anything after it, like ^ or .member.
	static Progress check_cast(Checker& checker, ast::Node* node, TypeInfo* expected, Value& result) {
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
		if (ValueKind::POISONED == value.kind) {
			result = typed(target);
			return apply_postfix(checker, node, rest, result);
		}
		TypeInfo* source = default_type(value);
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
		TypeInfo const* base = base_of(type);
		ast::Node* list = nullptr;
		for (ast::Node* child : node->children) {
			if (ast::NodeType::LIST == child->node_type) {
				list = child;
			}
		}
		result = typed(type);
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

	// if as an expression: each branch's block ends with its value.
	static Progress check_if_expression(Checker& checker, ast::Node* node, TypeInfo* expected, Value& result) {
		Value condition;
		Progress progress = check_expression(checker, node->children[0], BUILTIN_bool, condition);
		if (progress != Progress::DONE) {
			return progress;
		}
		require_fit(checker, condition, BUILTIN_bool, node->children[0], "if's condition");
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

	static Progress check_literal(Checker& checker, ast::Node* node, Value& result) {
		const TokenType token = node->value.type;
		if (TokenType::LITERAL_INTEGER == token) {
			result.kind = ValueKind::UNTYPED_INTEGER;
		}
		else if (TokenType::LITERAL_FLOATING_POINT == token) {
			result.kind = ValueKind::UNTYPED_FLOAT;
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

	static Progress check_expression(Checker& checker, ast::Node* node, TypeInfo* expected, Value& result) {
		Progress progress = check_expression_inner(checker, node, expected, result);
		if (progress == Progress::DONE) {
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
				//TODO(ches) run it; for now it has the type of what it runs
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
			if (TokenType::INVALID == op) {
				require_fit(checker, value, types[i], targets[i], "this assignment");
				continue;
			}
			Value shared;
			if (!common_type(target_values[i], value, shared) && ValueKind::POISONED != value.kind) {
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
			Progress progress = check_type(checker, parts.type, Need::RESOLVED, type);
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
				value = typed(default_type(value));
			}
			if (!parts.is_constant && ValueKind::TYPE == value.kind) {
				value = typed(BUILTIN_type);
			}
			value.never_returns = false;
			value.is_location = ValueKind::VALUE == value.kind;
			value.is_mutable = !parts.is_constant && ValueKind::VALUE == value.kind;
			value.is_context = false;
			declare_local(checker, parts.names[i], parts.names[i]->value.value, value);
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
		}
		return Progress::DONE;
	}

	static Progress check_condition(Checker& checker, ast::Node* node, std::string_view what) {
		Value condition;
		Progress progress = check_expression(checker, node, BUILTIN_bool, condition);
		if (progress != Progress::DONE) {
			return progress;
		}
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
			Value shared;
			if (ValueKind::POISONED != low.kind && ValueKind::POISONED != high.kind
				&& (!common_type(low, high, shared) || !is_integer(default_type(shared)))) {
				error_at(checker, ErrorCode::E4015, iterable, "a range's bounds are integers of one type");
			}
			else if (ValueKind::POISONED != low.kind && ValueKind::POISONED != high.kind) {
				element = typed(default_type(shared));
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
				const bool elsewhere = ArrayType::STATIC != static_cast<TypeInfoArray const*>(type)->array_type;
				by_reference_allowed = collection.is_location || elsewhere;
				element_mutable = collection.is_mutable || elsewhere;
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
		TypeInfo const* type = ValueKind::VALUE == subject.kind ? base_of(subject.type) : nullptr;
		if (type == nullptr || type->complete) {
			return Progress::DONE;
		}
		return require_complete(checker.walk, where, const_cast<TypeInfo*>(type));
	}

	static Progress check_match(Checker& checker, ast::Node* node, TypeInfo* expected, Value* result, bool& continues) {
		Value subject;
		Progress progress = check_expression(checker, node->children[0], nullptr, subject);
		if (progress == Progress::DONE) {
			progress = complete_subject(checker, node->children[0], subject);
		}
		if (progress != Progress::DONE) {
			return progress;
		}
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
		bool any_continues = false;
		Value subject;
		Progress progress = check_expression(checker, node->children[0], nullptr, subject);
		if (progress == Progress::DONE) {
			progress = complete_subject(checker, node->children[0], subject);
		}
		if (progress != Progress::DONE) {
			return progress;
		}
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
			//TODO(ches) #if inside a function, which picks its branch at compile time
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
					if (derived == checker.walk.generic_values.end() || find_local(checker, parameter->value.value) != nullptr) {
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
				if (value == checker.walk.generic_values.end() || find_local(checker, name->value.value) != nullptr) {
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

	static Progress check_function_body(Checker& checker, ast::Node* function_node, ast::Node* body,
		TypeInfoFunction const* type, const ast::Node* where) {

		Progress defaults = check_parameter_defaults(checker, function_node, type);
		if (defaults != Progress::DONE) {
			return defaults;
		}
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

	// A function defined inside another: like a top-level one, it can't use the outer one's locals.
	static Progress check_nested_function(Checker& checker, ast::Node* definition, ast::Node* function, Value& result) {
		TypeInfo* type = nullptr;
		Progress progress = check_type(checker, function, Need::DECLARED, type);
		if (progress == Progress::FAILED) {
			result = poisoned();
			return Progress::DONE;
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		result = typed(type);
		ast::Node* body = nullptr;
		bool after = false;
		for (ast::Node* child : definition->children) {
			if (child == function) {
				after = true;
			}
			else if (after && ast::NodeType::BLOCK == child->node_type) {
				body = child;
			}
		}
		if (body == nullptr) {
			return Progress::DONE;
		}
		Checker nested(checker.walk);
		return check_function_body(nested, function, body, static_cast<TypeInfoFunction const*>(type), definition);
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
		const size_t errors_before = thread_error_count();
		Progress progress = check_function_body(checker, function_node_, body, type, function->node);
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
