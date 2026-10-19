#include <format>
#include <map>
#include <mutex>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include "error/reporting.h"
#include "front_end/checking.h"
#include "front_end/front_end.h"
#include "front_end/info.h"
#include "front_end/walk.h"
#include "parser/ast_types.h"

/*
 * Checked bodies (docs/types.md, Checked Bodies): a constrained generic function's body is checked
 * once, before any instance, with archetypes for its type parameters. What an archetype has comes
 * from what the constraints promise, worked out from their requirements: a constraint is made of
 * them, so what it promises is what they'd find, whatever type it's given.
 */
namespace hemera {
	/// <summary>
	/// One generic's check before any instance: its archetypes, and the constraint calls its own
	/// constraints make sure of, which constraints of what its body calls can rely on.
	/// </summary>
	struct EarlyCheck {
		Declaration* instance = nullptr;
		std::vector<TypeInfoArchetype*> archetypes;
		// The early instance's arguments, and whether the archetypes have what's promised yet
		std::vector<TypeInfo*> arguments;
		std::vector<ConstantValue> values;
		bool promised = false;
		std::set<std::string> atoms;
		bool done = false;
		bool failed = false;
	};

	namespace {
		std::string text_of(InternedString value) {
			return value != nullptr ? std::string(std::string_view(*value)) : std::string("_");
		}

		bool is_combination(const ast::Node* node) {
			const TokenType op = node->value.type;
			return ast::NodeType::BINARY_OPERATOR == node->node_type && (TokenType::OPERATOR_AND == op || TokenType::OPERATOR_OR == op);
		}

		bool is_postfix_marker(const ast::Node* node) {
			const ast::NodeType type = node->node_type;
			return ast::NodeType::DOT_ACCESS == type || ast::NodeType::PAREN_GROUP == type || ast::NodeType::ARRAY_DIMENSION == type
				|| (ast::NodeType::UNARY_OPERATOR == type && TokenType::OPERATOR_DEREFERENCE == node->value.type);
		}

		// The arguments of a call like Convertible(From, To): in its parentheses, or after them.
		bool call_arguments(const ast::Node* node, std::vector<ast::Node*>& arguments) {
			for (size_t i = 0; i < node->children.size(); ++i) {
				ast::Node* step = node->children[i];
				if (ast::NodeType::PAREN_GROUP != step->node_type) {
					continue;
				}
				arguments.assign(step->children.begin(), step->children.end());
				while (i + 1 < node->children.size() && !is_postfix_marker(node->children[i + 1])) {
					arguments.push_back(node->children[++i]);
				}
				return true;
			}
			return false;
		}

		// Integers and floats are numbers, and numbers have == and <.
		uint32_t with_implied(uint32_t capabilities) {
			if ((capabilities & (CAPABILITY_SIGNED | CAPABILITY_UNSIGNED)) != 0) {
				capabilities |= CAPABILITY_INTEGER;
			}
			if ((capabilities & (CAPABILITY_INTEGER | CAPABILITY_FLOAT)) != 0) {
				capabilities |= CAPABILITY_ARITHMETIC;
			}
			if ((capabilities & CAPABILITY_ARITHMETIC) != 0) {
				capabilities |= CAPABILITY_EQUALITY | CAPABILITY_ORDERING;
			}
			if ((capabilities & CAPABILITY_ORDERING) != 0) {
				capabilities |= CAPABILITY_EQUALITY;
			}
			return capabilities;
		}

		// What's promised about one archetype.
		struct Promise {
			uint32_t capabilities = 0;
			std::vector<std::pair<InternedString, TypeInfo*>> fields;
			TypeInfo* element = nullptr;
		};

		struct Promises {
			std::map<TypeInfoArchetype*, Promise> types;
			std::set<std::string> atoms;
		};

		// A && B: what either promises.
		void unite(Promises& into, const Promises& other) {
			for (const auto& [archetype, promise] : other.types) {
				Promise& mine = into.types[archetype];
				mine.capabilities = with_implied(mine.capabilities | promise.capabilities);
				for (const auto& field : promise.fields) {
					bool known = false;
					for (const auto& existing : mine.fields) {
						known = known || *existing.first == *field.first;
					}
					if (!known) {
						mine.fields.push_back(field);
					}
				}
				if (mine.element == nullptr) {
					mine.element = promise.element;
				}
			}
			into.atoms.insert(other.atoms.begin(), other.atoms.end());
		}

		// A || B: only what both promise, since either may be the one that holds.
		Promises intersect(const Promises& a, const Promises& b) {
			Promises shared;
			for (const auto& [archetype, promise] : a.types) {
				auto other = b.types.find(archetype);
				if (other == b.types.end()) {
					continue;
				}
				Promise& both = shared.types[archetype];
				both.capabilities = with_implied(promise.capabilities) & with_implied(other->second.capabilities);
				for (const auto& field : promise.fields) {
					for (const auto& theirs : other->second.fields) {
						if (*field.first == *theirs.first && same_type(field.second, theirs.second)) {
							both.fields.push_back(field);
						}
					}
				}
				if (promise.element != nullptr && same_type(promise.element, other->second.element)) {
					both.element = promise.element;
				}
			}
			for (const std::string& atom : a.atoms) {
				if (b.atoms.contains(atom)) {
					shared.atoms.insert(atom);
				}
			}
			return shared;
		}

		/*
		 * What a constraint is called with: an archetype or a real type, or a value, known or not.
		 * text is how it's written in messages and in the atoms that identify a call.
		 */
		struct Argument {
			TypeInfo* type = nullptr;
			ConstantValue value{ ConstantValue::Kind::BOOLEAN, false, 0, {}, nullptr };
			bool is_type = false;
			std::string text;
		};

		TypeInfoArchetype* archetype_of(TypeInfo* type) {
			return type != nullptr && TypeInfoVariant::ARCHETYPE == type->variant ? static_cast<TypeInfoArchetype*>(type) : nullptr;
		}

		// Whether an argument stands for something only an instance knows.
		bool is_open(const Argument& argument) {
			return argument.is_type ? archetype_of(argument.type) != nullptr : ConstantValue::Kind::UNKNOWN == argument.value.kind;
		}

		std::string atom_key(const Declaration* constraint, const std::vector<Argument>& arguments) {
			std::string key = std::format("{}(", static_cast<const void*>(constraint));
			for (const Argument& argument : arguments) {
				key += argument.is_type ? std::format("{} ", static_cast<const void*>(get_base_type_or_alias(argument.type)))
					: "=" + constant_text(argument.value) + " ";
			}
			return key + ")";
		}

		std::string call_text(const Declaration* constraint, const std::vector<Argument>& arguments) {
			std::string text = text_of(constraint->name) + "(";
			for (size_t i = 0; i < arguments.size(); ++i) {
				text += (i > 0 ? ", " : "") + arguments[i].text;
			}
			return text + ")";
		}

		Walk walk_in(Walk& walk, const Declaration* declaration) {
			return Walk{
				walk.executor,
				declaration->package_path,
				declaration->file_name,
				declaration->file,
				nullptr,
				nullptr,
				file_path_of(declaration->package_path, declaration->file_name),
				{},
				{},
				{},
			};
		}

		// A constraint function's parameters' names, in order.
		std::vector<std::string> parameter_names(const Declaration* constraint) {
			std::vector<std::string> names;
			ast::Node* function = generic_node(constraint);
			if (function == nullptr) {
				return names;
			}
			for (ast::Node* child : function->children) {
				if (ast::NodeType::LIST != child->node_type) {
					continue;
				}
				for (ast::Node* parameter : child->children) {
					if (ast::NodeType::COLON == parameter->node_type && !parameter->children.empty()) {
						names.push_back(text_of(parameter->children[0]->value.value));
					}
				}
				break;
			}
			return names;
		}

		// Which of base/compiler's requirements a statement in a constraint calls, or "".
		std::string requirement_of(const Declaration* constraint, const ast::Node* node) {
			if (ast::NodeType::IDENTIFIER != node->node_type || node->value.value == nullptr) {
				return "";
			}
			std::string name = text_of(node->value.value);
			const bool qualified = node->children.size() >= 2 && ast::NodeType::DOT_ACCESS == node->children[0]->node_type;
			bool in_compiler = false;
			if (qualified) {
				InternedString package = constraint->file != nullptr ? imported_package(constraint->file, node->value.value) : nullptr;
				in_compiler = package != nullptr && std::string_view(*package).starts_with("<base>")
					&& std::string_view(*package).ends_with("compiler");
				name = text_of(node->children[1]->value.value);
			}
			else {
				in_compiler = constraint->package_path != nullptr && std::string_view(*constraint->package_path).starts_with("<base>")
					&& std::string_view(*constraint->package_path).ends_with("compiler");
			}
			const bool known = name.starts_with("require") || name == "note";
			return in_compiler && known ? name : "";
		}

		struct Analysis {
			Walk& walk;
			size_t depth = 0;
		};

		/*
		 * One argument in a constraint's body or a generic's constraints: a parameter's argument by its
		 * name, a string's text, a type, or a constant.
		 */
		Progress resolve_argument(Walk& inside, const std::map<std::string, Argument>& parameters, ast::Node* node, Argument& result) {
			if (ast::NodeType::IDENTIFIER == node->node_type && node->children.empty()) {
				auto known = parameters.find(text_of(node->value.value));
				if (known != parameters.end()) {
					result = known->second;
					return Progress::DONE;
				}
			}
			if (ast::NodeType::LITERAL == node->node_type && TokenType::LITERAL_STRING == node->value.type) {
				const std::string text = text_of(node->value.value);
				result.text = text.size() >= 2 ? text.substr(1, text.size() - 2) : text;
				return Progress::DONE;
			}
			if (ast::NodeType::LITERAL != node->node_type && ast::NodeType::BINARY_OPERATOR != node->node_type
				&& ast::NodeType::UNARY_OPERATOR != node->node_type && ast::NodeType::ENUM_SHORTHAND != node->node_type) {
				Progress named = walk_names(inside, node, Need::DECLARED);
				if (named != Progress::DONE) {
					return named;
				}
				TypeInfo* type = nullptr;
				Progress progress = type_of(inside, node, Need::DECLARED, type);
				if (progress == Progress::PARKED) {
					return progress;
				}
				if (progress == Progress::DONE && type != nullptr) {
					result.type = type;
					result.is_type = true;
					result.text = to_string(type);
					return Progress::DONE;
				}
			}
			// Anything else, like capacity * 2, is only known at an instance
			result.value.kind = ConstantValue::Kind::UNKNOWN;
			result.value.member = "?";
			result.text = "?";
			return Progress::DONE;
		}

		// Whether an expression in a constraint's body uses a parameter only an instance knows.
		bool uses_open(const ast::Node* node, const std::map<std::string, Argument>& parameters) {
			if (ast::NodeType::IDENTIFIER == node->node_type || ast::NodeType::TYPE == node->node_type) {
				auto known = parameters.find(text_of(node->value.value));
				if (known != parameters.end() && is_open(known->second)) {
					return true;
				}
			}
			for (const ast::Node* child : node->children) {
				if (uses_open(child, parameters)) {
					return true;
				}
			}
			return false;
		}

		Progress promise_expression(Analysis& analysis, Walk& inside, const Declaration* context, const std::map<std::string, Argument>& parameters,
			ast::Node* node, const Argument* subject, Promises& result);

		// What one constraint call promises, from the requirements its body is made of.
		Progress promise_call(Analysis& analysis, Declaration* constraint, const std::vector<Argument>& arguments, Promises& result) {
			result.atoms.insert(atom_key(constraint, arguments));
			ast::Node* body = function_body(constraint);
			if (body == nullptr || analysis.depth > 16) {
				return Progress::DONE;
			}
			++analysis.depth;
			std::map<std::string, Argument> parameters;
			const std::vector<std::string> names = parameter_names(constraint);
			for (size_t i = 0; i < names.size() && i < arguments.size(); ++i) {
				parameters[names[i]] = arguments[i];
			}
			Walk inside = walk_in(analysis.walk, constraint);
			for (const std::string& name : names) {
				inside.locals.push_back(intern(name));
			}
			for (ast::Node* statement : body->children) {
				const std::string requirement = requirement_of(constraint, statement);
				std::vector<ast::Node*> nodes;
				call_arguments(statement, nodes);
				if (requirement == "require_any") {
					// Only what every alternative promises
					Promises shared;
					bool first = true;
					for (ast::Node* alternative : nodes) {
						Promises each;
						Progress progress = promise_expression(analysis, inside, constraint, parameters, alternative, nullptr, each);
						if (progress != Progress::DONE) {
							--analysis.depth;
							return progress;
						}
						shared = first ? each : intersect(shared, each);
						first = false;
					}
					shared.atoms.clear();
					unite(result, shared);
					continue;
				}
				if (!requirement.empty()) {
					std::vector<Argument> given;
					for (ast::Node* node : nodes) {
						Argument argument;
						Progress progress = resolve_argument(inside, parameters, node, argument);
						if (progress != Progress::DONE) {
							--analysis.depth;
							return progress;
						}
						given.push_back(argument);
					}
					TypeInfoArchetype* archetype = !given.empty() && given[0].is_type ? archetype_of(given[0].type) : nullptr;
					if (archetype == nullptr) {
						continue;
					}
					Promise& promise = result.types[archetype];
					const uint32_t capability = requirement == "require_equality" ? CAPABILITY_EQUALITY
						: requirement == "require_ordering" ? CAPABILITY_ORDERING
						: requirement == "require_integer" ? CAPABILITY_INTEGER
						: requirement == "require_signed" ? CAPABILITY_SIGNED
						: requirement == "require_unsigned" ? CAPABILITY_UNSIGNED
						: requirement == "require_float" ? CAPABILITY_FLOAT
						: requirement == "require_numeric" ? CAPABILITY_ARITHMETIC
						: requirement == "require_mutable" ? CAPABILITY_MUTABLE
						: 0;
					promise.capabilities = with_implied(promise.capabilities | capability);
					if (requirement == "require_field" && given.size() == 3 && given[2].is_type) {
						promise.fields.emplace_back(intern(given[1].text), given[2].type);
					}
					if (requirement == "require_view" && given.size() == 2 && given[1].is_type) {
						promise.element = given[1].type;
					}
					continue;
				}
				// Another constraint, whose promises are this one's
				NameRegistry& names_registry = analysis.walk.executor.program_info->names;
				Declaration* nested = constraint_named(names_registry, constraint->package_path, constraint->file, statement);
				if (nested != nullptr && !nodes.empty()) {
					Promises inner;
					Progress progress = promise_expression(analysis, inside, constraint, parameters, statement, nullptr, inner);
					if (progress != Progress::DONE) {
						--analysis.depth;
						return progress;
					}
					unite(result, inner);
				}
			}
			--analysis.depth;
			return Progress::DONE;
		}

		// A constraint call's constraint and arguments, written in context's file.
		Progress call_parts(Analysis& analysis, Walk& inside, const Declaration* context, const std::map<std::string, Argument>& parameters,
			ast::Node* node, const Argument* subject, Declaration*& constraint, std::vector<Argument>& arguments) {

			// The constraint's name, waiting while it may still be declared, as any name does
			if (ast::NodeType::IDENTIFIER == node->node_type || ast::NodeType::TYPE == node->node_type) {
				ast::Node* qualifier = nullptr;
				for (size_t i = 0; i + 1 < node->children.size(); ++i) {
					if (ast::NodeType::DOT_ACCESS == node->children[i]->node_type) {
						qualifier = node->children[i + 1];
						break;
					}
				}
				bool head_was_package = false;
				Progress named = qualifier != nullptr
					? require_qualified(inside, node, node->value.value, qualifier, Need::DECLARED, head_was_package)
					: require(inside, node, node->value.value, Need::DECLARED);
				if (named != Progress::DONE) {
					return named;
				}
			}
			NameRegistry& names = analysis.walk.executor.program_info->names;
			constraint = constraint_named(names, context->package_path, context->file, node);
			if (constraint == nullptr) {
				return Progress::DONE;
			}
			std::vector<ast::Node*> nodes;
			if (!call_arguments(node, nodes)) {
				if (subject != nullptr) {
					arguments.push_back(*subject);
				}
				return Progress::DONE;
			}
			for (ast::Node* argument_node : nodes) {
				Argument argument;
				Progress progress = resolve_argument(inside, parameters, argument_node, argument);
				if (progress != Progress::DONE) {
					return progress;
				}
				arguments.push_back(argument);
			}
			return Progress::DONE;
		}

		Progress promise_expression(Analysis& analysis, Walk& inside, const Declaration* context, const std::map<std::string, Argument>& parameters,
			ast::Node* node, const Argument* subject, Promises& result) {

			if (ast::NodeType::PAREN_GROUP == node->node_type && node->children.size() == 1) {
				return promise_expression(analysis, inside, context, parameters, node->children[0], subject, result);
			}
			if (is_combination(node) && node->children.size() == 2) {
				Promises left;
				Promises right;
				Progress progress = promise_expression(analysis, inside, context, parameters, node->children[0], subject, left);
				if (progress == Progress::DONE) {
					progress = promise_expression(analysis, inside, context, parameters, node->children[1], subject, right);
				}
				if (progress != Progress::DONE) {
					return progress;
				}
				if (TokenType::OPERATOR_AND == node->value.type) {
					unite(result, left);
					unite(result, right);
				}
				else {
					unite(result, intersect(left, right));
				}
				return Progress::DONE;
			}
			Declaration* constraint = nullptr;
			std::vector<Argument> arguments;
			Progress progress = call_parts(analysis, inside, context, parameters, node, subject, constraint, arguments);
			if (progress != Progress::DONE || constraint == nullptr) {
				return progress;
			}
			return promise_call(analysis, constraint, arguments, result);
		}

		// What a proof found missing: each constraint call the caller's constraints don't promise.
		struct Proof {
			bool holds = true;
			std::vector<std::string> missing;
		};

		bool has_capability(const Argument& argument, uint32_t capability) {
			TypeInfoArchetype* archetype = argument.is_type ? archetype_of(argument.type) : nullptr;
			return archetype == nullptr || (with_implied(archetype->capabilities) & capability) == capability;
		}

		Progress prove_expression(Analysis& analysis, Walk& inside, const Declaration* context, const std::map<std::string, Argument>& parameters,
			ast::Node* node, const Argument* subject, const EarlyCheck& have, Proof& proof);

		/*
		 * Whether one constraint call holds for any instance, from what's promised: the caller's own
		 * constraints make sure of the same call, or every requirement in it is promised. Anything
		 * about a real type or a known value is left to the instances, which check it again.
		 */
		Progress prove_call(Analysis& analysis, Declaration* constraint, const std::vector<Argument>& arguments, const EarlyCheck& have,
			Proof& proof) {

			bool open = false;
			for (const Argument& argument : arguments) {
				open = open || is_open(argument);
			}
			if (!open || have.atoms.contains(atom_key(constraint, arguments))) {
				return Progress::DONE;
			}
			ast::Node* body = function_body(constraint);
			if (body == nullptr || analysis.depth > 16) {
				proof.holds = false;
				proof.missing.push_back(call_text(constraint, arguments));
				return Progress::DONE;
			}
			++analysis.depth;
			std::map<std::string, Argument> parameters;
			const std::vector<std::string> names = parameter_names(constraint);
			for (size_t i = 0; i < names.size() && i < arguments.size(); ++i) {
				parameters[names[i]] = arguments[i];
			}
			Walk inside = walk_in(analysis.walk, constraint);
			for (const std::string& name : names) {
				inside.locals.push_back(intern(name));
			}
			bool holds = true;
			for (ast::Node* statement : body->children) {
				const std::string requirement = requirement_of(constraint, statement);
				std::vector<ast::Node*> nodes;
				const bool is_call = call_arguments(statement, nodes);
				if (requirement == "note") {
					continue;
				}
				if (requirement == "require_any") {
					bool any = false;
					for (ast::Node* alternative : nodes) {
						Proof each;
						Progress progress = prove_expression(analysis, inside, constraint, parameters, alternative, nullptr, have, each);
						if (progress != Progress::DONE) {
							--analysis.depth;
							return progress;
						}
						any = any || each.holds;
					}
					holds = holds && any;
					continue;
				}
				if (!requirement.empty() && requirement != "require") {
					std::vector<Argument> given;
					for (ast::Node* node : nodes) {
						Argument argument;
						Progress progress = resolve_argument(inside, parameters, node, argument);
						if (progress != Progress::DONE) {
							--analysis.depth;
							return progress;
						}
						given.push_back(argument);
					}
					if (given.empty()) {
						continue;
					}
					const uint32_t capability = requirement == "require_equality" ? CAPABILITY_EQUALITY
						: requirement == "require_ordering" ? CAPABILITY_ORDERING
						: requirement == "require_integer" ? CAPABILITY_INTEGER
						: requirement == "require_signed" ? CAPABILITY_SIGNED
						: requirement == "require_unsigned" ? CAPABILITY_UNSIGNED
						: requirement == "require_float" ? CAPABILITY_FLOAT
						: requirement == "require_numeric" ? CAPABILITY_ARITHMETIC
						: requirement == "require_mutable" ? CAPABILITY_MUTABLE
						: 0;
					bool met = has_capability(given[0], capability);
					TypeInfoArchetype* archetype = given[0].is_type ? archetype_of(given[0].type) : nullptr;
					if (archetype != nullptr && requirement == "require_field" && given.size() == 3) {
						met = false;
						for (const auto& [name, type] : archetype->fields) {
							met = met || (text_of(name) == given[1].text && (!given[2].is_type || same_type(type, given[2].type)));
						}
					}
					if (archetype != nullptr && requirement == "require_view" && given.size() == 2) {
						met = archetype->element != nullptr && (!given[1].is_type || same_type(archetype->element, given[1].type));
					}
					holds = holds && met;
					continue;
				}
				// require(condition, ...), or anything else, about what only an instance knows can't be told early
				if (uses_open(statement, parameters)) {
					NameRegistry& names_registry = analysis.walk.executor.program_info->names;
					Declaration* nested = requirement.empty() && is_call
						? constraint_named(names_registry, constraint->package_path, constraint->file, statement) : nullptr;
					if (nested != nullptr) {
						Proof inner;
						Progress progress = prove_expression(analysis, inside, constraint, parameters, statement, nullptr, have, inner);
						if (progress != Progress::DONE) {
							--analysis.depth;
							return progress;
						}
						holds = holds && inner.holds;
					}
					else {
						holds = false;
					}
				}
			}
			--analysis.depth;
			if (!holds) {
				proof.holds = false;
				proof.missing.push_back(call_text(constraint, arguments));
			}
			return Progress::DONE;
		}

		Progress prove_expression(Analysis& analysis, Walk& inside, const Declaration* context, const std::map<std::string, Argument>& parameters,
			ast::Node* node, const Argument* subject, const EarlyCheck& have, Proof& proof) {

			if (ast::NodeType::PAREN_GROUP == node->node_type && node->children.size() == 1) {
				return prove_expression(analysis, inside, context, parameters, node->children[0], subject, have, proof);
			}
			if (is_combination(node) && node->children.size() == 2) {
				Proof left;
				Proof right;
				Progress progress = prove_expression(analysis, inside, context, parameters, node->children[0], subject, have, left);
				if (progress == Progress::DONE) {
					progress = prove_expression(analysis, inside, context, parameters, node->children[1], subject, have, right);
				}
				if (progress != Progress::DONE) {
					return progress;
				}
				const bool both = TokenType::OPERATOR_AND == node->value.type;
				const bool holds = both ? left.holds && right.holds : left.holds || right.holds;
				if (!holds) {
					proof.holds = false;
					proof.missing.insert(proof.missing.end(), left.missing.begin(), left.missing.end());
					proof.missing.insert(proof.missing.end(), right.missing.begin(), right.missing.end());
				}
				return Progress::DONE;
			}
			Declaration* constraint = nullptr;
			std::vector<Argument> arguments;
			Progress progress = call_parts(analysis, inside, context, parameters, node, subject, constraint, arguments);
			if (progress != Progress::DONE || constraint == nullptr) {
				return progress;
			}
			return prove_call(analysis, constraint, arguments, have, proof);
		}

		// A generic's parameters, as written: each one's name, and its node.
		std::vector<std::pair<std::string, ast::Node*>> generic_parameters(const Declaration* generic) {
			std::vector<std::pair<std::string, ast::Node*>> result;
			ast::Node* value = generic_node(generic);
			if (value == nullptr) {
				return result;
			}
			for (ast::Node* child : value->children) {
				if (ast::NodeType::GENERIC_TAG != child->node_type) {
					continue;
				}
				for (ast::Node* parameter : child->children) {
					const bool named = ast::NodeType::COLON == parameter->node_type && !parameter->children.empty();
					result.emplace_back(text_of(named ? parameter->children[0]->value.value : parameter->value.value), parameter);
				}
			}
			return result;
		}

		ast::Node* where_clause_of(const Declaration* generic) {
			ast::Node* value = generic_node(generic);
			for (ast::Node* child : value != nullptr ? value->children : MyVector<ast::Node*>{}) {
				if (ast::NodeType::WHERE_CLAUSE == child->node_type && !child->children.empty()) {
					return child->children[0];
				}
			}
			return nullptr;
		}

		// A function's declared result, when it's a single name, like the type in fn(C: type) -> type.
		std::string declared_result(const Declaration* function) {
			ast::Node* node = generic_node(function);
			bool parameters_seen = false;
			for (ast::Node* child : node != nullptr ? node->children : MyVector<ast::Node*>{}) {
				if (ast::NodeType::LIST == child->node_type && !parameters_seen) {
					parameters_seen = true;
					continue;
				}
				if (parameters_seen && (ast::NodeType::TYPE == child->node_type || ast::NodeType::IDENTIFIER == child->node_type)
					&& child->children.empty()) {
					return text_of(child->value.value);
				}
			}
			return "";
		}

		/*
		 * Whether a derived parameter is a type, from how it's written: a type, like ptr[A], or a call to
		 * a function that returns one, like element_of(C). size_of and other values aren't.
		 */
		bool derived_is_type(NameRegistry& names, const Declaration* generic, const ast::Node* expression) {
			if (ast::NodeType::TYPE == expression->node_type) {
				return true;
			}
			if (ast::NodeType::IDENTIFIER != expression->node_type) {
				return false;
			}
			std::vector<ast::Node*> arguments;
			if (!call_arguments(expression, arguments)) {
				return true;
			}
			const std::string name = text_of(expression->value.value);
			if (name == "size_of" || name == "align_of" || name == "offset_of") {
				return false;
			}
			std::scoped_lock<std::mutex> lock(names.mutex);
			auto found = names.declarations.find(std::make_pair(generic->package_path, expression->value.value));
			return found != names.declarations.end() && declared_result(found->second) == "type";
		}

		const Declaration* owner_of(const Declaration* instance) {
			for (TypeInfo* argument : instance->generic_arguments) {
				TypeInfoArchetype* archetype = archetype_of(argument);
				if (archetype != nullptr) {
					return archetype->owner;
				}
			}
			for (const ConstantValue& value : instance->generic_values) {
				if (ConstantValue::Kind::UNKNOWN == value.kind) {
					return value.function;
				}
			}
			return nullptr;
		}

		/*
		 * Whether a value parameter sizes a type, like T[capacity] or Buffer[T, capacity]: its value is
		 * needed to lay the type out, so only an instance can check where it's used.
		 */
		bool sizes_a_type(const ast::Node* node, const std::set<std::string>& values, bool in_type) {
			if (in_type && (ast::NodeType::IDENTIFIER == node->node_type || ast::NodeType::TYPE == node->node_type)
				&& values.contains(text_of(node->value.value))) {
				return true;
			}
			// A call's generic arguments, like scaled[factor](value), are values given, not sizes
			bool is_call = false;
			for (const ast::Node* child : node->children) {
				is_call = is_call || ast::NodeType::PAREN_GROUP == child->node_type;
			}
			for (const ast::Node* child : node->children) {
				const bool sizes = ast::NodeType::ARRAY_DIMENSION == child->node_type
					|| (ast::NodeType::GENERIC_TAG == child->node_type && !is_call);
				if (sizes_a_type(child, values, in_type || sizes)) {
					return true;
				}
			}
			return false;
		}

		std::shared_ptr<EarlyCheck> early_check_of(NameRegistry& names, const Declaration* generic) {
			std::scoped_lock<std::mutex> lock(names.mutex);
			auto found = names.early_checks.find(generic);
			return found != names.early_checks.end() ? found->second : nullptr;
		}

		// Each of an instance's parameters' arguments, by name.
		std::map<std::string, Argument> arguments_of(const Declaration* generic, const std::vector<TypeInfo*>& types,
			const std::vector<ConstantValue>& values) {

			std::map<std::string, Argument> result;
			const auto parameters = generic_parameters(generic);
			for (size_t i = 0; i < parameters.size() && i < types.size(); ++i) {
				Argument argument;
				if (types[i] != nullptr) {
					argument.type = types[i];
					argument.is_type = true;
					argument.text = to_string(argument.type);
				}
				else if (i < values.size()) {
					argument.value = values[i];
					argument.text = constant_text(argument.value);
				}
				result[parameters[i].first] = argument;
			}
			return result;
		}

		std::map<std::string, Argument> arguments_of(const Declaration* generic, const Declaration* instance) {
			return arguments_of(generic, instance->generic_arguments, instance->generic_values);
		}

		/*
		 * Gives a generic's archetypes what its constraints promise, once: before its body is checked,
		 * or sooner, when its signature uses a generic whose constraints need proving from them.
		 */
		Progress ensure_promised(Walk& walk, const Declaration* generic, EarlyCheck& check) {
			NameRegistry& names = walk.executor.program_info->names;
			{
				std::scoped_lock<std::mutex> lock(names.mutex);
				if (check.promised) {
					return Progress::DONE;
				}
			}
			std::map<std::string, Argument> parameters = arguments_of(generic, check.arguments, check.values);
			Walk inside = walk_in(walk, generic);
			for (const auto& [name, parameter] : generic_parameters(generic)) {
				inside.locals.push_back(intern(name));
			}
			Analysis analysis{ walk };
			Promises promised;
			for (const auto& [name, parameter] : generic_parameters(generic)) {
				if (!generic_parameter_is_constrained(names, generic, parameter)) {
					continue;
				}
				Promises each;
				Progress progress = promise_expression(analysis, inside, generic, parameters, parameter->children[1], &parameters[name], each);
				if (progress != Progress::DONE) {
					return progress;
				}
				unite(promised, each);
			}
			if (ast::Node* where_clause = where_clause_of(generic); where_clause != nullptr) {
				Promises each;
				Progress progress = promise_expression(analysis, inside, generic, parameters, where_clause, nullptr, each);
				if (progress != Progress::DONE) {
					return progress;
				}
				unite(promised, each);
			}
			std::scoped_lock<std::mutex> lock(names.mutex);
			if (check.promised) {
				return Progress::DONE;
			}
			for (TypeInfoArchetype* archetype : check.archetypes) {
				auto promise = promised.types.find(archetype);
				archetype->capabilities = promise != promised.types.end() ? with_implied(promise->second.capabilities) : 0;
				archetype->fields = promise != promised.types.end() ? promise->second.fields : decltype(archetype->fields){};
				archetype->element = promise != promised.types.end() ? promise->second.element : nullptr;
			}
			check.atoms = promised.atoms;
			check.promised = true;
			return Progress::DONE;
		}
	}

	bool has_constraints(NameRegistry& names, const Declaration* generic) {
		if (where_clause_of(generic) != nullptr) {
			return true;
		}
		for (const auto& [name, parameter] : generic_parameters(generic)) {
			if (generic_parameter_is_constrained(names, generic, parameter)) {
				return true;
			}
		}
		return false;
	}

	void start_early_check(Walk& walk, Declaration* generic) {
		NameRegistry& names = walk.executor.program_info->names;
		ast::Node* function = generic_node(generic);
		if (generic->generic != nullptr || function == nullptr || ast::NodeType::FUNCTION != function->node_type
			|| function_body(generic) == nullptr || generic_parameters(generic).empty() || is_constraint_function(generic)
			|| !has_constraints(names, generic)) {
			return;
		}
		auto check = std::make_shared<EarlyCheck>();
		std::vector<TypeInfo*> arguments;
		std::vector<ConstantValue> values;
		std::set<std::string> value_names;
		size_t index = 0;
		for (const auto& [name, parameter] : generic_parameters(generic)) {
			const bool is_value = ast::NodeType::DERIVED_PARAMETER == parameter->node_type
				? !parameter->children.empty() && !derived_is_type(names, generic, parameter->children[0])
				: generic_parameter_is_value(names, generic, index);
			++index;
			if (is_value) {
				// A function, like a HashMap's hash, doesn't size anything
				const bool is_function = ast::NodeType::COLON == parameter->node_type && parameter->children.size() > 1
					&& ast::NodeType::FUNCTION == parameter->children[1]->node_type;
				if (!is_function) {
					value_names.insert(name);
				}
				ConstantValue unknown{ ConstantValue::Kind::UNKNOWN, false, 0, name, generic };
				arguments.push_back(nullptr);
				values.push_back(unknown);
				continue;
			}
			auto archetype = new TypeInfoArchetype(intern(name), generic->name);
			archetype->owner = generic;
			check->archetypes.push_back(archetype);
			arguments.push_back(archetype);
			values.push_back({});
		}
		// A type sized by a value parameter is only checked at instances, which know its value
		bool sized = false;
		for (ast::Node* part : function->children) {
			// Not its own generic list or where clause, which name the parameters
			sized = sized || (ast::NodeType::GENERIC_TAG != part->node_type && ast::NodeType::WHERE_CLAUSE != part->node_type
				&& sizes_a_type(part, value_names, false));
		}
		ast::Node* body = function_body(generic);
		sized = sized || (body != nullptr && sizes_a_type(body, value_names, false));
		{
			if (sized) {
				for (TypeInfoArchetype* archetype : check->archetypes) {
					delete archetype;
				}
				return;
			}
		}
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			if (names.early_checks.contains(generic)) {
				return;
			}
			check->arguments = arguments;
			check->values = values;
			names.early_checks[generic] = check;
		}
		Declaration* instance = instance_of(walk, generic, arguments, values);
		std::scoped_lock<std::mutex> lock(names.mutex);
		check->instance = instance;
	}

	bool is_early_instance(const Declaration* instance) {
		return instance != nullptr && instance->generic != nullptr && owner_of(instance) == instance->generic;
	}

	bool has_archetype_arguments(const Declaration* instance) {
		return instance != nullptr && owner_of(instance) != nullptr;
	}

	Progress promise_archetypes(Walk& walk, Declaration* instance) {
		std::shared_ptr<EarlyCheck> check = early_check_of(walk.executor.program_info->names, instance->generic);
		return check != nullptr ? ensure_promised(walk, instance->generic, *check) : Progress::DONE;
	}

	bool early_check_failed(NameRegistry& names, const Declaration* generic) {
		std::shared_ptr<EarlyCheck> check = early_check_of(names, generic);
		return check != nullptr && check->done && check->failed;
	}

	Declaration* early_instance(NameRegistry& names, const Declaration* generic) {
		std::shared_ptr<EarlyCheck> check = early_check_of(names, generic);
		std::scoped_lock<std::mutex> lock(names.mutex);
		return check != nullptr ? check->instance : nullptr;
	}

	void finish_early_check(NameRegistry& names, const Declaration* instance, bool failed) {
		std::shared_ptr<EarlyCheck> check = early_check_of(names, instance->generic);
		if (check != nullptr) {
			std::scoped_lock<std::mutex> lock(names.mutex);
			check->done = true;
			check->failed = failed;
		}
	}

	Progress prove_constraints(Walk& walk, ast::Node* where, Declaration* generic, Declaration* instance) {
		NameRegistry& names = walk.executor.program_info->names;
		const Declaration* owner = owner_of(instance);
		std::shared_ptr<EarlyCheck> have = owner != nullptr ? early_check_of(names, owner) : nullptr;
		if (have == nullptr) {
			return Progress::DONE;
		}
		Progress promised = ensure_promised(walk, owner, *have);
		if (promised != Progress::DONE) {
			return promised;
		}
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			if (ConstraintState::SATISFIED == instance->constraint_state) {
				return Progress::DONE;
			}
		}
		std::map<std::string, Argument> parameters = arguments_of(generic, instance);
		Walk inside = walk_in(walk, generic);
		for (const auto& [name, parameter] : generic_parameters(generic)) {
			inside.locals.push_back(intern(name));
		}
		Analysis analysis{ walk };
		std::vector<std::string> lines;
		for (const auto& [name, parameter] : generic_parameters(generic)) {
			if (!generic_parameter_is_constrained(names, generic, parameter)) {
				continue;
			}
			Proof proof;
			Progress progress = prove_expression(analysis, inside, generic, parameters, parameter->children[1], &parameters[name], *have, proof);
			if (progress != Progress::DONE) {
				return progress;
			}
			for (const std::string& missing : proof.missing) {
				// T needs Integer(T), or U = T needs Integer(T) when the names differ
				lines.push_back(parameters[name].text == name ? std::format("{} needs {}", name, missing)
					: std::format("{} = {} needs {}", name, parameters[name].text, missing));
			}
		}
		if (ast::Node* where_clause = where_clause_of(generic); where_clause != nullptr && lines.empty()) {
			Proof proof;
			Progress progress = prove_expression(analysis, inside, generic, parameters, where_clause, nullptr, *have, proof);
			if (progress != Progress::DONE) {
				return progress;
			}
			for (const std::string& missing : proof.missing) {
				lines.push_back(std::format("its where clause needs {}", missing));
			}
		}
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			instance->constraint_state = lines.empty() ? ConstraintState::SATISFIED : ConstraintState::UNSATISFIED;
			instance->unsatisfied = lines;
		}
		if (lines.empty()) {
			return Progress::DONE;
		}
		std::string message = std::format("{} needs what {}'s constraints don't promise", text_of(instance->name), text_of(owner->name));
		for (const std::string& line : lines) {
			message += "\n    " + line;
		}
		report_error(ErrorCode::E4033, walk.file_path, where->value.line_number, where->value.column_number, message);
		return Progress::FAILED;
	}
}
