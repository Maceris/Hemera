#include <algorithm>
#include <format>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "error/reporting.h"
#include "front_end/stack_pointers.h"

/*
 * docs/memory.md, Pointers to the Stack. Every value whose type can hold a pointer is unrestricted or
 * local; a local one has an origin, the scope depth of the block whose variables it points into, or
 * a parameter. What's stored in a variable is flow-insensitive: a variable holds everything ever
 * assigned to it, so the body is walked until that settles, then once more to report.
 *
 * This walks a body the way the generator does (middle_end/generate.cpp), from what the checker
 * recorded at each node, so it sees the same conversions: a static array becoming a view of where it
 * is, and a value becoming an any, which points at a copy of it in the frame.
 */

namespace hemera {

	namespace {

		// A parameter's origin: it lives longer than anything in the function.
		constexpr size_t PARAMETER = 0;
		// The depth of the function's outermost block, which temporaries and parameters' copies live as long as.
		constexpr size_t FRAME = 2;
		// Not one parameter, or several.
		constexpr int NO_PARAMETER = -1;
		constexpr int SEVERAL_PARAMETERS = -2;

		bool is_text(InternedString value, std::string_view text) {
			return value != nullptr && std::string_view(*value) == text;
		}

		std::string text_of(InternedString value) {
			return value != nullptr ? std::string(std::string_view(*value)) : std::string("_");
		}

		bool is_assign(const ast::Node* node) {
			return TokenType::OPERATOR_ASSIGN == node->value.type;
		}

		bool is_compound_assignment(TokenType op) {
			const TokenType operators[] = {
				TokenType::OPERATOR_ASSIGN_ADD, TokenType::OPERATOR_ASSIGN_SUB, TokenType::OPERATOR_ASSIGN_MUL,
				TokenType::OPERATOR_ASSIGN_DIV, TokenType::OPERATOR_ASSIGN_MOD, TokenType::OPERATOR_ASSIGN_REMAINDER,
				TokenType::OPERATOR_ASSIGN_BITWISE_AND, TokenType::OPERATOR_ASSIGN_BITWISE_OR,
				TokenType::OPERATOR_ASSIGN_BITWISE_XOR, TokenType::OPERATOR_ASSIGN_LEFT_SHIFT,
				TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC, TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL,
				TokenType::OPERATOR_ASSIGN_AND, TokenType::OPERATOR_ASSIGN_OR,
			};
			return std::find(std::begin(operators), std::end(operators), op) != std::end(operators);
		}

		bool is_assignment(const ast::Node* node) {
			return ast::NodeType::BINARY_OPERATOR == node->node_type && node->children.size() == 2
				&& (is_assign(node) || is_compound_assignment(node->value.type));
		}

		bool is_wildcard(const ast::Node* node) {
			return ast::NodeType::UNDERSCORE == node->node_type;
		}

		bool is_untyped(ValueKind kind) {
			return ValueKind::UNTYPED_INTEGER == kind || ValueKind::UNTYPED_FLOAT == kind
				|| ValueKind::UNTYPED_COMPLEX == kind || ValueKind::UNTYPED_QUATERNION == kind
				|| ValueKind::UNTYPED_STRING == kind || ValueKind::UNTYPED_BOOLEAN == kind
				|| ValueKind::NULL_VALUE == kind;
		}

		// ---------------------------------------------------------------------------------------------
		// Types

		TypeInfo const* base(TypeInfo const* type) {
			return type != nullptr ? get_base_type(type) : nullptr;
		}

		bool is_variant(TypeInfo const* type, TypeInfoVariant variant) {
			type = base(type);
			return type != nullptr && variant == type->variant;
		}

		bool is_array(TypeInfo const* type, ArrayType kind) {
			type = base(type);
			return type != nullptr && TypeInfoVariant::ARRAY == type->variant
				&& kind == static_cast<TypeInfoArray const*>(type)->array_type;
		}

		TypeInfo* element_of(TypeInfo const* type) {
			type = base(type);
			return type != nullptr && TypeInfoVariant::ARRAY == type->variant ? static_cast<TypeInfoArray const*>(type)->element_type
				: BUILTIN_char;
		}

		TypeInfo* pointee(TypeInfo const* type) {
			type = base(type);
			return type != nullptr && TypeInfoVariant::POINTER == type->variant ? static_cast<TypeInfoPointer const*>(type)->base_type
				: nullptr;
		}

		bool is_scoped(TypeInfo const* type) {
			type = base(type);
			return type != nullptr && TypeInfoVariant::STRUCT == type->variant && static_cast<TypeInfoStruct const*>(type)->is_scoped;
		}

		// Whether a value of type can hold a pointer into the stack, so where it points matters.
		bool carries_pointers(TypeInfo const* type) {
			type = base(type);
			if (type == nullptr) {
				return false;
			}
			if (TypeInfoVariant::POINTER == type->variant) {
				return true;
			}
			if (TypeInfoVariant::ANY == type->variant || TypeInfoVariant::STRING == type->variant) {
				return true;
			}
			if (TypeInfoVariant::ARRAY == type->variant) {
				auto array = static_cast<TypeInfoArray const*>(type);
				return ArrayType::STATIC != array->array_type || carries_pointers(array->element_type);
			}
			if (TypeInfoVariant::STRUCT == type->variant) {
				if (static_cast<TypeInfoStruct const*>(type)->is_unrestricted) {
					return false;
				}
				for (const StructMember& member : static_cast<TypeInfoStruct const*>(type)->members) {
					if (carries_pointers(member.member_type)) {
						return true;
					}
				}
				return false;
			}
			if (TypeInfoVariant::UNION == type->variant) {
				for (const UnionVariant& variant : static_cast<TypeInfoUnion const*>(type)->variants) {
					for (TypeInfo* held : variant.types) {
						if (carries_pointers(held)) {
							return true;
						}
					}
				}
			}
			return false;
		}

		// The values that may be deep: an any, and a pointer to a #scoped struct.
		bool is_deep_kind(TypeInfo const* type) {
			return is_variant(type, TypeInfoVariant::ANY) || is_scoped(pointee(type));
		}

		// A member's type by name, through using and anonymous structs as the generator finds it.
		TypeInfo* member_type(TypeInfoStruct const* structure, InternedString name) {
			for (const StructMember& member : structure->members) {
				if (member.name != nullptr && !member.is_using && *member.name == *name) {
					return member.member_type;
				}
			}
			for (const StructMember& member : structure->members) {
				TypeInfo const* included = base(member.member_type);
				if ((member.is_using || member.name == nullptr) && included != nullptr && TypeInfoVariant::STRUCT == included->variant) {
					if (TypeInfo* found = member_type(static_cast<TypeInfoStruct const*>(included), name)) {
						return found;
					}
				}
			}
			for (const StructMember& member : structure->members) {
				if (member.is_using && member.name != nullptr && *member.name == *name) {
					return member.member_type;
				}
			}
			return nullptr;
		}

		// What an optional or result holds, or null for Result[void, E]'s Ok.
		TypeInfo* held_type(TypeInfo const* type) {
			type = base(type);
			if (type == nullptr || TypeInfoVariant::UNION != type->variant) {
				return nullptr;
			}
			auto union_type = static_cast<TypeInfoUnion const*>(type);
			const size_t index = union_type->value_index();
			if (index >= union_type->variants.size()) {
				return nullptr;
			}
			const UnionVariant& some = union_type->variants[index];
			return some.types.empty() ? nullptr : some.types[0];
		}

		// ---------------------------------------------------------------------------------------------
		// Where values point

		// Where a value may point: nowhere on the stack, or into the stack with an origin.
		struct Reach {
			bool local = false;
			size_t origin = PARAMETER;
			int parameter = NO_PARAMETER;
			/*
			 * Whether what's loaded through it is local too: an any, a pointer to a #scoped struct, or a
			 * varargs parameter, and what's cast or taken from those.
			 */
			bool deep = false;

			bool operator==(const Reach&) const = default;
		};

		Reach in_frame() {
			return Reach{ true, FRAME, NO_PARAMETER, false };
		}

		// Two values combined: local if either is, with the shorter-lived origin.
		Reach join(const Reach& a, const Reach& b) {
			if (!a.local) {
				return b;
			}
			if (!b.local) {
				return a;
			}
			Reach result = a.origin >= b.origin ? a : b;
			result.deep = a.deep || b.deep;
			if (a.origin == b.origin && a.parameter != b.parameter) {
				result.parameter = SEVERAL_PARAMETERS;
			}
			return result;
		}

		// A value as a value of type: unrestricted if the type can't hold a pointer, always local if it's #scoped.
		Reach as_type(Reach reach, TypeInfo const* type) {
			if (type != nullptr && !carries_pointers(type)) {
				return Reach{};
			}
			if (is_scoped(type) && !reach.local) {
				reach = Reach{ true, PARAMETER, SEVERAL_PARAMETERS, false };
			}
			if (!reach.local) {
				reach.deep = false;
			}
			else if (is_deep_kind(type)) {
				reach.deep = true;
			}
			return reach;
		}

		/*
		 * A location: part of a variable, a global, something a pointer points to, or a temporary in
		 * the frame. What's loaded from it is content; a pointer to it is address.
		 */
		struct Place {
			bool exists = false;
			const void* variable = nullptr;
			bool global = false;
			bool through = false;
			// Through a pointer to a #scoped struct, or part of one, which may hold local values
			bool scoped = false;
			// A part of a variable, rather than all of it
			bool part = false;
			// Part of an #unrestricted struct, which can't hold a local value
			bool unrestricted = false;
			Reach address;
			Reach content;
		};

		// What an expression is: a value, a location, several results, or not a value (a type, a package).
		struct Evaluated {
			ValueKind kind = ValueKind::NOTHING;
			TypeInfo* type = nullptr;
			size_t variant = 0;
			InternedString name = nullptr;
			Place place;
			Reach value;
			std::vector<std::pair<Reach, TypeInfo*>> results;
		};

		Evaluated value_of_type(Reach reach, TypeInfo* type) {
			Evaluated result;
			result.kind = ValueKind::VALUE;
			result.type = type;
			result.value = as_type(reach, type);
			return result;
		}

		Evaluated at(const Place& place, TypeInfo* type) {
			Evaluated result;
			result.kind = ValueKind::VALUE;
			result.type = type;
			result.place = place;
			return result;
		}

		Place temporary(Reach content) {
			Place place;
			place.exists = true;
			place.address = in_frame();
			place.content = content;
			return place;
		}

		// What a pointer points to: what's loaded through it is local only if the pointer is deep.
		Place through(Reach pointer, TypeInfo const* target) {
			Place place;
			place.exists = true;
			place.through = true;
			place.scoped = is_scoped(target);
			place.address = pointer;
			if (pointer.local && pointer.deep) {
				place.content = Reach{ true, pointer.origin, pointer.parameter, false };
			}
			return place;
		}

		// A local: how deep its block is, and everything it's ever held. A named result is one too,
		// which a return then checks.
		struct Variable {
			size_t depth = FRAME;
			Reach holds;
		};

		// Which parameters each function gives back pointers from, by its declaration.
		using ReturnSources = std::unordered_map<const Declaration*, std::vector<bool>>;

		struct Analysis {
			const CheckedBody& checked;
			TypeInfoFunction const* function;
			const std::string& file_path;
			const ReturnSources& sources;
			// Which of its own parameters it gives back pointers from, found as it's walked
			std::vector<bool> returns_from;
			// The compute blocks being walked, innermost last: what's given each, and its type
			std::vector<std::pair<Reach, TypeInfo*>> computes;
			std::unordered_map<const void*, Variable> variables;
			// A match arm's values, which are where they are in what's matched
			std::unordered_map<const void*, Place> aliases;
			// What a pipe passes to the last call after it
			std::vector<Evaluated> piped;
			bool reporting = false;
			bool changed = false;
			size_t errors = 0;
			std::unordered_set<const ast::Node*> reported;
		};

		void report(Analysis& analysis, const ast::Node* where, const std::string& details) {
			if (!analysis.reporting || !analysis.reported.insert(where).second) {
				return;
			}
			report_at(ErrorCode::E4030, analysis.file_path, analysis.checked.made, where, details);
			++analysis.errors;
		}

		const CheckedNode* found_at(const Analysis& analysis, const ast::Node* node) {
			auto iter = analysis.checked.nodes.find(node);
			return iter == analysis.checked.nodes.end() ? nullptr : &iter->second;
		}

		const CheckedNode* head_of(const Analysis& analysis, const ast::Node* node) {
			auto iter = analysis.checked.heads.find(node);
			return iter == analysis.checked.heads.end() ? nullptr : &iter->second;
		}

		TypeInfo* type_at(const Analysis& analysis, const ast::Node* node, TypeInfo* expected) {
			const CheckedNode* found = found_at(analysis, node);
			if (found == nullptr || is_untyped(found->kind)) {
				return expected;
			}
			return found->type;
		}

		Variable& variable(Analysis& analysis, const void* key) {
			auto iter = analysis.variables.find(key);
			if (iter != analysis.variables.end()) {
				return iter->second;
			}
			Variable& created = analysis.variables[key];
			auto depth = analysis.checked.local_depths.find(key);
			created.depth = depth != analysis.checked.local_depths.end() ? std::max(depth->second, FRAME) : FRAME;
			return created;
		}

		Place variable_place(Analysis& analysis, const void* key) {
			Variable& found = variable(analysis, key);
			Place place;
			place.exists = true;
			place.variable = key;
			place.address = Reach{ true, std::max(found.depth, FRAME), NO_PARAMETER, false };
			place.content = found.holds;
			return place;
		}

		Reach value_of(const Evaluated& evaluated) {
			if (evaluated.place.exists) {
				Reach content = evaluated.place.content;
				// A variable's whole value keeps what made it deep; a part of it is deep by its own type
				if (evaluated.place.variable == nullptr || evaluated.place.part) {
					content.deep = false;
				}
				return as_type(content, evaluated.type);
			}
			return as_type(evaluated.value, evaluated.type);
		}

		/*
		 * A pointer, or a view, to a place: an error if the place holds a local value, unless it's a
		 * #scoped struct, whose pointers are deep.
		 */
		Reach address_of(Analysis& analysis, const Place& place, TypeInfo const* target, const ast::Node* where, bool view) {
			if (!place.exists) {
				return in_frame();
			}
			const bool scoped = is_scoped(target);
			const bool holds_local = as_type(place.content, target).local;
			// A view of what a deep view, like a varargs parameter, points to is deep too
			const bool deep_view = view && place.through && place.address.deep;
			if (holds_local && !scoped && !deep_view) {
				report(analysis, where, view
					? "a view of an array holding pointers into the stack: only an any or a pointer to a #scoped struct can point to those"
					: "a pointer to something holding a pointer into the stack: make its type #scoped (docs/memory.md, Deep Pointers)");
			}
			Reach result = place.address;
			result.deep = (scoped || deep_view) && result.local;
			return result;
		}

		// A value converted to type, as the generator converts it where it's used.
		Reach convert(Analysis& analysis, const Evaluated& evaluated, TypeInfo* type, const ast::Node* where) {
			if (type == nullptr || evaluated.type == nullptr || ValueKind::TYPE == evaluated.kind) {
				return value_of(evaluated);
			}
			// Into an any: a pointer to a copy of it in the frame, deep since the copy may hold local values
			if (is_variant(type, TypeInfoVariant::ANY) && !is_variant(evaluated.type, TypeInfoVariant::ANY)) {
				Reach result = join(in_frame(), value_of(evaluated));
				result.deep = true;
				return result;
			}
			if (is_array(evaluated.type, ArrayType::STATIC) && is_array(type, ArrayType::VIEW)) {
				if (!evaluated.place.exists) {
					return in_frame();
				}
				return as_type(address_of(analysis, evaluated.place, element_of(evaluated.type), where, true), type);
			}
			return as_type(value_of(evaluated), type);
		}

		// Storing a value at a place: what may hold a local value, and for how long.
		void store(Analysis& analysis, const Place& place, const Reach& value, const ast::Node* where) {
			if (!place.exists) {
				return;
			}
			if (place.unrestricted && value.local) {
				report(analysis, where, "an #unrestricted struct can't hold a pointer into the stack (docs/memory.md, Unrestricted Structs)");
				return;
			}
			if (place.variable != nullptr) {
				Variable& target = variable(analysis, place.variable);
				const Reach joined = join(target.holds, value);
				if (!(joined == target.holds)) {
					target.holds = joined;
					analysis.changed = true;
				}
				if (value.local && value.origin > target.depth) {
					report(analysis, where, "stores a pointer into a block's stack in a variable that outlives the block");
				}
				return;
			}
			if (!value.local) {
				return;
			}
			if (place.global) {
				report(analysis, where, "stores a pointer into the stack in a global");
				return;
			}
			if (!place.through) {
				return;
			}
			/*
			 * Through a pointer to a #scoped struct: what lives as long as it, which is what came through
			 * the same parameter, or what's from a block at least as old as the struct's
			 */
			const Reach& pointer = place.address;
			if (place.scoped && pointer.local) {
				const bool fits = PARAMETER == pointer.origin
					? PARAMETER == value.origin && pointer.parameter >= 0 && value.parameter == pointer.parameter
					: value.origin <= pointer.origin;
				if (fits) {
					return;
				}
				report(analysis, where, "stores a pointer into the stack through a pointer to a #scoped struct, which may outlive it");
				return;
			}
			report(analysis, where, "stores a pointer into the stack through a pointer: only a #scoped struct can hold one there");
		}

		// What a parameter points to, given back, or maybe: that one, or any, for several or one unknown.
		void gives_back(Analysis& analysis, const Reach& value) {
			if (!value.local || PARAMETER != value.origin) {
				return;
			}
			if (value.parameter >= 0 && static_cast<size_t>(value.parameter) < analysis.returns_from.size()) {
				analysis.returns_from[static_cast<size_t>(value.parameter)] = true;
			}
			else {
				std::fill(analysis.returns_from.begin(), analysis.returns_from.end(), true);
			}
		}

		void check_returned(Analysis& analysis, const Reach& value, const ast::Node* where, const FunctionOutput* output = nullptr) {
			// An #unrestricted result can't be anything the function was given, either
			if (output != nullptr && output->is_unrestricted && value.local) {
				report(analysis, where, output->name != nullptr
					? std::format("returns what may point into the stack as #unrestricted result `{}`", text_of(output->name))
					: std::string("returns what may point into the stack as an #unrestricted result"));
				return;
			}
			if (value.local && PARAMETER != value.origin) {
				report(analysis, where, "returns a pointer into this function's stack");
			}
			gives_back(analysis, value);
		}

		// ---------------------------------------------------------------------------------------------
		// Expressions

		Evaluated evaluate(Analysis& analysis, ast::Node* node, TypeInfo* expected);
		void walk_statement(Analysis& analysis, ast::Node* statement);
		Reach walk_block(Analysis& analysis, ast::Node* block, TypeInfo* result_type, bool as_value);

		Evaluated evaluate_name(Analysis& analysis, ast::Node* node, const CheckedNode* found) {
			Evaluated result;
			if (found == nullptr || ValueKind::POISONED == found->kind) {
				return result;
			}
			result.kind = found->kind;
			result.type = found->type;
			result.variant = found->variant;
			result.name = node->value.value;
			if (ValueKind::TYPE == found->kind || ValueKind::PACKAGE == found->kind || ValueKind::BUILTIN_FUNCTION == found->kind
				|| ValueKind::GENERIC_FUNCTION == found->kind) {
				return result;
			}
			if (found->local != nullptr) {
				auto alias = analysis.aliases.find(found->local);
				if (alias != analysis.aliases.end()) {
					result.place = alias->second;
				}
				else if (!is_untyped(found->kind)) {
					result.place = variable_place(analysis, found->local);
				}
				return result;
			}
			Declaration* declaration = found->declaration;
			if (declaration == nullptr && ValueKind::VALUE == found->kind && is_text(node->value.value, "context")) {
				// Everything reachable from a context is unrestricted (docs/memory.md, Contexts)
				result.place = through(Reach{}, found->type);
				return result;
			}
			if (declaration != nullptr && DeclarationKind::VALUE == declaration->kind && ValueKind::VALUE == found->kind) {
				result.place.exists = true;
				result.place.global = true;
			}
			return result;
		}

		bool is_postfix_marker(const ast::Node* node) {
			return ast::NodeType::DOT_ACCESS == node->node_type
				|| ast::NodeType::PAREN_GROUP == node->node_type
				|| ast::NodeType::ARRAY_DIMENSION == node->node_type
				|| (ast::NodeType::UNARY_OPERATOR == node->node_type && TokenType::OPERATOR_DEREFERENCE == node->value.type);
		}

		bool is_placeholder(const ast::Node* node) {
			return ast::NodeType::UNDERSCORE == node->node_type || ast::NodeType::PIPE_REORDER_IDENTIFIER == node->node_type;
		}

		Evaluated evaluate_member(const Evaluated& current_, ast::Node* name_node, const CheckedNode* found) {
			Evaluated current = current_;
			TypeInfo const* type = base(current.type);
			TypeInfo* result_type = found->type;
			if (type == nullptr) {
				return value_of_type(Reach{}, result_type);
			}
			if (TypeInfoVariant::POINTER == type->variant) {
				TypeInfo* target = static_cast<TypeInfoPointer const*>(type)->base_type;
				current = at(through(value_of(current), target), target);
				type = base(target);
				if (type == nullptr) {
					return value_of_type(Reach{}, result_type);
				}
			}
			if (TypeInfoVariant::STRUCT == type->variant) {
				const bool unrestricted = static_cast<TypeInfoStruct const*>(type)->is_unrestricted;
				if (current.place.exists) {
					Place part = current.place;
					part.part = true;
					part.unrestricted = part.unrestricted || unrestricted;
					return at(part, result_type);
				}
				Reach whole = value_of(current);
				whole.deep = whole.deep && is_deep_kind(result_type);
				return value_of_type(whole, result_type);
			}
			if (TypeInfoVariant::ARRAY == type->variant && ArrayType::STATIC == static_cast<TypeInfoArray const*>(type)->array_type) {
				return value_of_type(Reach{}, result_type);
			}
			// An any's data, or an array's or string's: where the whole points, deep if it's deep
			Reach whole = value_of(current);
			if (!is_text(name_node->value.value, "data")) {
				return value_of_type(Reach{}, result_type);
			}
			Evaluated result = value_of_type(whole, result_type);
			result.value.deep = whole.local && whole.deep;
			return result;
		}

		Evaluated evaluate_index(Analysis& analysis, const Evaluated& current_, ast::Node* index, const CheckedNode* found) {
			Evaluated current = current_;
			TypeInfo const* type = base(current.type);
			if (type != nullptr && TypeInfoVariant::POINTER == type->variant) {
				TypeInfo* target = static_cast<TypeInfoPointer const*>(type)->base_type;
				current = at(through(value_of(current), target), target);
				type = base(target);
			}
			const TokenType op = index->value.type;
			const bool range = ast::NodeType::BINARY_OPERATOR == index->node_type
				&& (TokenType::OPERATOR_RANGE_EXCLUSIVE == op || TokenType::OPERATOR_RANGE_INCLUSIVE == op);
			if (range) {
				for (ast::Node* bound : index->children) {
					if (ast::NodeType::RANGE_ARRAY != bound->node_type) {
						evaluate(analysis, bound, BUILTIN_usize);
					}
				}
			}
			else if (ast::NodeType::RANGE_ARRAY != index->node_type) {
				evaluate(analysis, index, BUILTIN_usize);
			}
			TypeInfo* element = element_of(type);
			Place elements;
			if (type != nullptr && TypeInfoVariant::ARRAY == type->variant
				&& ArrayType::STATIC == static_cast<TypeInfoArray const*>(type)->array_type) {
				elements = current.place.exists ? current.place : temporary(value_of(current));
				elements.part = true;
			}
			else {
				elements = through(value_of(current), element);
			}
			if (range || ast::NodeType::RANGE_ARRAY == index->node_type) {
				return value_of_type(address_of(analysis, elements, element, index, true), found->type);
			}
			return at(elements, element);
		}

		// The value an argument gives: one a pipe passed, or its expression's.
		struct Argument {
			ast::Node* node = nullptr;
			bool given = false;
			Evaluated value;
		};

		Evaluated evaluate_argument(Analysis& analysis, const Argument& argument, TypeInfo* type) {
			return argument.given ? argument.value : evaluate(analysis, argument.node, type);
		}

		Evaluated evaluate_call(Analysis& analysis, ast::Node* paren, const std::vector<ast::Node*>& argument_nodes,
			const Evaluated& callee, const CheckedNode* found, const std::vector<Evaluated>& piped) {

			if (ValueKind::BUILTIN_FUNCTION == callee.kind) {
				// size_of, type_info_of and the like: nothing that points anywhere
				for (ast::Node* argument : argument_nodes) {
					evaluate(analysis, argument, nullptr);
				}
				return value_of_type(Reach{}, type_at(analysis, paren, nullptr));
			}
			if (ValueKind::VARIANT == callee.kind) {
				auto union_type = static_cast<TypeInfoUnion const*>(base(callee.type));
				const UnionVariant& variant = union_type->variants[callee.variant];
				Reach reach;
				for (size_t i = 0; i < argument_nodes.size() && i < variant.types.size(); ++i) {
					reach = join(reach, convert(analysis, evaluate(analysis, argument_nodes[i], variant.types[i]), variant.types[i],
						argument_nodes[i]));
				}
				return value_of_type(reach, callee.type);
			}
			TypeInfoFunction const* function = found->called;
			if (function == nullptr) {
				for (ast::Node* argument : argument_nodes) {
					evaluate(analysis, argument, nullptr);
				}
				return Evaluated{};
			}
			std::vector<Argument> positional;
			std::vector<std::pair<InternedString, ast::Node*>> named;
			const bool placeholders = std::any_of(argument_nodes.begin(), argument_nodes.end(), is_placeholder);
			if (!placeholders) {
				for (const Evaluated& each : piped) {
					positional.push_back({ nullptr, true, each });
				}
			}
			size_t next_piped = 0;
			for (ast::Node* argument : argument_nodes) {
				if (ast::NodeType::UNDERSCORE == argument->node_type && next_piped < piped.size()) {
					positional.push_back({ argument, true, piped[next_piped++] });
				}
				else if (ast::NodeType::PIPE_REORDER_IDENTIFIER == argument->node_type) {
					const size_t number = std::stoul(text_of(argument->value.value).substr(1));
					if (number >= 1 && number <= piped.size()) {
						positional.push_back({ argument, true, piped[number - 1] });
					}
				}
				else if (ast::NodeType::BINARY_OPERATOR == argument->node_type && is_assign(argument)
					&& argument->children.size() == 2 && ast::NodeType::IDENTIFIER == argument->children[0]->node_type) {
					named.emplace_back(argument->children[0]->value.value, argument->children[1]);
				}
				else {
					positional.push_back({ argument, false, {} });
				}
			}
			/*
			 * What the call gives is local if something it was given to keep only for the call was, and the callee
			 * gives back pointers from that parameter, as its body says; any, if what it is isn't known
			 */
			const std::vector<bool>* gives_back = nullptr;
			if (found != nullptr && found->called_declaration != nullptr) {
				auto known = analysis.sources.find(found->called_declaration);
				if (known != analysis.sources.end()) {
					gives_back = &known->second;
				}
			}
			Reach result;
			size_t passing = 0;
			auto pass = [&](const Reach& reach, const FunctionInput& input, const ast::Node* where) {
				if (input.is_escaping && reach.local) {
					report(analysis, where, std::format("passes a pointer into the stack to #escaping parameter `{}`: copy it to the heap first",
						text_of(input.name)));
					return;
				}
				if (gives_back == nullptr || (passing < gives_back->size() && (*gives_back)[passing])) {
					result = join(result, reach);
				}
			};
			// Which parameter each positional argument went to, where the checker split them around a variadic one
			auto found_split = analysis.checked.argument_parameters.find(paren);
			const std::vector<uint32_t>* split = found_split != analysis.checked.argument_parameters.end() ? &found_split->second : nullptr;
			size_t next = 0;
			size_t parameter = 0;
			for (const FunctionInput& input : function->input) {
				const size_t this_parameter = parameter++;
				passing = this_parameter;
				const auto mine = [&](size_t argument) {
					return split == nullptr || (argument < split->size() && (*split)[argument] == this_parameter);
				};
				if (input.is_varargs) {
					// A view of them passed on, or the rest in a stack array whose view is passed
					if (next < positional.size() && mine(next)) {
						const Argument& first = positional[next];
						TypeInfo* first_type = first.given ? first.value.type : type_at(analysis, first.node, nullptr);
						if (is_array(first_type, ArrayType::VIEW) && base(element_of(first_type)) == base(input.type)) {
							Evaluated passed = evaluate_argument(analysis, first, nullptr);
							pass(value_of(passed), input, first.node != nullptr ? first.node : paren);
							++next;
							continue;
						}
					}
					Reach values;
					bool any = false;
					for (; next < positional.size() && mine(next); ++next) {
						const Argument& each = positional[next];
						values = join(values, convert(analysis, evaluate_argument(analysis, each, input.type), input.type,
							each.node != nullptr ? each.node : paren));
						any = true;
					}
					if (any) {
						// The array is in this frame, and its elements may be local: the callee's view is deep
						values = join(values, in_frame());
						values.deep = true;
					}
					pass(values, input, paren);
					continue;
				}
				if (next < positional.size() && mine(next)) {
					const Argument& each = positional[next++];
					pass(convert(analysis, evaluate_argument(analysis, each, input.type), input.type, each.node != nullptr ? each.node : paren),
						input, each.node != nullptr ? each.node : paren);
					continue;
				}
				for (const auto& [name, node] : named) {
					if (input.name != nullptr && *name == *input.name) {
						pass(convert(analysis, evaluate(analysis, node, input.type), input.type, node), input, node);
					}
				}
			}
			if (function->output.empty()) {
				return Evaluated{};
			}
			// An #unrestricted result is never local, whatever the call was given
			if (function->output.size() == 1) {
				return value_of_type(function->output[0].is_unrestricted ? Reach{} : result, function->output[0].type);
			}
			Evaluated several;
			several.kind = ValueKind::RESULTS;
			for (const FunctionOutput& output : function->output) {
				several.results.emplace_back(output.is_unrestricted ? Reach{} : as_type(result, output.type), output.type);
			}
			return several;
		}

		// What follows a value, from start: .member, (arguments), [index] or [type arguments], and ^.
		Evaluated evaluate_steps(Analysis& analysis, ast::Node* node, size_t start, Evaluated current) {
			for (size_t i = start; i < node->children.size(); ++i) {
				ast::Node* child = node->children[i];
				std::vector<ast::Node*> arguments;
				while (i + 1 < node->children.size() && !is_postfix_marker(node->children[i + 1])) {
					arguments.push_back(node->children[++i]);
				}
				const ast::NodeType type = child->node_type;
				if (ast::NodeType::PAREN_GROUP == type && arguments.empty() && !child->children.empty()) {
					arguments.assign(child->children.begin(), child->children.end());
				}
				ast::Node* where = ast::NodeType::DOT_ACCESS == type && !arguments.empty() ? arguments[0] : child;
				const CheckedNode* found = found_at(analysis, where);
				if (found == nullptr || ValueKind::POISONED == found->kind) {
					return Evaluated{};
				}
				if (ast::NodeType::DOT_ACCESS == type) {
					if (ValueKind::PACKAGE == current.kind) {
						current = evaluate_name(analysis, arguments[0], found);
					}
					else if (ValueKind::TYPE == current.kind) {
						// A variant, or an enum's member
						current = value_of_type(Reach{}, found->type);
					}
					else {
						current = evaluate_member(current, arguments[0], found);
					}
				}
				else if (ast::NodeType::PAREN_GROUP == type) {
					bool last_call = true;
					for (size_t j = i + 1; j < node->children.size(); ++j) {
						if (ast::NodeType::PAREN_GROUP == node->children[j]->node_type) {
							last_call = false;
						}
					}
					std::vector<Evaluated> piped;
					if (last_call) {
						piped = std::move(analysis.piped);
						analysis.piped.clear();
					}
					current = evaluate_call(analysis, child, arguments, current, found, piped);
				}
				else if (ast::NodeType::ARRAY_DIMENSION == type) {
					if (ValueKind::GENERIC_FUNCTION != current.kind && !arguments.empty()) {
						current = evaluate_index(analysis, current, arguments[0], found);
					}
				}
				else {
					TypeInfo* target = pointee(current.type);
					current = at(through(value_of(current), target), found->type);
				}
				if (ValueKind::RESULTS != current.kind && ValueKind::NOTHING != current.kind) {
					current.kind = found->kind;
					current.variant = found->variant;
					if (found->type != nullptr) {
						current.type = found->type;
					}
				}
			}
			return current;
		}

		Evaluated evaluate_postfix(Analysis& analysis, ast::Node* node) {
			const CheckedNode* whole = found_at(analysis, node);
			if (whole != nullptr && ValueKind::TYPE == whole->kind) {
				Evaluated result;
				result.kind = ValueKind::TYPE;
				result.type = whole->type;
				return result;
			}
			const CheckedNode* head = head_of(analysis, node);
			if (node->children.empty() || head == nullptr) {
				return evaluate_name(analysis, node, head != nullptr ? head : whole);
			}
			Evaluated current = evaluate_name(analysis, head->next > 0 ? node->children[head->next - 1] : node, head);
			return evaluate_steps(analysis, node, head->next, current);
		}

		// What an optional or result holds, where it is.
		Evaluated held(const Evaluated& whole, TypeInfo* type) {
			Evaluated result = whole;
			result.place.part = true;
			result.kind = ValueKind::VALUE;
			result.type = type;
			return result;
		}

		Evaluated evaluate_unary(Analysis& analysis, ast::Node* node, TypeInfo* expected) {
			const TokenType op = node->value.type;
			ast::Node* operand_node = node->children[0];
			const CheckedNode* found = found_at(analysis, node);
			TypeInfo* result_type = type_at(analysis, node, expected);
			if (found != nullptr && ValueKind::TYPE == found->kind) {
				Evaluated type;
				type.kind = ValueKind::TYPE;
				type.type = found->type;
				return type;
			}
			if (TokenType::SYM_QUESTION == op || TokenType::KEYWORD_IS_SOME == op || TokenType::KEYWORD_IS_NONE == op
				|| TokenType::KEYWORD_IS_OK == op || TokenType::KEYWORD_IS_ERROR == op
				|| TokenType::KEYWORD_OR_BREAK == op || TokenType::KEYWORD_OR_CONTINUE == op) {
				Evaluated operand = evaluate(analysis, operand_node, nullptr);
				if (TokenType::KEYWORD_IS_SOME == op || TokenType::KEYWORD_IS_NONE == op || TokenType::KEYWORD_IS_OK == op
					|| TokenType::KEYWORD_IS_ERROR == op) {
					return value_of_type(Reach{}, BUILTIN_bool);
				}
				return held(operand, result_type);
			}
			if (TokenType::SYM_AMPERSAND == op) {
				Evaluated operand = evaluate(analysis, operand_node, nullptr);
				Reach pointer = address_of(analysis, operand.place, operand.type, node, false);
				return value_of_type(pointer, result_type);
			}
			if (TokenType::OPERATOR_DEREFERENCE == op) {
				Evaluated operand = evaluate(analysis, operand_node, nullptr);
				return at(through(value_of(operand), result_type), result_type);
			}
			evaluate(analysis, operand_node, result_type);
			return value_of_type(Reach{}, result_type);
		}

		bool is_comparison(TokenType op) {
			return TokenType::OPERATOR_EQUAL == op || TokenType::OPERATOR_NOT_EQUAL == op
				|| TokenType::SYM_LT == op || TokenType::SYM_GT == op
				|| TokenType::OPERATOR_LESS_THAN_OR_EQUAL == op || TokenType::OPERATOR_GREATER_THAN_OR_EQUAL == op;
		}

		Evaluated evaluate_binary(Analysis& analysis, ast::Node* node, TypeInfo* expected) {
			const TokenType op = node->value.type;
			ast::Node* left_node = node->children[0];
			ast::Node* right_node = node->children.size() > 1 ? node->children[1] : nullptr;
			TypeInfo* result_type = type_at(analysis, node, expected);
			if (TokenType::OPERATOR_PIPE == op) {
				Evaluated left = evaluate(analysis, left_node, nullptr);
				std::vector<Evaluated> piped;
				if (ValueKind::RESULTS == left.kind) {
					for (const auto& [reach, type] : left.results) {
						piped.push_back(value_of_type(reach, type));
					}
				}
				else if (ValueKind::NOTHING != left.kind) {
					piped.push_back(left);
				}
				analysis.piped = std::move(piped);
				Evaluated right = evaluate_postfix(analysis, right_node);
				Evaluated result = evaluate_steps(analysis, node, 2, right);
				analysis.piped.clear();
				return result;
			}
			if (TokenType::KEYWORD_OR_ELSE == op || TokenType::KEYWORD_OR_RETURN == op) {
				Evaluated left = evaluate(analysis, left_node, nullptr);
				TypeInfo* held_as = held_type(left.type);
				if (TokenType::KEYWORD_OR_RETURN == op) {
					if (analysis.function->output.empty()) {
						evaluate(analysis, right_node, nullptr);
					}
					else {
						TypeInfo* returned = analysis.function->output[0].type;
						check_returned(analysis, convert(analysis, evaluate(analysis, right_node, returned), returned, right_node), right_node,
							&analysis.function->output[0]);
					}
					return held(left, held_as);
				}
				if (held_as == nullptr) {
					evaluate(analysis, right_node, nullptr);
					return Evaluated{};
				}
				Reach otherwise = convert(analysis, evaluate(analysis, right_node, held_as), held_as, right_node);
				return value_of_type(join(value_of(held(left, held_as)), otherwise), held_as);
			}
			if (TokenType::OPERATOR_AND == op || TokenType::OPERATOR_OR == op || is_comparison(op)) {
				evaluate(analysis, left_node, nullptr);
				evaluate(analysis, right_node, nullptr);
				return value_of_type(Reach{}, BUILTIN_bool);
			}
			Evaluated left = evaluate(analysis, left_node, result_type);
			Evaluated right = evaluate(analysis, right_node, result_type);
			// Pointer arithmetic keeps where the pointer points
			if (is_variant(result_type, TypeInfoVariant::POINTER)) {
				return value_of_type(value_of(left), result_type);
			}
			return value_of_type(join(value_of(left), value_of(right)), result_type);
		}

		// cast[T](x), bit_cast[T](x), auto_cast(x): the same pointer, still deep if it was, or an integer.
		Evaluated evaluate_cast(Analysis& analysis, ast::Node* node) {
			// auto_cast(x), and (x) before a chain, have no type before the value
			const bool automatic = TokenType::KEYWORD_AUTO_CAST == node->value.type || TokenType::SYM_LPAREN == node->value.type;
			if (node->children.size() < (automatic ? 1u : 2u)) {
				return Evaluated{};
			}
			ast::Node* value_node = node->children[automatic ? 0 : 1];
			const CheckedNode* head = head_of(analysis, node);
			TypeInfo* target = head != nullptr ? head->type : nullptr;
			if (target == nullptr) {
				return Evaluated{};
			}
			Reach source = value_of(evaluate(analysis, value_node, target));
			Evaluated result = value_of_type(source, target);
			if (result.value.local) {
				result.value.deep = result.value.deep || source.deep;
			}
			/*
			 * A pointer from a parameter made an integer, like string_of's cast[usize](data), isn't followed any
			 * further: what it came from may be given back, made a pointer again
			 */
			else if (source.local) {
				gives_back(analysis, source);
			}
			return evaluate_steps(analysis, node, automatic ? 1 : 2, result);
		}

		Evaluated evaluate_struct_literal(Analysis& analysis, ast::Node* node, TypeInfo* type) {
			TypeInfo const* structure = base(type);
			Reach reach;
			if (structure == nullptr || TypeInfoVariant::STRUCT != structure->variant) {
				return value_of_type(reach, type);
			}
			auto members = static_cast<TypeInfoStruct const*>(structure);
			size_t position = 0;
			for (ast::Node* child : node->children) {
				if (ast::NodeType::LIST != child->node_type) {
					continue;
				}
				for (ast::Node* element : child->children) {
					const bool named = ast::NodeType::BINARY_OPERATOR == element->node_type && is_assign(element)
						&& element->children.size() == 2;
					TypeInfo* member = named ? member_type(members, element->children[0]->value.value)
						: position < members->members.size() ? members->members[position].member_type : nullptr;
					if (!named) {
						++position;
					}
					ast::Node* value_node = named ? element->children[1] : element;
					const Reach given = convert(analysis, evaluate(analysis, value_node, member), member, value_node);
					if (members->is_unrestricted && given.local) {
						report(analysis, value_node, "an #unrestricted struct can't hold a pointer into the stack (docs/memory.md, Unrestricted Structs)");
					}
					reach = join(reach, given);
				}
			}
			return value_of_type(reach, type);
		}

		Evaluated evaluate_array_literal(Analysis& analysis, ast::Node* node, TypeInfo* type) {
			TypeInfo* element = element_of(type);
			Reach reach;
			for (ast::Node* child : node->children) {
				if (ast::NodeType::LIST != child->node_type) {
					continue;
				}
				for (ast::Node* each : child->children) {
					reach = join(reach, convert(analysis, evaluate(analysis, each, element), element, each));
				}
			}
			return value_of_type(reach, type);
		}

		ast::Node* else_of(ast::Node* if_node) {
			ast::Node* otherwise = if_node->children.size() > 2 ? if_node->children[2] : nullptr;
			if (otherwise != nullptr && ast::NodeType::ELSE == otherwise->node_type && !otherwise->children.empty()) {
				otherwise = otherwise->children[0];
			}
			return otherwise;
		}

		// An if, as a value or a statement: each branch's value, combined.
		Reach walk_if(Analysis& analysis, ast::Node* node, TypeInfo* type, bool as_value) {
			evaluate(analysis, node->children[0], BUILTIN_bool);
			Reach result = walk_block(analysis, node->children[1], type, as_value);
			ast::Node* otherwise = else_of(node);
			if (otherwise == nullptr) {
				return result;
			}
			if (ast::NodeType::IF == otherwise->node_type) {
				return join(result, walk_if(analysis, otherwise, type, as_value));
			}
			return join(result, walk_block(analysis, otherwise, type, as_value));
		}

		// The entries of a match's or switch's lists: its arms or cases.
		std::vector<ast::Node*> entries_of(ast::Node* node, bool cases) {
			std::vector<ast::Node*> result;
			for (ast::Node* list : node->children) {
				if (ast::NodeType::LIST != list->node_type) {
					continue;
				}
				for (ast::Node* entry : list->children) {
					if (!entry->children.empty() && (!cases || ast::NodeType::SWITCH_CASE == entry->node_type)) {
						result.push_back(entry);
					}
				}
			}
			return result;
		}

		// One of an arm's or case's values: a variant's values are where they are in what's matched.
		void walk_pattern(Analysis& analysis, ast::Node* pattern, const Place& subject, TypeInfo* subject_type) {
			if (is_wildcard(pattern)) {
				return;
			}
			TypeInfo const* type = base(subject_type);
			if (type != nullptr && TypeInfoVariant::UNION == type->variant
				&& (ast::NodeType::IDENTIFIER == pattern->node_type || ast::NodeType::ENUM_SHORTHAND == pattern->node_type)) {
				for (ast::Node* child : pattern->children) {
					if (ast::NodeType::PAREN_GROUP != child->node_type) {
						continue;
					}
					const UnionVariant* variant = nullptr;
					for (const UnionVariant& each : static_cast<TypeInfoUnion const*>(type)->variants) {
						if (each.name != nullptr && pattern->value.value != nullptr && *each.name == *pattern->value.value) {
							variant = &each;
						}
					}
					for (size_t i = 0; i < child->children.size(); ++i) {
						ast::Node* binding = child->children[i];
						if (is_wildcard(binding)) {
							continue;
						}
						Place part = subject;
						part.part = true;
						if (ast::NodeType::IDENTIFIER == binding->node_type && binding->children.empty()) {
							analysis.aliases[binding] = part;
						}
						// A pattern inside, like Some(x) in Ok(Some(x)): its names are parts of the same place
						else if (variant != nullptr && i < variant->types.size()) {
							walk_pattern(analysis, binding, part, variant->types[i]);
						}
					}
				}
				return;
			}
			if (ast::NodeType::BINARY_OPERATOR == pattern->node_type) {
				for (ast::Node* bound : pattern->children) {
					evaluate(analysis, bound, subject_type);
				}
				return;
			}
			evaluate(analysis, pattern, subject_type);
		}

		Reach walk_match(Analysis& analysis, ast::Node* node, TypeInfo* type, bool as_value, bool cases) {
			Evaluated subject = evaluate(analysis, node->children[0], nullptr);
			const Place place = subject.place.exists ? subject.place : temporary(value_of(subject));
			Reach result;
			for (ast::Node* entry : entries_of(node, cases)) {
				for (size_t i = 0; i + 1 < entry->children.size(); ++i) {
					walk_pattern(analysis, entry->children[i], place, subject.type);
				}
				ast::Node* outcome = entry->children.back();
				const ast::NodeType outcome_type = outcome->node_type;
				if (ast::NodeType::BLOCK == outcome_type) {
					result = join(result, walk_block(analysis, outcome, type, as_value));
				}
				else if (ast::NodeType::RETURN == outcome_type || ast::NodeType::GIVE == outcome_type || ast::NodeType::BREAK == outcome_type
					|| ast::NodeType::CONTINUE == outcome_type || is_assignment(outcome) || !as_value) {
					walk_statement(analysis, outcome);
				}
				else {
					result = join(result, convert(analysis, evaluate(analysis, outcome, type), type, outcome));
				}
			}
			return result;
		}

		Evaluated evaluate(Analysis& analysis, ast::Node* node, TypeInfo* expected) {
			const ast::NodeType type = node->node_type;
			TypeInfo* result_type = type_at(analysis, node, expected);
			if (ast::NodeType::IDENTIFIER == type) {
				return evaluate_postfix(analysis, node);
			}
			if (ast::NodeType::PAREN_GROUP == type && node->children.size() == 1) {
				return evaluate(analysis, node->children[0], expected);
			}
			if (ast::NodeType::TYPE == type || ast::NodeType::FUNCTION == type) {
				Evaluated result;
				result.kind = ValueKind::TYPE;
				return result;
			}
			if (ast::NodeType::UNARY_OPERATOR == type) {
				return evaluate_unary(analysis, node, expected);
			}
			if (ast::NodeType::BINARY_OPERATOR == type) {
				return evaluate_binary(analysis, node, expected);
			}
			if (ast::NodeType::CAST == type) {
				return evaluate_cast(analysis, node);
			}
			if (ast::NodeType::STRUCT_LITERAL == type) {
				return evaluate_struct_literal(analysis, node, result_type);
			}
			if (ast::NodeType::ARRAY_LITERAL == type) {
				return evaluate_array_literal(analysis, node, result_type);
			}
			// A variant by its name alone, like .Ok(value): what it holds, as for a call to the variant
			if (ast::NodeType::ENUM_SHORTHAND == type) {
				Reach reach;
				TypeInfo* shorthand_type = result_type != nullptr ? result_type : expected;
				TypeInfo const* union_type = base(shorthand_type);
				const UnionVariant* variant = nullptr;
				if (is_variant(union_type, TypeInfoVariant::UNION)) {
					for (const UnionVariant& each : static_cast<TypeInfoUnion const*>(union_type)->variants) {
						if (each.name != nullptr && node->value.value != nullptr && *each.name == *node->value.value) {
							variant = &each;
						}
					}
				}
				// Its arguments: inside the parentheses' node, or the children after it, as for calls
				std::vector<ast::Node*> arguments;
				for (size_t i = 0; i < node->children.size(); ++i) {
					ast::Node* step = node->children[i];
					if (ast::NodeType::PAREN_GROUP != step->node_type) {
						continue;
					}
					if (!step->children.empty()) {
						arguments.assign(step->children.begin(), step->children.end());
					}
					while (i + 1 < node->children.size() && !is_postfix_marker(node->children[i + 1])) {
						arguments.push_back(node->children[++i]);
					}
					break;
				}
				for (size_t i = 0; i < arguments.size(); ++i) {
					TypeInfo* held = variant != nullptr && i < variant->types.size() ? variant->types[i] : nullptr;
					Evaluated argument = evaluate(analysis, arguments[i], held);
					if (held != nullptr) {
						reach = join(reach, convert(analysis, argument, held, arguments[i]));
					}
				}
				return value_of_type(reach, shorthand_type);
			}
			if (ast::NodeType::IF == type) {
				return value_of_type(walk_if(analysis, node, result_type, true), result_type);
			}
			// compute[T] { ... }: what every give in it gives
			if (ast::NodeType::COMPUTE == type && node->children.size() == 2) {
				analysis.computes.emplace_back(Reach{}, result_type);
				walk_block(analysis, node->children[1], nullptr, false);
				Reach given = analysis.computes.back().first;
				analysis.computes.pop_back();
				return value_of_type(given, result_type);
			}
			if (ast::NodeType::MATCH == type) {
				return value_of_type(walk_match(analysis, node, result_type, true, false), result_type);
			}
			// Literals, enum members, and what's worked out while compiling (#run, #caller_location, #file_data)
			return value_of_type(Reach{}, result_type);
		}

		// ---------------------------------------------------------------------------------------------
		// Statements

		// The values of a list, or of one expression, with a call's several results as several.
		std::vector<Evaluated> evaluate_values(Analysis& analysis, ast::Node* node, const std::vector<TypeInfo*>& expected) {
			std::vector<ast::Node*> nodes;
			if (ast::NodeType::LIST == node->node_type) {
				nodes.assign(node->children.begin(), node->children.end());
			}
			else {
				nodes.push_back(node);
			}
			std::vector<Evaluated> values;
			for (size_t i = 0; i < nodes.size(); ++i) {
				TypeInfo* hint = nodes.size() == 1 && expected.size() == 1 ? expected[0]
					: i < expected.size() && nodes.size() == expected.size() ? expected[i] : nullptr;
				Evaluated evaluated = evaluate(analysis, nodes[i], hint);
				if (ValueKind::RESULTS == evaluated.kind) {
					for (const auto& [reach, type] : evaluated.results) {
						values.push_back(value_of_type(reach, type));
					}
					continue;
				}
				values.push_back(evaluated);
			}
			return values;
		}

		void walk_assignment(Analysis& analysis, ast::Node* node) {
			ast::Node* left_node = node->children[0];
			ast::Node* right_node = node->children[1];
			std::vector<ast::Node*> targets;
			if (ast::NodeType::LIST == left_node->node_type) {
				targets.assign(left_node->children.begin(), left_node->children.end());
			}
			else {
				targets.push_back(left_node);
			}
			std::vector<TypeInfo*> types;
			for (ast::Node* target : targets) {
				types.push_back(is_wildcard(target) ? nullptr : type_at(analysis, target, nullptr));
			}
			std::vector<Evaluated> values;
			if (is_assignment(right_node)) {
				walk_assignment(analysis, right_node);
				values = evaluate_values(analysis, right_node->children[0], types);
			}
			else {
				values = evaluate_values(analysis, right_node, types);
			}
			for (size_t i = 0; i < targets.size() && !values.empty(); ++i) {
				if (is_wildcard(targets[i])) {
					continue;
				}
				const Evaluated& given = values.size() == 1 ? values[0] : values[std::min(i, values.size() - 1)];
				Evaluated target = evaluate(analysis, targets[i], nullptr);
				// a += b keeps what a points to: only plain assignment stores something new
				if (is_assign(node)) {
					const Reach stored = convert(analysis, given, types[i], node);
					// A relative pointer is only for memory that's shared or on disk (docs/types.md, Relative Pointers)
					const CheckedNode* place = found_at(analysis, targets[i]);
					if (place != nullptr && place->stored_type != nullptr && stored.local) {
						report(analysis, node, "a relative pointer can't point into the stack (docs/types.md, Relative Pointers)");
						continue;
					}
					store(analysis, target.place, stored, node);
				}
			}
		}

		void walk_definition(Analysis& analysis, ast::Node* definition) {
			std::vector<ast::Node*> names;
			ast::Node* names_node = definition->children[0];
			if (ast::NodeType::LIST == names_node->node_type) {
				names.assign(names_node->children.begin(), names_node->children.end());
			}
			else {
				names.push_back(names_node);
			}
			ast::Node* value_node = nullptr;
			for (size_t i = 1; i < definition->children.size(); ++i) {
				ast::Node* child = definition->children[i];
				if (ast::NodeType::COLON == child->node_type || (ast::NodeType::IDENTIFIER == child->node_type && is_assign(child))) {
					value_node = i + 1 < definition->children.size() ? definition->children[i + 1] : nullptr;
					break;
				}
			}
			if (value_node != nullptr && ast::NodeType::FUNCTION == value_node->node_type) {
				return;
			}
			std::vector<TypeInfo*> types;
			for (ast::Node* name : names) {
				const CheckedNode* found = found_at(analysis, name);
				types.push_back(found != nullptr && ValueKind::VALUE == found->kind ? found->type : nullptr);
			}
			if (value_node == nullptr || ast::NodeType::UNINITIALIZED == value_node->node_type) {
				return;
			}
			std::vector<Evaluated> values = evaluate_values(analysis, value_node, types);
			for (size_t i = 0; i < names.size() && !values.empty(); ++i) {
				if (is_wildcard(names[i]) || types[i] == nullptr) {
					continue;
				}
				const Evaluated& given = values.size() == 1 ? values[0] : values[std::min(i, values.size() - 1)];
				store(analysis, variable_place(analysis, names[i]), convert(analysis, given, types[i], definition), definition);
			}
		}

		void walk_return(Analysis& analysis, ast::Node* node) {
			if (node->children.empty() || (node->children.size() == 1 && ast::NodeType::VOID == node->children[0]->node_type)) {
				return;
			}
			std::vector<TypeInfo*> expected;
			for (const FunctionOutput& output : analysis.function->output) {
				expected.push_back(output.type);
			}
			std::vector<Evaluated> given;
			for (size_t i = 0; i < node->children.size(); ++i) {
				TypeInfo* hint = node->children.size() == expected.size() ? expected[i] : nullptr;
				std::vector<Evaluated> each = evaluate_values(analysis, node->children[i], { hint });
				given.insert(given.end(), each.begin(), each.end());
			}
			for (size_t i = 0; i < given.size() && i < expected.size(); ++i) {
				check_returned(analysis, convert(analysis, given[i], expected[i], node), node, &analysis.function->output[i]);
			}
		}

		void walk_for(Analysis& analysis, ast::Node* node) {
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
			if (iterable == nullptr) {
				return;
			}
			const TokenType op = iterable->value.type;
			const bool is_range = ast::NodeType::BINARY_OPERATOR == iterable->node_type
				&& (TokenType::OPERATOR_RANGE_EXCLUSIVE == op || TokenType::OPERATOR_RANGE_INCLUSIVE == op);
			if (is_range) {
				for (ast::Node* bound : iterable->children) {
					evaluate(analysis, bound, nullptr);
				}
			}
			else {
				Evaluated collection = evaluate(analysis, iterable, nullptr);
				TypeInfo const* type = base(collection.type);
				if (type != nullptr && TypeInfoVariant::POINTER == type->variant) {
					TypeInfo* target = static_cast<TypeInfoPointer const*>(type)->base_type;
					collection = at(through(value_of(collection), target), target);
					type = base(target);
				}
				TypeInfo* element = element_of(type);
				const Place elements = is_array(type, ArrayType::STATIC)
					? (collection.place.exists ? collection.place : temporary(value_of(collection)))
					: through(value_of(collection), element);
				// The element, by value or by &; the second name is an index
				if (!names.empty()) {
					ast::Node* name = names[0];
					if (ast::NodeType::UNARY_OPERATOR == name->node_type && !name->children.empty()) {
						store(analysis, variable_place(analysis, name->children[0]), address_of(analysis, elements, element, name, false), name);
					}
					else if (!is_wildcard(name)) {
						store(analysis, variable_place(analysis, name), value_of(at(elements, element)), name);
					}
				}
			}
			if (body != nullptr) {
				walk_block(analysis, body, nullptr, false);
			}
		}

		void walk_loop(Analysis& analysis, ast::Node* node) {
			for (ast::Node* child : node->children) {
				if (ast::NodeType::WITH_CLAUSE == child->node_type) {
					for (ast::Node* list : child->children) {
						for (ast::Node* statement : list->children) {
							walk_statement(analysis, statement);
						}
					}
				}
			}
			for (ast::Node* child : node->children) {
				if (ast::NodeType::WHILE_CLAUSE == child->node_type && !child->children.empty()) {
					evaluate(analysis, child->children[0], BUILTIN_bool);
				}
				else if (ast::NodeType::BLOCK == child->node_type) {
					walk_block(analysis, child, nullptr, false);
				}
			}
		}

		// push_context: what's reachable from a context is unrestricted, except extensions on this frame.
		void walk_push_context(Analysis& analysis, ast::Node* node) {
			auto override_value = [&](ast::Node* value_node, bool extension) {
				TypeInfo* type = type_at(analysis, value_node, nullptr);
				const Reach reach = convert(analysis, evaluate(analysis, value_node, type), type, value_node);
				if (reach.local && !extension) {
					report(analysis, value_node, "a context can't point into the stack, so push_context can't use this (docs/memory.md, Contexts)");
				}
			};
			for (size_t i = 1; i + 1 < node->children.size(); ++i) {
				ast::Node* part = node->children[i];
				if (ast::NodeType::KEYWORD_FROM == part->node_type) {
					if (!part->children.empty()) {
						override_value(part->children[0], false);
					}
					continue;
				}
				if (ast::NodeType::LIST == part->node_type) {
					for (ast::Node* field : part->children) {
						if (field->children.size() == 2) {
							override_value(field->children[1], is_text(field->children[0]->value.value, "extensions"));
						}
					}
					continue;
				}
				override_value(part, false);
			}
			ast::Node* body = node->children.empty() ? nullptr : node->children.back();
			if (body != nullptr && ast::NodeType::BLOCK == body->node_type) {
				walk_block(analysis, body, nullptr, false);
			}
		}

		void walk_statement(Analysis& analysis, ast::Node* statement) {
			const ast::NodeType type = statement->node_type;
			if (ast::NodeType::DEFINITION == type) {
				walk_definition(analysis, statement);
			}
			else if (is_assignment(statement)) {
				walk_assignment(analysis, statement);
			}
			else if (ast::NodeType::RETURN == type) {
				walk_return(analysis, statement);
			}
			else if (ast::NodeType::GIVE == type) {
				if (!analysis.computes.empty() && !statement->children.empty()) {
					auto& [given, compute_type] = analysis.computes.back();
					ast::Node* value_node = statement->children[0];
					given = join(given, convert(analysis, evaluate(analysis, value_node, compute_type), compute_type, value_node));
				}
				return;
			}
			else if (ast::NodeType::BREAK == type || ast::NodeType::CONTINUE == type) {
				return;
			}
			else if (ast::NodeType::IF == type) {
				walk_if(analysis, statement, nullptr, false);
			}
			else if (ast::NodeType::FOR_LOOP == type) {
				walk_for(analysis, statement);
			}
			else if (ast::NodeType::LOOP == type) {
				walk_loop(analysis, statement);
			}
			else if (ast::NodeType::DEFER == type) {
				for (ast::Node* deferred : statement->children) {
					walk_statement(analysis, deferred);
				}
			}
			else if (ast::NodeType::BLOCK == type) {
				walk_block(analysis, statement, nullptr, false);
			}
			else if (ast::NodeType::MATCH == type) {
				walk_match(analysis, statement, nullptr, false, false);
			}
			else if (ast::NodeType::SWITCH == type) {
				walk_match(analysis, statement, nullptr, false, true);
			}
			else if (ast::NodeType::PUSH_CONTEXT == type) {
				walk_push_context(analysis, statement);
			}
			else if (ast::NodeType::DIRECTIVE == type) {
				// #run runs while compiling, where nothing it makes outlives the run
				return;
			}
			else {
				evaluate(analysis, statement, nullptr);
			}
		}

		/*
		 * A block's statements, with the branch the checker picked for each #if chain; as a value, what
		 * its last statement gives.
		 */
		Reach walk_block(Analysis& analysis, ast::Node* block, TypeInfo* result_type, bool as_value) {
			Reach result;
			for (size_t i = 0; i < block->children.size(); ++i) {
				ast::Node* statement = block->children[i];
				if (ast::NodeType::DIRECTIVE == statement->node_type && is_text(statement->value.value, "#if")) {
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
					const CheckedNode* chosen = found_at(analysis, statement);
					if (chosen != nullptr && chosen->variant < chain.size() && !chain[chosen->variant]->children.empty()) {
						result = join(result, walk_block(analysis, chain[chosen->variant]->children.back(), result_type, as_value));
					}
					continue;
				}
				const ast::NodeType type = statement->node_type;
				if (as_value && i + 1 == block->children.size() && ast::NodeType::DEFINITION != type && !is_assignment(statement)
					&& ast::NodeType::RETURN != type && ast::NodeType::GIVE != type && ast::NodeType::BREAK != type && ast::NodeType::CONTINUE != type
					&& ast::NodeType::FOR_LOOP != type && ast::NodeType::LOOP != type && ast::NodeType::BLOCK != type) {
					result = join(result, convert(analysis, evaluate(analysis, statement, result_type), result_type, statement));
					continue;
				}
				walk_statement(analysis, statement);
			}
			return result;
		}

	}

	namespace {

	/*
	 * A function's body walked, until what its variables hold settles, then once more, reporting if it's
	 * asked to: which of its parameters it gives back pointers from, and whether it reported nothing.
	 */
	bool analyze(const StackCheck& function, const ReturnSources& sources, bool reporting, std::vector<bool>& returns_from) {
		const CheckedBody& checked = *function.checked;
		TypeInfoFunction const* type = function.type;
		ast::Node* body = function.body;
		Analysis analysis{ checked, type, function.file_path, sources, std::vector<bool>(type->input.size(), false), {},
			{}, {}, {}, false, false, 0, {} };
		/*
		 * Parameters hold what the caller passed: local, from that parameter, unless it's #escaping. An
		 * any, a pointer to a #scoped struct or a varargs view may be deep.
		 */
		for (size_t i = 0; i < checked.parameters.size() && i < type->input.size(); ++i) {
			const FunctionInput& input = type->input[i];
			Variable& parameter = variable(analysis, checked.parameters[i]);
			if (!input.is_escaping && (input.is_varargs || carries_pointers(input.type))) {
				parameter.holds = Reach{ true, PARAMETER, static_cast<int>(i), input.is_varargs || is_deep_kind(input.type) };
			}
		}
		// What variables hold only grows, so this settles; then once more, reporting
		for (size_t round = 0; round < 64; ++round) {
			analysis.changed = false;
			analysis.aliases.clear();
			walk_block(analysis, body, nullptr, false);
			if (!analysis.changed) {
				break;
			}
		}
		analysis.reporting = reporting;
		analysis.aliases.clear();
		walk_block(analysis, body, nullptr, false);
		returns_from = analysis.returns_from;
		return analysis.errors == 0;
	}

	}

	bool check_all_stack_pointers(std::vector<StackCheck>& functions) {
		/*
		 * Which parameters each function gives back pointers from: none to begin with, and more as calls are found
		 * to give them back, until nothing changes. They only grow, so it settles; a loop of calls is no different.
		 */
		ReturnSources sources;
		for (const StackCheck& function : functions) {
			sources[function.declaration] = std::vector<bool>(function.type->input.size(), false);
		}
		std::vector<bool> found;
		for (size_t round = 0; round < 64; ++round) {
			bool changed = false;
			for (const StackCheck& function : functions) {
				analyze(function, sources, false, found);
				std::vector<bool>& known = sources[function.declaration];
				for (size_t i = 0; i < found.size() && i < known.size(); ++i) {
					if (found[i] && !known[i]) {
						known[i] = true;
						changed = true;
					}
				}
			}
			if (!changed) {
				break;
			}
		}
		bool clean = true;
		for (const StackCheck& function : functions) {
			clean = analyze(function, sources, true, found) && clean;
		}
		return clean;
	}

}
