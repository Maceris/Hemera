#include <format>
#include <mutex>
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
 * Constraints on generics (docs/types.md, Constraints): #constraint functions, which generics name in
 * their generic lists (T: Equatable && Ordered) and where clauses, checked where an instance is made,
 * by running each constraint at compile time with the instance's arguments.
 */
namespace hemera {
	namespace {
		bool is_text(InternedString value, std::string_view text) {
			return value != nullptr && std::string_view(*value) == text;
		}

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

		// A constraint expression as it's written, for messages.
		std::string expression_text(const ast::Node* node) {
			if (node == nullptr) {
				return "";
			}
			if (is_combination(node) && node->children.size() == 2) {
				return std::format("{} {} {}", expression_text(node->children[0]),
					TokenType::OPERATOR_AND == node->value.type ? "&&" : "||", expression_text(node->children[1]));
			}
			if (ast::NodeType::PAREN_GROUP == node->node_type && node->children.size() == 1) {
				return std::format("({})", expression_text(node->children[0]));
			}
			std::string text = text_of(node->value.value);
			for (size_t i = 0; i < node->children.size(); ++i) {
				const ast::Node* child = node->children[i];
				if (ast::NodeType::DOT_ACCESS == child->node_type && i + 1 < node->children.size()) {
					text += "." + text_of(node->children[++i]->value.value);
				}
			}
			std::vector<ast::Node*> arguments;
			if (call_arguments(node, arguments)) {
				text += "(";
				for (size_t i = 0; i < arguments.size(); ++i) {
					text += (i > 0 ? ", " : "") + expression_text(arguments[i]);
				}
				text += ")";
			}
			return text;
		}

		// What part of a constraint expression found: satisfied, or not, with why.
		struct Outcome {
			bool satisfied = true;
			std::vector<std::string> reasons;
		};

		// Checking one instance's constraints, in a walk of the generic's own file with its parameters bound.
		struct ConstraintCheck {
			Walk& caller;
			ast::Node* where;
			InternedString package_path;
			FileInfo* file;
			Walk inside;
		};

		void report_in_generic(ConstraintCheck& check, const ast::Node* node, std::string what) {
			report_at(ErrorCode::E4014, check.inside.file_path, &check.inside.executor.program_info->made_nodes, node, std::move(what));
		}

		/*
		 * A constraint argument: a generic parameter's type or value, or a type or constant written
		 * in place, like Convertible(T, u64) or AtLeastOne(capacity * 2).
		 */
		Progress argument_of(ConstraintCheck& check, ast::Node* node, TypeInfo*& type, ConstantValue& value) {
			type = nullptr;
			if (ast::NodeType::IDENTIFIER == node->node_type && node->children.empty()) {
				const std::string name = text_of(node->value.value);
				auto bound_type = check.inside.generic_types.find(name);
				if (bound_type != check.inside.generic_types.end()) {
					type = bound_type->second;
					return Progress::DONE;
				}
				auto bound_value = check.inside.generic_values.find(name);
				if (bound_value != check.inside.generic_values.end()) {
					value = bound_value->second;
					return Progress::DONE;
				}
			}
			if (ast::NodeType::LITERAL != node->node_type && ast::NodeType::BINARY_OPERATOR != node->node_type
				&& ast::NodeType::UNARY_OPERATOR != node->node_type && ast::NodeType::ENUM_SHORTHAND != node->node_type) {
				// Its names looked up first, so type_of can follow them, like Point in Equatable(Point)
				Progress named = walk_names(check.inside, node, Need::DECLARED);
				if (named != Progress::DONE) {
					return named;
				}
				Progress progress = type_of(check.inside, node, Need::DECLARED, type);
				if (progress == Progress::DONE && type != nullptr) {
					// mut Config: given with mut
					for (const ast::Node* child : node->children) {
						if (ast::NodeType::MUTABLE == child->node_type) {
							type = mutable_argument(check.inside, type);
						}
					}
					return Progress::DONE;
				}
				if (progress == Progress::PARKED) {
					return progress;
				}
				type = nullptr;
			}
			return evaluate_in(check.inside, node, value);
		}

		// One constraint, named alone (constraining subject) or called with its arguments.
		Progress evaluate_call(ConstraintCheck& check, ast::Node* node, const std::string* subject, Outcome& outcome) {
			NameRegistry& names = check.caller.executor.program_info->names;
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
					? require_qualified(check.inside, node, node->value.value, qualifier, Need::DECLARED, head_was_package)
					: require(check.inside, node, node->value.value, Need::DECLARED);
				if (named != Progress::DONE) {
					return named;
				}
			}
			Declaration* constraint = constraint_named(names, check.package_path, check.file, node);
			if (constraint == nullptr) {
				report_in_generic(check, node, std::format("{} isn't a #constraint function", expression_text(node)));
				return Progress::FAILED;
			}
			ConstraintRun asked;
			asked.constraint = constraint;
			std::vector<ast::Node*> arguments;
			if (!call_arguments(node, arguments)) {
				// T: Equatable is Equatable(T)
				if (subject == nullptr) {
					report_in_generic(check, node, std::format("{} needs its arguments here, like {}(T)",
						text_of(constraint->name), text_of(constraint->name)));
					return Progress::FAILED;
				}
				auto bound = check.inside.generic_types.find(*subject);
				asked.types.push_back(bound != check.inside.generic_types.end() ? bound->second : nullptr);
				asked.values.push_back({});
			}
			for (ast::Node* argument : arguments) {
				TypeInfo* type = nullptr;
				ConstantValue value;
				Progress progress = argument_of(check, argument, type, value);
				if (progress != Progress::DONE) {
					return progress;
				}
				asked.types.push_back(type);
				asked.values.push_back(type != nullptr ? ConstantValue{} : value);
			}
			const ConstraintRun* result = nullptr;
			Progress progress = run_constraint(check.caller, check.where, asked, result);
			if (progress != Progress::DONE) {
				return progress;
			}
			outcome.satisfied = result->unsatisfied.empty();
			for (const std::string& reason : result->unsatisfied) {
				outcome.reasons.push_back(std::format("{}: {}", text_of(constraint->name), reason));
			}
			return Progress::DONE;
		}

		/*
		 * A constraint expression, like a short-circuiting boolean one: A && B stops at the first that
		 * isn't satisfied, and A || B at the first that is, keeping why each alternative wasn't.
		 */
		Progress evaluate(ConstraintCheck& check, ast::Node* node, const std::string* subject, Outcome& outcome) {
			if (ast::NodeType::PAREN_GROUP == node->node_type && node->children.size() == 1) {
				return evaluate(check, node->children[0], subject, outcome);
			}
			if (is_combination(node) && node->children.size() == 2) {
				Outcome left;
				Progress progress = evaluate(check, node->children[0], subject, left);
				if (progress != Progress::DONE) {
					return progress;
				}
				const bool both = TokenType::OPERATOR_AND == node->value.type;
				if (left.satisfied != both) {
					outcome = left;
					return Progress::DONE;
				}
				Outcome right;
				progress = evaluate(check, node->children[1], subject, right);
				if (progress != Progress::DONE) {
					return progress;
				}
				outcome.satisfied = right.satisfied;
				outcome.reasons = both ? right.reasons : left.reasons;
				if (!both) {
					outcome.reasons.insert(outcome.reasons.end(), right.reasons.begin(), right.reasons.end());
				}
				return Progress::DONE;
			}
			return evaluate_call(check, node, subject, outcome);
		}

		std::string instance_name(const Declaration* instance) {
			return text_of(instance->name);
		}

		void report_unsatisfied(Walk& walk, ast::Node* where, const Declaration* instance, const std::vector<std::string>& lines) {
			std::string message = std::format("{} can't be made", instance_name(instance));
			for (const std::string& line : lines) {
				message += "\n    " + line;
			}
			report_at(ErrorCode::E4032, walk.file_path, &walk.executor.program_info->made_nodes, where, message);
		}
	}

	Progress bind_derived(Walk& walk, ast::Node* where, Declaration* generic, std::map<std::string, TypeInfo*>& bound,
		std::map<std::string, ConstantValue>& bound_values) {

		ast::Node* value = generic_node(generic);
		if (value == nullptr) {
			return Progress::DONE;
		}
		std::vector<ast::Node*> derived;
		std::vector<std::string> names;
		for (ast::Node* child : value->children) {
			if (ast::NodeType::GENERIC_TAG != child->node_type) {
				continue;
			}
			for (ast::Node* parameter : child->children) {
				const bool named = ast::NodeType::COLON == parameter->node_type && !parameter->children.empty();
				names.push_back(text_of(named ? parameter->children[0]->value.value : parameter->value.value));
				if (ast::NodeType::DERIVED_PARAMETER == parameter->node_type && !parameter->children.empty()
					&& !bound.contains(names.back()) && !bound_values.contains(names.back())) {
					derived.push_back(parameter);
				}
			}
		}
		// Each pass works out those whose expressions only use what's bound, until all are
		while (!derived.empty()) {
			bool any = false;
			for (auto iter = derived.begin(); iter != derived.end();) {
				ast::Node* parameter = *iter;
				// Every other parameter it names has to be bound first
				bool ready = true;
				std::vector<const ast::Node*> pending{ parameter->children[0] };
				while (!pending.empty() && ready) {
					const ast::Node* node = pending.back();
					pending.pop_back();
					const std::string name = text_of(node->value.value);
					if (ast::NodeType::IDENTIFIER == node->node_type || ast::NodeType::TYPE == node->node_type) {
						for (ast::Node* other : derived) {
							if (other != parameter && text_of(other->value.value) == name) {
								ready = false;
							}
						}
						if (name == text_of(parameter->value.value)) {
							report_error(ErrorCode::E4007, file_path_of(generic->package_path, generic->file_name), parameter->value.line_number,
								parameter->value.column_number, std::format("{} is worked out from itself", name));
							return Progress::FAILED;
						}
					}
					for (const ast::Node* child : node->children) {
						pending.push_back(child);
					}
				}
				if (!ready) {
					++iter;
					continue;
				}
				Walk inside{
					walk.executor,
					generic->package_path,
					generic->file_name,
					generic->file,
					nullptr,
					nullptr,
					file_path_of(generic->package_path, generic->file_name),
					{},
					{},
					{},
				};
				std::string key = std::format("{}", static_cast<const void*>(parameter));
				for (const std::string& name : names) {
					inside.locals.push_back(intern(name));
					auto type = bound.find(name);
					if (type != bound.end()) {
						inside.generic_types[name] = type->second;
						key += std::format(" {}", static_cast<const void*>(get_base_type_or_alias(type->second)));
					}
					auto constant = bound_values.find(name);
					if (constant != bound_values.end()) {
						inside.generic_values[name] = constant->second;
						key += " =" + constant_text(constant->second);
					}
				}
				TypeInfo* type = nullptr;
				ConstantValue constant;
				Progress progress = evaluate_derived(inside, parameter->children[0], key, type, constant);
				if (progress != Progress::DONE) {
					return progress;
				}
				if (type != nullptr) {
					bound[text_of(parameter->value.value)] = type;
				}
				else {
					bound_values[text_of(parameter->value.value)] = constant;
				}
				iter = derived.erase(iter);
				any = true;
			}
			if (!any) {
				ast::Node* first = derived.front();
				report_error(ErrorCode::E4007, file_path_of(generic->package_path, generic->file_name), first->value.line_number,
					first->value.column_number, std::format("{}'s derived parameters are worked out from each other", text_of(generic->name)));
				return Progress::FAILED;
			}
		}
		(void)where;
		return Progress::DONE;
	}

	bool is_satisfies_call(Walk& walk, const ast::Node* node) {
		if (ast::NodeType::IDENTIFIER != node->node_type || !is_text(node->value.value, "compiler") || node->children.size() < 3
			|| ast::NodeType::DOT_ACCESS != node->children[0]->node_type || !is_text(node->children[1]->value.value, "satisfies")
			|| ast::NodeType::PAREN_GROUP != node->children[2]->node_type) {
			return false;
		}
		InternedString package = walk.file != nullptr ? imported_package(walk.file, node->value.value) : nullptr;
		return package != nullptr && std::string_view(*package).ends_with("compiler");
	}

	bool is_compiler_function(const Declaration* declaration, std::string_view name) {
		return declaration != nullptr && is_text(declaration->name, name) && declaration->package_path != nullptr
			&& std::string_view(*declaration->package_path).ends_with("compiler")
			&& std::string_view(*declaration->package_path).starts_with("<base>");
	}

	Progress evaluate_satisfies(Walk& walk, ast::Node* node, ConstantValue& result) {
		std::vector<ast::Node*> arguments;
		call_arguments(node, arguments);
		return evaluate_satisfies(walk, node, arguments, result);
	}

	Progress evaluate_satisfies(Walk& walk, ast::Node* where, const std::vector<ast::Node*>& arguments, ConstantValue& result) {
		if (arguments.size() != 1) {
			report_at(ErrorCode::E4018, walk.file_path, &walk.executor.program_info->made_nodes, where,
				"compiler.satisfies takes one constraint expression, like Hashable(Point) && Ordered(Point)");
			return Progress::FAILED;
		}
		ConstraintCheck check{ walk, where, walk.package_path, walk.file, walk };
		Outcome outcome;
		Progress progress = evaluate(check, arguments[0], nullptr, outcome);
		if (progress != Progress::DONE) {
			return progress;
		}
		result.kind = ConstantValue::Kind::BOOLEAN;
		result.boolean = outcome.satisfied;
		return Progress::DONE;
	}

	// Whether a function's declaration has a directive after its name, like #constraint or #macro.
	static bool function_declared_with(const Declaration* declaration, std::string_view directive) {
		if (declaration == nullptr || DeclarationKind::FUNCTION != declaration->kind || declaration->node == nullptr
			|| declaration->node->children.empty()) {
			return false;
		}
		ast::Node* names_node = declaration->node->children[0];
		std::vector<ast::Node*> names{ names_node };
		if (ast::NodeType::LIST == names_node->node_type) {
			names.assign(names_node->children.begin(), names_node->children.end());
		}
		for (ast::Node* name : names) {
			if (name->value.value == nullptr || declaration->name == nullptr || *name->value.value != *declaration->name) {
				continue;
			}
			for (ast::Node* child : name->children) {
				if (ast::NodeType::DIRECTIVE == child->node_type && is_text(child->value.value, directive)) {
					return true;
				}
			}
		}
		return false;
	}

	bool is_constraint_function(const Declaration* declaration) {
		return function_declared_with(declaration, "#constraint");
	}

	bool is_macro_function(const Declaration* declaration) {
		return function_declared_with(declaration, "#macro");
	}

	Declaration* constraint_named(NameRegistry& names, const Declaration* context, const ast::Node* node) {
		return context != nullptr ? constraint_named(names, context->package_path, context->file, node) : nullptr;
	}

	Declaration* constraint_named(NameRegistry& names, InternedString package_path, FileInfo* file, const ast::Node* node) {
		if (node == nullptr || package_path == nullptr || node->value.value == nullptr
			|| (ast::NodeType::IDENTIFIER != node->node_type && ast::NodeType::TYPE != node->node_type)) {
			return nullptr;
		}
		// pkg.Name: the package's local name, then a DOT_ACCESS and the name
		InternedString head = node->value.value;
		InternedString name = head;
		bool qualified = false;
		for (size_t i = 0; i + 1 < node->children.size(); ++i) {
			if (ast::NodeType::DOT_ACCESS == node->children[i]->node_type && ast::NodeType::IDENTIFIER == node->children[i + 1]->node_type) {
				name = node->children[i + 1]->value.value;
				qualified = true;
				break;
			}
		}
		std::vector<InternedString> packages;
		if (qualified) {
			InternedString package = file != nullptr ? imported_package(file, head) : nullptr;
			if (package == nullptr) {
				return nullptr;
			}
			packages.push_back(package);
		}
		else {
			// The generic's own package, then what its file imports, which a name can come from unqualified
			packages.push_back(package_path);
			if (file != nullptr) {
				std::scoped_lock<std::mutex> imports_lock(file->imports_mutex);
				for (ImportInfo* import : file->imports) {
					if (import != nullptr && import->resolved_path != nullptr) {
						packages.push_back(import->resolved_path);
					}
				}
			}
		}
		std::scoped_lock<std::mutex> lock(names.mutex);
		for (InternedString package : packages) {
			auto iter = names.declarations.find(std::make_pair(package, name));
			if (iter != names.declarations.end() && is_constraint_function(iter->second)) {
				return iter->second;
			}
		}
		return nullptr;
	}

	bool generic_parameter_is_constrained(NameRegistry& names, const Declaration* generic, const ast::Node* parameter) {
		if (ast::NodeType::COLON != parameter->node_type || parameter->children.size() < 2) {
			return false;
		}
		const ast::Node* what = parameter->children[1];
		if (is_combination(what) || ast::NodeType::PAREN_GROUP == what->node_type) {
			return true;
		}
		return constraint_named(names, generic, what) != nullptr;
	}

	Progress check_constraints(Walk& walk, ast::Node* where, Declaration* generic, Declaration* instance, bool quiet) {
		if (generic == nullptr || instance == nullptr) {
			return Progress::DONE;
		}
		/*
		 * In a checked body, with its archetypes: whether its own constraints promise these
		 * (docs/types.md, Checked Bodies). The early instance itself has only what they promise.
		 */
		if (is_early_instance(instance)) {
			return Progress::DONE;
		}
		if (has_archetype_arguments(instance)) {
			return quiet ? Progress::DONE : prove_constraints(walk, where, generic, instance);
		}
		NameRegistry& names = walk.executor.program_info->names;
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			if (ConstraintState::SATISFIED == instance->constraint_state) {
				return Progress::DONE;
			}
			if (ConstraintState::UNSATISFIED == instance->constraint_state) {
				if (!quiet) {
					report_unsatisfied(walk, where, instance, instance->unsatisfied);
				}
				return Progress::FAILED;
			}
		}
		ast::Node* value = generic_node(generic);
		if (value == nullptr) {
			return Progress::DONE;
		}
		// The parameters' names, the constraints on each, and the where clause
		std::vector<std::string> parameter_names;
		std::vector<std::pair<std::string, ast::Node*>> constrained;
		ast::Node* where_clause = nullptr;
		for (ast::Node* child : value->children) {
			if (ast::NodeType::WHERE_CLAUSE == child->node_type && !child->children.empty()) {
				where_clause = child->children[0];
			}
			if (ast::NodeType::GENERIC_TAG != child->node_type) {
				continue;
			}
			for (ast::Node* parameter : child->children) {
				const bool named = ast::NodeType::COLON == parameter->node_type && !parameter->children.empty();
				const std::string name = text_of(named ? parameter->children[0]->value.value : parameter->value.value);
				parameter_names.push_back(name);
				if (generic_parameter_is_constrained(names, generic, parameter)) {
					constrained.emplace_back(name, parameter->children[1]);
				}
			}
		}
		if (constrained.empty() && where_clause == nullptr) {
			std::scoped_lock<std::mutex> lock(names.mutex);
			instance->constraint_state = ConstraintState::SATISFIED;
			return Progress::DONE;
		}
		ConstraintCheck check{
			walk,
			where,
			generic->package_path,
			generic->file,
			Walk{
				walk.executor,
				generic->package_path,
				generic->file_name,
				generic->file,
				nullptr,
				nullptr,
				file_path_of(generic->package_path, generic->file_name),
				{},
				{},
				{},
			},
		};
		for (size_t i = 0; i < parameter_names.size() && i < instance->generic_arguments.size(); ++i) {
			if (instance->generic_arguments[i] != nullptr) {
				check.inside.generic_types[parameter_names[i]] = instance->generic_arguments[i];
			}
			else if (i < instance->generic_values.size()) {
				check.inside.generic_values[parameter_names[i]] = instance->generic_values[i];
			}
			check.inside.locals.push_back(intern(parameter_names[i]));
		}
		// Each parameter's constraints, then the where clause once they hold
		std::vector<std::string> lines;
		for (const auto& [name, expression] : constrained) {
			Outcome outcome;
			Progress progress = evaluate(check, expression, &name, outcome);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (!outcome.satisfied) {
				auto bound = check.inside.generic_types.find(name);
				const std::string given = bound != check.inside.generic_types.end() && bound->second != nullptr ? to_string(bound->second) : name;
				lines.push_back(std::format("{} = {} isn't {}", name, given, expression_text(expression)));
				for (const std::string& reason : outcome.reasons) {
					lines.push_back("    " + reason);
				}
			}
		}
		if (lines.empty() && where_clause != nullptr) {
			Outcome outcome;
			Progress progress = evaluate(check, where_clause, nullptr, outcome);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (!outcome.satisfied) {
				lines.push_back(std::format("where {} isn't satisfied", expression_text(where_clause)));
				for (const std::string& reason : outcome.reasons) {
					lines.push_back("    " + reason);
				}
			}
		}
		{
			std::scoped_lock<std::mutex> lock(names.mutex);
			instance->constraint_state = lines.empty() ? ConstraintState::SATISFIED : ConstraintState::UNSATISFIED;
			instance->unsatisfied = lines;
		}
		if (!lines.empty()) {
			if (!quiet) {
				report_unsatisfied(walk, where, instance, lines);
			}
			return Progress::FAILED;
		}
		return Progress::DONE;
	}
}
