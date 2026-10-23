#include <algorithm>
#include <format>
#include <memory>

#include "error/reporting.h"
#include "front_end/checking.h"
#include "front_end/front_end.h"
#include "front_end/walk.h"
#include "util/logger.h"

namespace hemera {

	/*
	 * Works out what each declaration is, and its type information, once the name walker has
	 * resolved the names it uses (docs/types.md). The walker records what each name resolved to
	 * in walk.bindings, so this only follows those.
	 */

	static bool is_text(InternedString value, std::string_view text) {
		return value != nullptr && std::string_view(*value) == text;
	}

	// = in a definition, a named argument, a field's or parameter's default. Operators have no text.
	static bool is_assign(const ast::Node* node) {
		return TokenType::OPERATOR_ASSIGN == node->value.type;
	}

	static bool is_separator(const ast::Node* node) {
		return ast::NodeType::COLON == node->node_type
			|| (ast::NodeType::IDENTIFIER == node->node_type && is_assign(node));
	}

	static bool has_child(const ast::Node* node, ast::NodeType type) {
		for (const ast::Node* child : node->children) {
			if (type == child->node_type) {
				return true;
			}
		}
		return false;
	}

	static std::string name_text(InternedString name) {
		return name != nullptr ? std::string(std::string_view(*name)) : std::string("_");
	}

	ast::Node* definition_value(ast::Node* definition) {
		for (size_t i = 1; i < definition->children.size(); ++i) {
			if (is_separator(definition->children[i])) {
				return i + 1 < definition->children.size() ? definition->children[i + 1] : nullptr;
			}
		}
		return nullptr;
	}

	// The type a definition declares, between its name and separator, like u8 in C : u8 : 5.
	static ast::Node* definition_declared_type(ast::Node* definition) {
		if (definition->children.size() > 1 && !is_separator(definition->children[1])) {
			return definition->children[1];
		}
		return nullptr;
	}

	// A function with a body: its signature, then the BLOCK, after the separator.
	static bool has_body(ast::Node* definition) {
		bool after_value = false;
		for (size_t i = 1; i < definition->children.size(); ++i) {
			ast::Node* child = definition->children[i];
			if (after_value && ast::NodeType::BLOCK == child->node_type) {
				return true;
			}
			if (ast::NodeType::FUNCTION == child->node_type) {
				after_value = true;
			}
		}
		return false;
	}

	void classify_declaration(NameRegistry& names, Declaration* declaration) {
		ast::Node* value = definition_value(declaration->node);
		ast::Node* declared = definition_declared_type(declaration->node);
		DeclarationKind kind = DeclarationKind::VALUE;
		TypeInfo* type = nullptr;
		if (value != nullptr) {
			const ast::NodeType value_type = value->node_type;
			if (ast::NodeType::STRUCT == value_type || ast::NodeType::UNION == value_type) {
				if (has_child(value, ast::NodeType::GENERIC_TAG) && declaration->generic == nullptr) {
					kind = DeclarationKind::GENERIC_TYPE;
				}
				else {
					kind = DeclarationKind::TYPE;
					type = ast::NodeType::STRUCT == value_type
						? static_cast<TypeInfo*>(make_type<TypeInfoStruct>(names, declaration->name))
						: static_cast<TypeInfo*>(make_type<TypeInfoUnion>(names, declaration->name));
					if (ast::NodeType::STRUCT == value_type && declaration->generic != nullptr) {
						static_cast<TypeInfoStruct*>(type)->instance = declaration;
					}
					/*
					 * #secret is known from when the type is declared, since what only points to it, like a
					 * ptr[Key] parameter, may be checked before its body is (docs/memory.md, Secrets)
					 */
					if (ast::NodeType::STRUCT == value_type) {
						for (const ast::Node* child : value->children) {
							if (ast::NodeType::DIRECTIVE == child->node_type && child->value.value != nullptr
								&& std::string_view(*child->value.value) == "#secret") {
								static_cast<TypeInfoStruct*>(type)->is_secret = true;
							}
						}
					}
				}
			}
			else if (ast::NodeType::ENUM == value_type) {
				kind = DeclarationKind::TYPE;
				type = make_type<TypeInfoEnum>(names, declaration->name);
			}
			else if ((ast::NodeType::KEYWORD_ALIAS == value_type || ast::NodeType::KEYWORD_DISTINCT == value_type)
				&& has_child(value, ast::NodeType::GENERIC_TAG) && declaration->generic == nullptr) {
				// A generic alias, whose instances alias what it names with their arguments (docs/types.md)
				kind = DeclarationKind::GENERIC_TYPE;
			}
			else if (ast::NodeType::KEYWORD_ALIAS == value_type
				|| ast::NodeType::KEYWORD_DISTINCT == value_type) {
				kind = DeclarationKind::TYPE;
				type = make_type<TypeInfoAlias>(names, declaration->name,
					ast::NodeType::KEYWORD_DISTINCT == value_type);
				// #secret, known from the start like a struct's; alias_body checks it's on a distinct alias
				for (const ast::Node* part : declaration->node->children) {
					if (ast::NodeType::KEYWORD_ALIAS != part->node_type) {
						continue;
					}
					for (const ast::Node* directive : part->children) {
						if (ast::NodeType::DIRECTIVE == directive->node_type && directive->value.value != nullptr
							&& std::string_view(*directive->value.value) == "#secret" && ast::NodeType::KEYWORD_DISTINCT == value_type) {
							static_cast<TypeInfoAlias*>(type)->is_secret = true;
						}
					}
				}
			}
			else if (ast::NodeType::FUNCTION == value_type) {
				if (has_body(declaration->node)) {
					kind = DeclarationKind::FUNCTION;
				}
				else {
					// A function type, like Handler :: fn(int) -> bool: a pointer, whatever it's of
					kind = DeclarationKind::TYPE;
					type = make_type<TypeInfoFunction>(names);
				}
			}
		}
		if (declared != nullptr && ast::NodeType::FUNCTION == declared->node_type) {
			kind = DeclarationKind::FUNCTION;
		}
		declaration->kind = kind;
		declaration->type_value = type;
		if (type != nullptr) {
			names.type_declarations[type] = declaration;
		}
	}

	static Progress type_error(Walk& walk, ErrorCode code, ast::Node* where, std::string details) {
		report_at(code, walk.file_path, &walk.executor.program_info->made_nodes, where,
			std::move(details));
		return Progress::FAILED;
	}

	// A type made from others, like ptr[int] or int[4], the same object each time it's asked for.
	template<typename Make>
	static TypeInfo* derived_type(Walk& walk, const std::string& key, Make make) {
		NameRegistry& names = walk.executor.program_info->names;
		std::scoped_lock<std::mutex> lock(names.types_mutex);
		auto iter = names.derived_types.find(key);
		if (iter != names.derived_types.end()) {
			return iter->second;
		}
		TypeInfo* type = make();
		names.owned_types.emplace_back(type);
		names.derived_types[key] = type;
		return type;
	}

	TypeInfo* pointer_to(Walk& walk, TypeInfo* base, bool is_mutable, bool is_relative, size_t size) {
		return derived_type(walk,
			std::format("ptr {} {} {} {}", static_cast<const void*>(base), is_mutable, is_relative, size),
			[&] { return new TypeInfoPointer(base, is_relative, is_mutable, size); });
	}

	bool is_mutable_argument(TypeInfo const* type) {
		return type != nullptr && TypeInfoVariant::ALIAS == type->variant && static_cast<TypeInfoAlias const*>(type)->mutable_argument;
	}

	TypeInfo* mutable_argument(Walk& walk, TypeInfo* base) {
		if (base == nullptr || is_mutable_argument(base)) {
			return base;
		}
		return derived_type(walk, std::format("mut {}", static_cast<const void*>(base)), [&] {
			auto alias = new TypeInfoAlias(intern("mut " + to_string(base)), false);
			alias->base_type = base;
			alias->mutable_argument = true;
			if (base->complete) {
				lay_out_alias(alias);
			}
			return alias;
		});
	}

	void bind_generic_type(Walk& walk, const std::string& name, TypeInfo* argument) {
		if (is_mutable_argument(argument)) {
			walk.generic_types[name] = static_cast<TypeInfoAlias*>(argument)->base_type;
			walk.generic_mutable.insert(name);
			return;
		}
		walk.generic_types[name] = argument;
		walk.generic_mutable.erase(name);
	}

	// Whether a type node names a generic parameter given with mut, like T in ptr[T] in SharedPtr[mut Buffer].
	static bool names_mutable_parameter(const Walk& walk, const ast::Node* node) {
		return (ast::NodeType::TYPE == node->node_type || ast::NodeType::IDENTIFIER == node->node_type) && node->value.value != nullptr
			&& walk.generic_mutable.contains(std::string(std::string_view(*node->value.value)));
	}

	/*
	 * Whether a generic struct's parameter is only ever pointed to in its fields, like T in a struct holding
	 * a ptr[T]: then an instance given mut T has the same layout as one given T.
	 */
	static bool used_by_value(const ast::Node* node, std::string_view name, bool under_pointer) {
		if ((ast::NodeType::TYPE == node->node_type || ast::NodeType::IDENTIFIER == node->node_type) && node->value.value != nullptr) {
			const std::string_view text(*node->value.value);
			if (text == name && !under_pointer) {
				return true;
			}
			const bool pointer = text == "ptr" || text.starts_with("relptr");
			for (const ast::Node* child : node->children) {
				if (used_by_value(child, name, under_pointer || (pointer && ast::NodeType::GENERIC_TAG == child->node_type))) {
					return true;
				}
			}
			return false;
		}
		for (const ast::Node* child : node->children) {
			if (used_by_value(child, name, under_pointer)) {
				return true;
			}
		}
		return false;
	}

	static InternedString generic_parameter_name(const ast::Node* parameter);

	static bool only_pointed_to(const Declaration* generic, std::string_view name) {
		ast::Node* value = generic_node(generic);
		if (value == nullptr || ast::NodeType::STRUCT != value->node_type) {
			return false;
		}
		for (const ast::Node* child : value->children) {
			if (ast::NodeType::DEFINITION == child->node_type) {
				for (size_t i = 1; i < child->children.size(); ++i) {
					if (used_by_value(child->children[i], name, false)) {
						return false;
					}
				}
			}
			else if (ast::NodeType::USING == child->node_type) {
				return false;
			}
		}
		return true;
	}

	bool converts_to_read_only(TypeInfo const* from, TypeInfo const* to) {
		from = get_base_type_or_alias(from);
		to = get_base_type_or_alias(to);
		if (from == nullptr || to == nullptr || from == to || TypeInfoVariant::STRUCT != from->variant
			|| TypeInfoVariant::STRUCT != to->variant) {
			return false;
		}
		const Declaration* a = static_cast<TypeInfoStruct const*>(from)->instance;
		const Declaration* b = static_cast<TypeInfoStruct const*>(to)->instance;
		if (a == nullptr || b == nullptr || a->generic != b->generic || a->generic_arguments.size() != b->generic_arguments.size()) {
			return false;
		}
		std::vector<std::string> names;
		ast::Node* value = generic_node(a->generic);
		for (const ast::Node* child : value != nullptr ? value->children : MyVector<ast::Node*>{}) {
			if (ast::NodeType::GENERIC_TAG == child->node_type) {
				for (const ast::Node* parameter : child->children) {
					names.push_back(name_text(generic_parameter_name(parameter)));
				}
			}
		}
		bool loses_mut = false;
		for (size_t i = 0; i < a->generic_arguments.size(); ++i) {
			TypeInfo* given = a->generic_arguments[i];
			TypeInfo* wanted = b->generic_arguments[i];
			if (given == nullptr || wanted == nullptr) {
				// Values: the same
				if (given != wanted || i >= a->generic_values.size() || i >= b->generic_values.size()
					|| constant_text(a->generic_values[i]) != constant_text(b->generic_values[i])) {
					return false;
				}
				continue;
			}
			if (!same_type(given, wanted)) {
				return false;
			}
			if (is_mutable_argument(given) == is_mutable_argument(wanted)) {
				continue;
			}
			// Only from mut to without it, and only for a parameter that's only pointed to
			if (!is_mutable_argument(given) || i >= names.size() || !only_pointed_to(a->generic, names[i])) {
				return false;
			}
			loses_mut = true;
		}
		return loses_mut;
	}

	TypeInfo* vector_of(Walk& walk, TypeInfo* element, size_t count) {
		return derived_type(walk, std::format("vector {} {}", static_cast<const void*>(element), count),
			[&] { return new TypeInfoVector(element, count, false); });
	}

	TypeInfo* array_of(Walk& walk, TypeInfo* element, ArrayType array_type, size_t count) {
		return derived_type(walk,
			std::format("array {} {} {}", static_cast<const void*>(element), static_cast<int>(array_type), count),
			[&] { return new TypeInfoArray(element, array_type, count); });
	}

	Progress type_of(Walk& walk, ast::Node* node, Need need, TypeInfo*& result);

	// An instance of a generic type, made the first time it's asked for, resolved when need asks.
	static InternedString generic_parameter_name(const ast::Node* parameter);

	Progress instance_type(Walk& walk, ast::Node* where, Declaration* generic,
		const std::vector<TypeInfo*>& arguments, Need need, TypeInfo*& result, const std::vector<ConstantValue>& values) {

		ast::Node* value = definition_value(generic->node);
		size_t parameters = 0;
		std::vector<ast::Node*> parameter_nodes;
		for (ast::Node* child : value->children) {
			if (ast::NodeType::GENERIC_TAG == child->node_type) {
				parameters = child->children.size();
				parameter_nodes.assign(child->children.begin(), child->children.end());
			}
		}
		/*
		 * Derived parameters the use doesn't give, like E in Box[C, E = element_of(C)], worked out
		 * from those it does (docs/types.md, Derived Parameters)
		 */
		if (arguments.size() < parameters) {
			std::map<std::string, TypeInfo*> bound;
			std::map<std::string, ConstantValue> bound_values;
			for (size_t i = 0; i < arguments.size() && i < parameter_nodes.size(); ++i) {
				const std::string name = name_text(generic_parameter_name(parameter_nodes[i]));
				if (arguments[i] != nullptr) {
					bound[name] = arguments[i];
				}
				else if (i < values.size()) {
					bound_values[name] = values[i];
				}
			}
			bool all_derived = true;
			for (size_t i = arguments.size(); i < parameter_nodes.size(); ++i) {
				all_derived = all_derived && ast::NodeType::DERIVED_PARAMETER == parameter_nodes[i]->node_type;
			}
			if (all_derived) {
				Progress derived = bind_derived(walk, where, generic, bound, bound_values);
				if (derived != Progress::DONE) {
					return derived;
				}
				std::vector<TypeInfo*> completed = arguments;
				std::vector<ConstantValue> completed_values = values;
				completed_values.resize(arguments.size());
				for (size_t i = arguments.size(); i < parameter_nodes.size(); ++i) {
					const std::string name = name_text(generic_parameter_name(parameter_nodes[i]));
					auto type = bound.find(name);
					completed.push_back(type != bound.end() ? type->second : nullptr);
					auto constant = bound_values.find(name);
					completed_values.push_back(constant != bound_values.end() ? constant->second : ConstantValue{});
				}
				return instance_type(walk, where, generic, completed, need, result, completed_values);
			}
		}
		if (parameters != arguments.size()) {
			return type_error(walk, ErrorCode::E4014, where, std::format("{} takes {} generic arguments, not {}",
				name_text(generic->name), parameters, arguments.size()));
		}
		/*
		 * Each argument the kind its parameter takes, checked here, where it's given: a type or a
		 * value, and a value one its type holds, when that's a builtin type. A type of the generic's
		 * own is checked with the instance, where its names are.
		 */
		size_t index = 0;
		for (ast::Node* child : value->children) {
			if (ast::NodeType::GENERIC_TAG != child->node_type || ast::NodeType::FUNCTION == value->node_type) {
				continue;
			}
			for (ast::Node* parameter : child->children) {
				if (index >= arguments.size()) {
					break;
				}
				const bool is_value = ast::NodeType::DERIVED_PARAMETER == parameter->node_type
					? !derived_parameter_is_type(walk.executor.program_info->names, generic, parameter)
					: ast::NodeType::COLON == parameter->node_type
						&& !generic_parameter_is_constrained(walk.executor.program_info->names, generic, parameter);
				const bool given_value = arguments[index] == nullptr;
				const std::string name = name_text(generic_parameter_name(parameter));
				if (is_value != given_value) {
					return type_error(walk, ErrorCode::E4014, where, is_value
						? std::format("{}'s {} is a value, so it takes one, not a type", name_text(generic->name), name)
						: std::format("{}'s {} is a type, so it takes one, not a value", name_text(generic->name), name));
				}
				ast::Node* declared_node = is_value && parameter->children.size() > 1 ? parameter->children[1] : nullptr;
				TypeInfo* declared = declared_node != nullptr && declared_node->children.empty() && declared_node->value.value != nullptr
					? builtin_type(name_text(declared_node->value.value)) : nullptr;
				if (declared != nullptr && index < values.size()) {
					const ConstantValue& given = values[index];
					TypeInfo const* kind = get_base_type(declared);
					// An unknown value, in a body checked before any instance, is whatever its type allows
					const bool fits = kind == nullptr || ConstantValue::Kind::UNKNOWN == given.kind
						|| (TypeInfoVariant::INTEGER == kind->variant && ConstantValue::Kind::INTEGER == given.kind)
						|| (TypeInfoVariant::BOOLEAN == kind->variant && ConstantValue::Kind::BOOLEAN == given.kind);
					if (!fits) {
						return type_error(walk, ErrorCode::E4014, where, std::format("{}'s {} takes a {}, not {}",
							name_text(generic->name), name, to_string(declared), constant_text(given)));
					}
				}
				++index;
			}
		}
		Declaration* instance = instance_of(walk, generic, arguments, values);
		// Its constraints, and the functions it's given, checked where it's used (docs/types.md, Constraints)
		Progress progress = check_constraints(walk, where, generic, instance);
		if (progress == Progress::DONE) {
			progress = check_function_arguments(walk, where, generic, instance);
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		progress = require_resolved(walk, where, instance, need);
		if (progress != Progress::DONE) {
			return progress;
		}
		result = instance->type_value;
		return Progress::DONE;
	}

	/*
	 * Each function an instance is given, like a HashMap's hash, takes and gives what its parameter
	 * says, with the instance's other arguments in it: checked where the instance is made, so an error
	 * points there (docs/types.md, Values in Generic Lists).
	 */
	Progress check_function_arguments(Walk& walk, ast::Node* where, Declaration* generic, Declaration* instance) {
		ast::Node* value = generic_node(generic);
		if (value == nullptr) {
			return Progress::DONE;
		}
		std::vector<ast::Node*> parameters;
		for (ast::Node* child : value->children) {
			if (ast::NodeType::GENERIC_TAG == child->node_type) {
				parameters.insert(parameters.end(), child->children.begin(), child->children.end());
			}
		}
		// The generic's own file, with its parameters bound to the instance's arguments
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
		for (size_t i = 0; i < parameters.size() && i < instance->generic_arguments.size(); ++i) {
			const std::string name = name_text(generic_parameter_name(parameters[i]));
			inside.locals.push_back(intern(name));
			if (instance->generic_arguments[i] != nullptr) {
				inside.generic_types[name] = instance->generic_arguments[i];
			}
			else if (i < instance->generic_values.size()) {
				inside.generic_values[name] = instance->generic_values[i];
			}
		}
		for (size_t i = 0; i < parameters.size() && i < instance->generic_values.size(); ++i) {
			ast::Node* parameter = parameters[i];
			const ConstantValue& given = instance->generic_values[i];
			if (ast::NodeType::COLON != parameter->node_type || parameter->children.size() < 2
				|| ast::NodeType::FUNCTION != parameter->children[1]->node_type
				|| ConstantValue::Kind::FUNCTION != given.kind || given.function == nullptr) {
				continue;
			}
			Progress progress = walk_names(inside, parameter->children[1], Need::DECLARED);
			TypeInfo* declared = nullptr;
			if (progress == Progress::DONE) {
				progress = type_of(inside, parameter->children[1], Need::DECLARED, declared);
			}
			if (progress == Progress::DONE) {
				progress = require_resolved(walk, where, given.function, Need::RESOLVED);
			}
			if (progress != Progress::DONE) {
				return progress;
			}
			auto wanted = static_cast<TypeInfoFunction const*>(get_base_type(declared));
			auto actual = given.function->value_type != nullptr
				? static_cast<TypeInfoFunction const*>(get_base_type(given.function->value_type)) : nullptr;
			bool matches = wanted != nullptr && actual != nullptr && TypeInfoVariant::FUNCTION == actual->variant
				&& TypeInfoVariant::FUNCTION == wanted->variant && actual->input.size() == wanted->input.size()
				&& actual->output.size() == wanted->output.size();
			for (size_t j = 0; matches && j < wanted->input.size(); ++j) {
				matches = same_type(wanted->input[j].type, actual->input[j].type);
			}
			for (size_t j = 0; matches && j < wanted->output.size(); ++j) {
				matches = same_type(wanted->output[j].type, actual->output[j].type);
			}
			if (!matches) {
				return type_error(walk, ErrorCode::E4014, where, std::format("{}'s {} takes a {}, not {}, a {}",
					name_text(instance->name), name_text(generic_parameter_name(parameter)), to_string(declared),
					name_text(given.function->name), actual != nullptr ? to_string(actual) : "function"));
			}
		}
		return Progress::DONE;
	}

	// T?, an instance of base/builtin's Optional.
	Progress optional_of(Walk& walk, ast::Node* where, TypeInfo* type, Need need, TypeInfo*& result) {
		Declaration* optional = nullptr;
		Progress progress = builtin_generic(walk, where, "Optional", optional);
		if (progress != Progress::DONE) {
			return progress;
		}
		return instance_type(walk, where, optional, { type }, need, result);
	}

	// The ? of T?, when it's one of T's parts rather than around it.
	static bool is_optional_marker(const ast::Node* node) {
		return ast::NodeType::UNARY_OPERATOR == node->node_type
			&& TokenType::SYM_QUESTION == node->value.type && node->children.empty();
	}

	// vector[T, n], which like ptr[T] is made from its arguments rather than declared.
	static bool is_vector_name(std::string_view name) {
		return name == "vector";
	}

	static bool is_pointer_name(std::string_view name) {
		return name == "ptr" || name == "relptr8" || name == "relptr16" || name == "relptr32"
			|| name == "relptr64";
	}

	/*
	 * The type a name is: a generic parameter's argument, a declared type, or a builtin. binding is
	 * the node the walker looked the name up at. A generic type gives generic instead, for its
	 * arguments to make an instance of.
	 */
	static Progress named_type(Walk& walk, ast::Node* binding, InternedString name, TypeInfo*& result,
		Declaration*& generic) {

		result = nullptr;
		generic = nullptr;
		auto bound = walk.bindings.find(binding);
		if (bound != walk.bindings.end()) {
			Declaration* declaration = bound->second;
			if (DeclarationKind::GENERIC_TYPE == declaration->kind) {
				generic = declaration;
				return Progress::DONE;
			}
			if (declaration->type_value != nullptr) {
				result = declaration->type_value;
				return Progress::DONE;
			}
			return type_error(walk, ErrorCode::E4013, binding, std::format("{} isn't a type",
				name_text(declaration->name)));
		}
		auto parameter = walk.generic_types.find(name_text(name));
		if (parameter != walk.generic_types.end()) {
			result = parameter->second;
			return Progress::DONE;
		}
		result = builtin_type(name_text(name));
		if (result != nullptr) {
			return Progress::DONE;
		}
		return type_error(walk, ErrorCode::E4013, binding, std::format("{} isn't a type", name_text(name)));
	}

	/*
	 * What an IDENTIFIER in a value position names: package.Name when the walker bound the part
	 * after the dot (or base.Name, a builtin), otherwise the head itself, with anything after it,
	 * like .Member, being access into it. next is the first child after the name.
	 */
	struct NamedHead {
		ast::Node* binding;
		InternedString name;
		size_t next;
	};

	static NamedHead head_of(Walk& walk, ast::Node* node) {
		if (node->children.size() >= 2 && ast::NodeType::DOT_ACCESS == node->children[0]->node_type
			&& ast::NodeType::IDENTIFIER == node->children[1]->node_type) {
			const bool qualified = walk.bindings.contains(node->children[1])
				|| (is_text(node->value.value, "base") && !walk.bindings.contains(node));
			if (qualified) {
				return { node->children[1], node->children[1]->value.value, 2 };
			}
		}
		return { node, node->value.value, 0 };
	}

	// One part of a type after its name: [arguments], an array dimension, or ?.
	struct TypePart {
		enum class Kind : uint8_t {
			ARGUMENTS,
			DIMENSION,
			OPTIONAL,
		};
		Kind kind;
		ast::Node* node;
		std::vector<ast::Node*> arguments;
	};

	// The count of a static array, a compile-time integer.
	static Progress array_count(Walk& walk, ast::Node* node, size_t& count) {
		ConstantValue value;
		Progress progress = evaluate_in(walk, node, value);
		if (progress != Progress::DONE) {
			return progress;
		}
		if (ConstantValue::Kind::INTEGER != value.kind || value.integer < 0) {
			return type_error(walk, ErrorCode::E4014, node, "an array's count must be an integer of 0 or more");
		}
		count = static_cast<size_t>(value.integer);
		return Progress::DONE;
	}

	/*
	 * vector[T, n] (docs/types.md, Vectors): lanes of an integer, float or bool of the target's own
	 * endianness, a power of two of them, at most 64 bytes in all.
	 */
	Progress vector_type(Walk& walk, ast::Node* where, const std::vector<ast::Node*>& arguments, TypeInfo*& result) {
		if (arguments.size() != 2) {
			return type_error(walk, ErrorCode::E4014, where, "vector takes its lanes' type and how many, like vector[u32, 4]");
		}
		TypeInfo* element = nullptr;
		Progress progress = type_of(walk, arguments[0], Need::RESOLVED, element);
		if (progress != Progress::DONE) {
			return progress;
		}
		size_t count = 0;
		progress = array_count(walk, arguments[1], count);
		if (progress != Progress::DONE) {
			return progress;
		}
		TypeInfo const* lane = get_base_type(element);
		const bool numeric = lane != nullptr && (TypeInfoVariant::INTEGER == lane->variant || TypeInfoVariant::FLOAT == lane->variant);
		const bool own_endianness = !numeric
			|| (TypeInfoVariant::INTEGER == lane->variant ? static_cast<TypeInfoInteger const*>(lane)->endianness
				: static_cast<TypeInfoFloat const*>(lane)->endianness) == Endianness::SYSTEM;
		if (lane == nullptr || !(numeric || element == BUILTIN_bool) || !own_endianness || lane->size > 8) {
			return type_error(walk, ErrorCode::E4014, arguments[0],
				std::format("a vector's lanes are integers or floats of up to 64 bits, or bools, not {}", to_string(element)));
		}
		if (count == 0 || (count & (count - 1)) != 0 || element->size * count > 64) {
			return type_error(walk, ErrorCode::E4014, arguments[1],
				std::format("a vector has a power of two lanes, at most 64 bytes in all, not {} of {}", count, to_string(element)));
		}
		result = vector_of(walk, element, count);
		return Progress::DONE;
	}

	// Array dimensions, outermost first: the last one written is the innermost.
	static Progress apply_dimensions(Walk& walk, std::vector<TypePart>& dimensions, TypeInfo*& current) {
		for (auto iter = dimensions.rbegin(); iter != dimensions.rend(); ++iter) {
			ArrayType array_type = ArrayType::VIEW;
			size_t count = 0;
			if (!iter->arguments.empty()) {
				if (ast::NodeType::RANGE_ARRAY == iter->arguments[0]->node_type) {
					array_type = ArrayType::DYNAMIC;
				}
				else {
					array_type = ArrayType::STATIC;
					Progress progress = array_count(walk, iter->arguments[0], count);
					if (progress != Progress::DONE) {
						return progress;
					}
					// Its elements are held by value
					progress = require_complete(walk, iter->node, current);
					if (progress != Progress::DONE) {
						return progress;
					}
				}
			}
			current = array_of(walk, current, array_type, count);
		}
		dimensions.clear();
		return Progress::DONE;
	}

	/*
	 * A type from its name and the parts after it: ptr[T] and the relative pointers, a generic
	 * type's arguments, array dimensions and ?. binding is where the walker looked the name up.
	 */
	static Progress compose_type(Walk& walk, ast::Node* where, ast::Node* binding, InternedString name,
		std::vector<TypePart>& parts, Need need, TypeInfo*& result) {

		const bool pointer = is_pointer_name(name_text(name)) && !walk.bindings.contains(binding)
			&& !walk.generic_types.contains(name_text(name));
		const bool vector = is_vector_name(name_text(name)) && !walk.bindings.contains(binding)
			&& !walk.generic_types.contains(name_text(name));
		TypeInfo* current = nullptr;
		Declaration* generic = nullptr;
		if (vector) {
			if (parts.empty() || TypePart::Kind::ARGUMENTS != parts[0].kind) {
				return type_error(walk, ErrorCode::E4014, where, "vector takes its lanes' type and how many, like vector[u32, 4]");
			}
			Progress progress = vector_type(walk, parts[0].node, parts[0].arguments, current);
			if (progress != Progress::DONE) {
				return progress;
			}
			parts.erase(parts.begin());
		}
		else if (!pointer) {
			Progress progress = named_type(walk, binding, name, current, generic);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		// What isn't a static array holds its elements through a pointer
		Need head_need = need;
		for (const TypePart& part : parts) {
			if (TypePart::Kind::DIMENSION == part.kind
				&& (part.arguments.empty() || ast::NodeType::RANGE_ARRAY == part.arguments[0]->node_type)) {
				head_need = Need::DECLARED;
			}
		}
		std::vector<TypePart> dimensions;
		bool has_arguments = false;
		for (TypePart& part : parts) {
			// One value in brackets after a type that isn't generic is an array's count, like
			// u8[count] (docs/types.md, Values in Generic Lists)
			if (TypePart::Kind::ARGUMENTS == part.kind && !pointer && generic == nullptr && current != nullptr
				&& part.arguments.size() == 1) {
				part.kind = TypePart::Kind::DIMENSION;
			}
			// And the other way: brackets right after a generic type, like Bits[64], are its arguments
			if (TypePart::Kind::DIMENSION == part.kind && generic != nullptr && current == nullptr && !part.arguments.empty()
				&& ast::NodeType::RANGE_ARRAY != part.arguments[0]->node_type) {
				part.kind = TypePart::Kind::ARGUMENTS;
			}
			if (TypePart::Kind::ARGUMENTS == part.kind) {
				if (has_arguments || (!pointer && generic == nullptr)) {
					return type_error(walk, ErrorCode::E4014, part.node,
						std::format("{} doesn't take generic arguments", name_text(name)));
				}
				has_arguments = true;
				if (pointer) {
					if (part.arguments.size() != 1) {
						return type_error(walk, ErrorCode::E4014, part.node,
							std::format("{} takes one type, what it points to", name_text(name)));
					}
					TypeInfo* target = nullptr;
					Progress progress = type_of(walk, part.arguments[0], Need::DECLARED, target);
					if (progress != Progress::DONE) {
						return progress;
					}
					const std::string_view text(*name);
					const size_t size = text == "ptr" ? POINTER_SIZE
						: static_cast<size_t>(std::stoi(std::string(text.substr(6)))) / 8;
					TypeInfo const* pointed = get_base_type(target);
					const bool archetype_mutable = pointed != nullptr && TypeInfoVariant::ARCHETYPE == pointed->variant
						&& (static_cast<TypeInfoArchetype const*>(pointed)->capabilities & CAPABILITY_MUTABLE) != 0;
					const bool is_mutable = has_child(part.arguments[0], ast::NodeType::MUTABLE)
						|| names_mutable_parameter(walk, part.arguments[0]) || archetype_mutable;
					current = pointer_to(walk, target, is_mutable, text != "ptr", size);
				}
				else {
					std::vector<TypeInfo*> arguments;
					std::vector<ConstantValue> values;
					Progress progress = generic_type_arguments(walk, generic, part.arguments, [&](ast::Node* argument, TypeInfo*& type) {
						return type_of(walk, argument, Need::DECLARED, type);
					}, arguments, values);
					if (progress != Progress::DONE) {
						return progress;
					}
					progress = instance_type(walk, part.node, generic, arguments, head_need, current, values);
					if (progress != Progress::DONE) {
						return progress;
					}
					generic = nullptr;
				}
				continue;
			}
			if (current == nullptr) {
				break;
			}
			if (TypePart::Kind::DIMENSION == part.kind) {
				dimensions.push_back(part);
				continue;
			}
			Progress progress = apply_dimensions(walk, dimensions, current);
			if (progress == Progress::DONE) {
				progress = optional_of(walk, part.node, current, need, current);
			}
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		if (current == nullptr) {
			return type_error(walk, ErrorCode::E4014, where, generic != nullptr
				? std::format("{} needs its generic arguments", name_text(name))
				: std::format("{} needs what it points to", name_text(name)));
		}
		Progress progress = apply_dimensions(walk, dimensions, current);
		if (progress != Progress::DONE) {
			return progress;
		}
		result = current;
		return Progress::DONE;
	}

	/*
	 * A type in a type position, like a field's: a TYPE node named for its head, with GENERIC_TAG,
	 * ARRAY_DIMENSION and ? children, and a qualified name as DOT_ACCESS then the IDENTIFIER.
	 */
	static Progress type_of_type_node(Walk& walk, ast::Node* node, Need need, TypeInfo*& result) {
		// A type #insert put here (docs/compilation.md, Code Values)
		if (node->type != nullptr) {
			result = node->type;
			return Progress::DONE;
		}
		InternedString name = node->value.value;
		ast::Node* binding = node;
		std::vector<TypePart> parts;
		for (size_t i = 0; i < node->children.size(); ++i) {
			ast::Node* child = node->children[i];
			const ast::NodeType type = child->node_type;
			if (ast::NodeType::DOT_ACCESS == type && i + 1 < node->children.size()) {
				// package.Name, or base.Name for a builtin: the walker bound the last part
				binding = node->children[++i];
				name = binding->value.value;
			}
			else if (ast::NodeType::GENERIC_TAG == type) {
				parts.push_back({ TypePart::Kind::ARGUMENTS, child,
					std::vector<ast::Node*>(child->children.begin(), child->children.end()) });
			}
			else if (ast::NodeType::ARRAY_DIMENSION == type) {
				parts.push_back({ TypePart::Kind::DIMENSION, child,
					std::vector<ast::Node*>(child->children.begin(), child->children.end()) });
			}
			else if (ast::NodeType::UNARY_OPERATOR == type && TokenType::SYM_QUESTION == child->value.type) {
				parts.push_back({ TypePart::Kind::OPTIONAL, child, {} });
			}
		}
		return compose_type(walk, node, binding, name, parts, need, result);
	}

	/*
	 * A type in a value position, like after ::, an IDENTIFIER whose postfix parts are flat:
	 * ARRAY_DIMENSION, then that bracket's arguments, which are a generic's arguments or what a
	 * pointer points to, or else an array's count.
	 */
	static Progress type_of_identifier(Walk& walk, ast::Node* node, Need need, TypeInfo*& result) {
		const NamedHead head = head_of(walk, node);
		InternedString name = head.name;
		ast::Node* binding = head.binding;
		size_t i = head.next;
		const bool takes_arguments = ((is_pointer_name(name_text(name)) || is_vector_name(name_text(name)))
				&& !walk.bindings.contains(binding))
			|| (walk.bindings.contains(binding)
				&& DeclarationKind::GENERIC_TYPE == walk.bindings[binding]->kind);
		std::vector<TypePart> parts;
		for (; i < node->children.size(); ++i) {
			ast::Node* child = node->children[i];
			if (ast::NodeType::ARRAY_DIMENSION != child->node_type) {
				return type_error(walk, ErrorCode::E4013, child, std::format("{} isn't a type",
					name_text(node->value.value)));
			}
			TypePart part{ takes_arguments && parts.empty() ? TypePart::Kind::ARGUMENTS
				: TypePart::Kind::DIMENSION, child, {} };
			while (i + 1 < node->children.size()
				&& ast::NodeType::ARRAY_DIMENSION != node->children[i + 1]->node_type) {
				part.arguments.push_back(node->children[++i]);
			}
			parts.push_back(std::move(part));
		}
		return compose_type(walk, node, binding, name, parts, need, result);
	}

	static Progress function_signature(Walk& walk, ast::Node* node, TypeInfoFunction* function);
	static Progress struct_body(Walk& walk, ast::Node* node, TypeInfoStruct* type);
	static Progress union_body(Walk& walk, ast::Node* node, TypeInfoUnion* type);
	static Progress enum_body(Walk& walk, ast::Node* node, TypeInfoEnum* type);

	/*
	 * A function type, the same object for the same signature, so types that refer to it, like
	 * an optional function, are the same each time a declaration is worked out.
	 */
	Progress function_type(Walk& walk, ast::Node* node, TypeInfo*& result) {
		TypeInfoFunction signature;
		Progress progress = function_signature(walk, node, &signature);
		if (progress != Progress::DONE) {
			return progress;
		}
		std::string key = "fn";
		for (const FunctionInput& input : signature.input) {
			// Which default, so a call through the type finds it; types that differ only in defaults still convert
			key += std::format(" {}:{}:{}{}{}", name_text(input.name), static_cast<const void*>(input.type),
				static_cast<const void*>(input.default_value), input.is_varargs, input.is_escaping);
		}
		key += " ->";
		for (const FunctionOutput& output : signature.output) {
			key += std::format(" {}:{}:{}", name_text(output.name), static_cast<const void*>(output.type), output.is_unrestricted);
		}
		key += std::format(" {} {} {}", signature.never_returns, name_text(signature.calling_convention), signature.no_context);
		result = derived_type(walk, key, [&] {
			auto function = new TypeInfoFunction();
			function->input = signature.input;
			function->output = signature.output;
			function->never_returns = signature.never_returns;
			function->calling_convention = signature.calling_convention;
			function->no_context = signature.no_context;
			return function;
		});
		return Progress::DONE;
	}

	// A function type of its parameters' and result's types alone, for a call whose types the checker works out.
	TypeInfo* plain_function_type(Walk& walk, const std::vector<TypeInfo*>& inputs, TypeInfo* output) {
		std::string key = "plain fn";
		for (TypeInfo* input : inputs) {
			key += std::format(" {}", static_cast<const void*>(input));
		}
		key += std::format(" -> {}", static_cast<const void*>(output));
		return derived_type(walk, key, [&] {
			auto function = new TypeInfoFunction();
			for (TypeInfo* input : inputs) {
				FunctionInput parameter;
				parameter.type = input;
				function->input.push_back(parameter);
			}
			if (output != nullptr) {
				FunctionOutput result;
				result.type = output;
				function->output.push_back(result);
			}
			return function;
		});
	}

	// The same function type, marked #never_returns.
	static TypeInfo* never_returning(Walk& walk, TypeInfoFunction* function) {
		if (function->never_returns) {
			return function;
		}
		return derived_type(walk, std::format("never returns {}", static_cast<const void*>(function)), [&] {
			auto result = new TypeInfoFunction();
			result->input = function->input;
			result->output = function->output;
			result->never_returns = true;
			result->calling_convention = function->calling_convention;
			result->no_context = function->no_context;
			return result;
		});
	}

	// The same function type, with a calling convention (docs/calling_convention.md).
	static TypeInfo* with_convention(Walk& walk, TypeInfoFunction* function, InternedString convention) {
		return derived_type(walk, std::format("convention {} {}", static_cast<const void*>(function),
			name_text(convention)), [&] {
			auto result = new TypeInfoFunction();
			result->input = function->input;
			result->output = function->output;
			result->never_returns = function->never_returns;
			result->calling_convention = convention;
			result->no_context = function->no_context;
			return result;
		});
	}

	// The same function type, called without a context (#no_context).
	static TypeInfo* without_context(Walk& walk, TypeInfoFunction* function) {
		if (function->no_context) {
			return function;
		}
		return derived_type(walk, std::format("no context {}", static_cast<const void*>(function)), [&] {
			auto result = new TypeInfoFunction();
			result->input = function->input;
			result->output = function->output;
			result->never_returns = function->never_returns;
			result->calling_convention = function->calling_convention;
			result->no_context = true;
			return result;
		});
	}

	// The same function type, its defaults marked as checked with the function's body.
	static TypeInfo* with_defaults_in_body(Walk& walk, TypeInfoFunction* function) {
		bool any = false;
		for (const FunctionInput& input : function->input) {
			any = any || input.default_value != nullptr;
		}
		if (!any) {
			return function;
		}
		return derived_type(walk, std::format("defaults in body {}", static_cast<const void*>(function)), [&] {
			auto result = new TypeInfoFunction();
			result->input = function->input;
			for (FunctionInput& input : result->input) {
				input.default_in_body = input.default_value != nullptr;
			}
			result->output = function->output;
			result->never_returns = function->never_returns;
			result->calling_convention = function->calling_convention;
			result->no_context = function->no_context;
			return result;
		});
	}

	// Whether two expressions are written the same: the same nodes, with the same text.
	static bool same_expression(const ast::Node* a, const ast::Node* b) {
		if (a == nullptr || b == nullptr) {
			return a == b;
		}
		if (a->node_type != b->node_type || a->value.type != b->value.type || name_text(a->value.value) != name_text(b->value.value)
			|| a->children.size() != b->children.size()) {
			return false;
		}
		for (size_t i = 0; i < a->children.size(); ++i) {
			if (!same_expression(a->children[i], b->children[i])) {
				return false;
			}
		}
		return true;
	}

	/*
	 * A function declared with a type, like foo : FooFn : fn(a: int, b: int) { }: a parameter it gives no
	 * default gets the type's, and one it gives must be the type's, written the same (docs/functions.md,
	 * Defaults in Function Types). Whether the type fits the function otherwise is checked with its value.
	 */
	static Progress defaults_from_stated_type(Walk& walk, InternedString name, ast::Node* declared, TypeInfo*& function) {
		// Resolved, so an alias has what it aliases and a named function type its parameters
		Progress progress = walk_names(walk, declared, Need::RESOLVED);
		if (progress != Progress::DONE) {
			return progress;
		}
		TypeInfo* stated = nullptr;
		progress = type_of(walk, declared, Need::RESOLVED, stated);
		if (progress != Progress::DONE) {
			return progress;
		}
		TypeInfo const* stated_base = get_base_type_or_alias(stated);
		if (stated_base == nullptr || TypeInfoVariant::FUNCTION != stated_base->variant) {
			return Progress::DONE;
		}
		auto type = static_cast<TypeInfoFunction const*>(stated_base);
		auto own = static_cast<TypeInfoFunction*>(function);
		if (type->input.size() != own->input.size()) {
			return Progress::DONE;
		}
		std::vector<FunctionInput> inputs = own->input;
		bool inherits = false;
		for (size_t i = 0; i < inputs.size(); ++i) {
			const FunctionInput& theirs = type->input[i];
			FunctionInput& mine = inputs[i];
			if (mine.default_value == nullptr) {
				if (theirs.default_value != nullptr) {
					mine.has_default = true;
					mine.default_value = theirs.default_value;
					mine.default_package = theirs.default_package;
					mine.default_file = theirs.default_file;
					// The type's, so checked on its own, not with this function's body
					mine.default_in_body = false;
					inherits = true;
				}
				continue;
			}
			if (theirs.default_value == nullptr) {
				return type_error(walk, ErrorCode::E4038, mine.default_value, std::format(
					"{} gives {} a default its stated type doesn't: leave out the type to give it one", name_text(name), name_text(mine.name)));
			}
			if (!same_expression(mine.default_value, theirs.default_value)) {
				return type_error(walk, ErrorCode::E4038, mine.default_value, std::format(
					"{}'s default for {} isn't its stated type's: leave it out to use the type's, or leave out the type", name_text(name),
					name_text(mine.name)));
			}
		}
		if (!inherits) {
			return Progress::DONE;
		}
		function = derived_type(walk, std::format("defaults of {} for {}", static_cast<const void*>(stated_base),
			static_cast<const void*>(own)), [&] {
			auto result = new TypeInfoFunction();
			result->input = inputs;
			result->output = own->output;
			result->never_returns = own->never_returns;
			result->calling_convention = own->calling_convention;
			result->no_context = own->no_context;
			return result;
		});
		return Progress::DONE;
	}

	// Which anonymous type a node is: the node, in an instance with its generic arguments.
	static std::string anonymous_type_key(Walk& walk, const ast::Node* node) {
		std::string key = std::format("anonymous {}", static_cast<const void*>(node));
		for (const auto& [name, type] : walk.generic_types) {
			key += std::format(" {}={}", name, static_cast<const void*>(type));
		}
		return key;
	}

	Progress type_of(Walk& walk, ast::Node* node, Need need, TypeInfo*& result) {
		const ast::NodeType type = node->node_type;
		if (ast::NodeType::VOID == type) {
			result = BUILTIN_void;
			return Progress::DONE;
		}
		if (ast::NodeType::TYPE == type) {
			return type_of_type_node(walk, node, need, result);
		}
		if (ast::NodeType::IDENTIFIER == type) {
			return type_of_identifier(walk, node, need, result);
		}
		if (ast::NodeType::UNARY_OPERATOR == type && TokenType::SYM_QUESTION == node->value.type
			&& node->children.size() == 1) {
			TypeInfo* value = nullptr;
			Progress progress = type_of(walk, node->children[0], need, value);
			if (progress != Progress::DONE) {
				return progress;
			}
			return optional_of(walk, node, value, need, result);
		}
		if (ast::NodeType::FUNCTION == type) {
			if (has_child(node, ast::NodeType::GENERIC_TAG)) {
				return type_error(walk, ErrorCode::E4014, node, "a function type can't be generic");
			}
			Progress progress = function_type(walk, node, result);
			if (progress != Progress::DONE) {
				return progress;
			}
			// fn(...)?, an optional function, keeps its ? among the function's parts
			for (ast::Node* child : node->children) {
				if (is_optional_marker(child)) {
					return optional_of(walk, child, result, need, result);
				}
			}
			return Progress::DONE;
		}
		/*
		 * An anonymous struct, union or enum, like a field's _ : struct { x, y : f32 }. It's the
		 * same object each time its declaration is worked out, which may be more than once.
		 */
		const std::string anonymous_key = anonymous_type_key(walk, node);
		if (ast::NodeType::STRUCT == type) {
			auto anonymous = static_cast<TypeInfoStruct*>(derived_type(walk, anonymous_key,
				[] { return new TypeInfoStruct(nullptr); }));
			result = anonymous;
			return struct_body(walk, node, anonymous);
		}
		if (ast::NodeType::UNION == type) {
			auto anonymous = static_cast<TypeInfoUnion*>(derived_type(walk, anonymous_key,
				[] { return new TypeInfoUnion(nullptr); }));
			result = anonymous;
			return union_body(walk, node, anonymous);
		}
		if (ast::NodeType::ENUM == type) {
			auto anonymous = static_cast<TypeInfoEnum*>(derived_type(walk, anonymous_key,
				[] { return new TypeInfoEnum(nullptr); }));
			result = anonymous;
			return enum_body(walk, node, anonymous);
		}
		return type_error(walk, ErrorCode::E4013, node, "this isn't a type");
	}

	// A directive's argument, like 8 in #align(8): what follows its parentheses.
	static ast::Node* directive_argument(ast::Node* directive) {
		for (ast::Node* child : directive->children) {
			if (ast::NodeType::PAREN_GROUP != child->node_type) {
				return child;
			}
		}
		return nullptr;
	}

	/*
	 * Parameters and results (docs/functions.md). Their types only need to be declared, so a
	 * function can take what it's part of.
	 */
	static Progress function_signature(Walk& walk, ast::Node* node, TypeInfoFunction* function) {
		function->input.clear();
		function->output.clear();
		bool seen_parameters = false;
		bool all_unrestricted = false;
		for (ast::Node* child : node->children) {
			const ast::NodeType type = child->node_type;
			if (ast::NodeType::LIST == type && !seen_parameters) {
				seen_parameters = true;
				for (ast::Node* parameter : child->children) {
					ast::Node* names_and_type = parameter;
					bool has_default = false;
					if (ast::NodeType::BINARY_OPERATOR == parameter->node_type && is_assign(parameter)
						&& !parameter->children.empty()) {
						names_and_type = parameter->children[0];
						has_default = true;
					}
					if (ast::NodeType::COLON != names_and_type->node_type) {
						// Just a type, in a function type like fn(int) -> bool
						FunctionInput input;
						Progress progress = type_of(walk, names_and_type, Need::DECLARED, input.type);
						if (progress != Progress::DONE) {
							return progress;
						}
						function->input.push_back(input);
						continue;
					}
					// Names, then a type unless it comes from the default, then ... for varargs
					std::vector<ast::Node*> parameter_names;
					TypeInfo* parameter_type = nullptr;
					bool is_varargs = false;
					for (ast::Node* part : names_and_type->children) {
						if (ast::NodeType::IDENTIFIER == part->node_type && parameter_names.empty()) {
							parameter_names.push_back(part);
						}
						else if (ast::NodeType::LIST == part->node_type) {
							for (ast::Node* name : part->children) {
								parameter_names.push_back(name);
							}
						}
						else if (ast::NodeType::ELLIIPSIS == part->node_type) {
							is_varargs = true;
						}
						else {
							Progress progress = type_of(walk, part, Need::DECLARED, parameter_type);
							if (progress != Progress::DONE) {
								return progress;
							}
						}
					}
					if (parameter_type == nullptr && has_default && parameter->children.size() == 2) {
						// The type of its default, like allocator := context.allocator
						Value default_value;
						Progress progress = check_constant(walk, parameter->children[1], nullptr, default_value);
						if (progress != Progress::DONE) {
							return progress;
						}
						parameter_type = usual_type(default_value);
					}
					for (ast::Node* name : parameter_names) {
						FunctionInput input;
						input.name = name->value.value;
						input.type = parameter_type;
						input.has_default = has_default;
						if (has_default && parameter->children.size() == 2) {
							input.default_value = parameter->children[1];
							input.default_package = walk.package_path;
							input.default_file = walk.file_name;
						}
						input.is_varargs = is_varargs;
						for (ast::Node* directive : name->children) {
							if (is_text(directive->value.value, "#crosses_threads")) {
								input.crosses_threads = true;
							}
							if (is_text(directive->value.value, "#escaping")) {
								input.is_escaping = true;
							}
						}
						function->input.push_back(input);
					}
				}
			}
			else if (ast::NodeType::LIST == type) {
				/*
				 * Several results. Named ones are flat: names, a COLON, then the type they share, like
				 * (a: u16, b, c: f32).
				 */
				const bool named = has_child(child, ast::NodeType::COLON);
				std::vector<FunctionOutput> pending;
				for (size_t i = 0; i < child->children.size(); ++i) {
					ast::Node* part = child->children[i];
					if (ast::NodeType::COLON == part->node_type) {
						continue;
					}
					const bool is_type = !named || (i > 0 && ast::NodeType::COLON == child->children[i - 1]->node_type);
					if (!is_type) {
						FunctionOutput output;
						output.name = part->value.value;
						for (ast::Node* directive : part->children) {
							if (ast::NodeType::DIRECTIVE == directive->node_type && is_text(directive->value.value, "#unrestricted")) {
								output.is_unrestricted = true;
							}
						}
						pending.push_back(output);
						continue;
					}
					TypeInfo* result_type = nullptr;
					Progress progress = type_of(walk, part, Need::DECLARED, result_type);
					if (progress != Progress::DONE) {
						return progress;
					}
					if (!named) {
						function->output.push_back({ result_type, nullptr });
						continue;
					}
					for (FunctionOutput output : pending) {
						output.type = result_type;
						function->output.push_back(output);
					}
					pending.clear();
				}
			}
			else if (is_optional_marker(child)) {
				continue; // fn(...)?, an optional function
			}
			else if (ast::NodeType::TYPE == type || ast::NodeType::FUNCTION == type
				|| ast::NodeType::IDENTIFIER == type || ast::NodeType::UNARY_OPERATOR == type) {
				FunctionOutput output;
				Progress progress = type_of(walk, child, Need::DECLARED, output.type);
				if (progress != Progress::DONE) {
					return progress;
				}
				function->output.push_back(output);
			}
			else if (ast::NodeType::DIRECTIVE == type) {
				if (is_text(child->value.value, "#never_returns")) {
					function->never_returns = true;
				}
				else if (is_text(child->value.value, "#no_context")) {
					function->no_context = true;
				}
				// After the results, like -> Result[string, Error] #unrestricted: every result is
				else if (is_text(child->value.value, "#unrestricted")) {
					all_unrestricted = true;
				}
				else if (is_text(child->value.value, "#calling_convention")) {
					ast::Node* convention = directive_argument(child);
					function->calling_convention = convention != nullptr ? convention->value.value : nullptr;
				}
			}
		}
		if (all_unrestricted) {
			for (FunctionOutput& output : function->output) {
				output.is_unrestricted = true;
			}
		}
		return Progress::DONE;
	}

	// A member's type, held by value, so complete.
	static Progress member_type(Walk& walk, ast::Node* node, TypeInfo*& result) {
		Progress progress = type_of(walk, node, Need::RESOLVED, result);
		if (progress != Progress::DONE) {
			return progress;
		}
		return require_complete(walk, node, result);
	}

	// A compile-time integer in a directive, like #align(8).
	static Progress directive_integer(Walk& walk, ast::Node* directive, int64_t& value) {
		ast::Node* argument = directive_argument(directive);
		if (argument == nullptr) {
			return type_error(walk, ErrorCode::E4014, directive,
				std::format("{} needs a value", name_text(directive->value.value)));
		}
		ConstantValue constant;
		Progress progress = evaluate_in(walk, argument, constant);
		if (progress != Progress::DONE) {
			return progress;
		}
		if (ConstantValue::Kind::INTEGER != constant.kind) {
			return type_error(walk, ErrorCode::E4014, argument,
				std::format("{} needs an integer", name_text(directive->value.value)));
		}
		value = constant.integer;
		return Progress::DONE;
	}

	static bool has_owned_directive(const ast::Node* node) {
		for (const ast::Node* child : node->children) {
			if (ast::NodeType::DIRECTIVE == child->node_type && is_text(child->value.value, "#owned")) {
				return true;
			}
		}
		return false;
	}

	// docs/types.md, Structs: fields, using, anonymous structs, and #packed, #align, #union, #scoped, #unrestricted.
	static Progress struct_body(Walk& walk, ast::Node* node, TypeInfoStruct* type) {
		type->members.clear();
		for (ast::Node* child : node->children) {
			const ast::NodeType child_type = child->node_type;
			if (ast::NodeType::DIRECTIVE == child_type) {
				if (is_text(child->value.value, "#packed")) {
					type->is_packed = true;
				}
				else if (is_text(child->value.value, "#union")) {
					type->is_union = true;
				}
				else if (is_text(child->value.value, "#scoped")) {
					type->is_scoped = true;
				}
				else if (is_text(child->value.value, "#unrestricted")) {
					type->is_unrestricted = true;
				}
				else if (is_text(child->value.value, "#secret")) {
					type->is_secret = true;
				}
				else if (is_text(child->value.value, "#thread_bound")) {
					// #thread_bound, or #thread_bound(condition) for the instances it's true for
					type->is_thread_bound = true;
					for (ast::Node* argument : child->children) {
						if (ast::NodeType::PAREN_GROUP == argument->node_type) {
							continue;
						}
						ConstantValue condition;
						Progress progress = evaluate_in(walk, argument, condition);
						if (progress != Progress::DONE) {
							return progress;
						}
						if (ConstantValue::Kind::BOOLEAN != condition.kind) {
							return type_error(walk, ErrorCode::E4014, argument, "#thread_bound's condition is a bool");
						}
						type->is_thread_bound = condition.boolean;
						break;
					}
				}
				else if (is_text(child->value.value, "#owned")) {
					// #owned(release), or #owned(release, condition) for the instances it's true for
					std::vector<ast::Node*> arguments;
					for (ast::Node* argument : child->children) {
						if (ast::NodeType::PAREN_GROUP != argument->node_type) {
							arguments.push_back(argument);
						}
					}
					ast::Node* release = arguments.empty() ? nullptr : arguments[0];
					if (release == nullptr || ast::NodeType::IDENTIFIER != release->node_type) {
						return type_error(walk, ErrorCode::E4014, child, "#owned names the function that releases one, like #owned(release)");
					}
					type->is_owned = true;
					type->release_name = release->value.value;
					type->release_package = nullptr;
					if (release->children.size() >= 2 && ast::NodeType::DOT_ACCESS == release->children[0]->node_type) {
						type->release_package = release->value.value;
						type->release_name = release->children[1]->value.value;
					}
					if (arguments.size() >= 2) {
						ConstantValue condition;
						Progress progress = evaluate_in(walk, arguments[1], condition);
						if (progress != Progress::DONE) {
							return progress;
						}
						if (ConstantValue::Kind::BOOLEAN != condition.kind) {
							return type_error(walk, ErrorCode::E4014, arguments[1], "#owned's condition is a bool");
						}
						type->is_owned = condition.boolean;
					}
				}
				if (type->is_scoped && type->is_unrestricted) {
					return type_error(walk, ErrorCode::E4014, child, "a struct can't be both #scoped and #unrestricted");
				}
				else if (is_text(child->value.value, "#align")) {
					int64_t alignment = 0;
					Progress progress = directive_integer(walk, child, alignment);
					if (progress != Progress::DONE) {
						return progress;
					}
					if (alignment <= 0 || (alignment & (alignment - 1)) != 0) {
						return type_error(walk, ErrorCode::E4014, child, "#align needs a power of two");
					}
					type->requested_alignment = static_cast<size_t>(alignment);
				}
			}
			else if (ast::NodeType::DEFINITION == child_type && !child->children.empty()) {
				// Names, then the type, then = and a default value
				ast::Node* type_node = child->children.size() > 1 && !is_assign(child->children[1])
					? child->children[1] : nullptr;
				if (type_node == nullptr) {
					//TODO(ches) a field's type from its default, which needs type checking
					return type_error(walk, ErrorCode::E4014, child->children[0], "a field needs a type");
				}
				TypeInfo* field_type = nullptr;
				Progress progress = member_type(walk, type_node, field_type);
				if (progress != Progress::DONE) {
					return progress;
				}
				// A default, = value, is a compile-time constant (docs/types.md, Structs); --- is none
				ast::Node* default_node = std::any_of(child->children.begin(), child->children.end(),
					[](const ast::Node* part) { return is_assign(part); }) ? definition_value(child) : nullptr;
				const bool has_value = default_node != nullptr && ast::NodeType::UNINITIALIZED != default_node->node_type;
				ConstantValue default_value{ ConstantValue::Kind::INTEGER, false, 0, std::string(), nullptr };
				if (has_value) {
					progress = evaluate_in(walk, default_node, default_value);
					if (progress != Progress::DONE) {
						return progress;
					}
					if (ConstantValue::Kind::FUNCTION == default_value.kind) {
						return type_error(walk, ErrorCode::E4014, default_node, "a field's default can't be a function yet");
					}
				}
				const int64_t default_integer = ConstantValue::Kind::BOOLEAN == default_value.kind ? (default_value.boolean ? 1 : 0)
					: default_value.integer;
				const std::string default_member = ConstantValue::Kind::ENUM_MEMBER == default_value.kind ? default_value.member : std::string();
				ast::Node* names_node = child->children[0];
				// using value : ptr[T], or : Inner: a named field whose members are the struct's own (docs/types.md, Structs)
				const bool named_using = ast::NodeType::USING == child->children.back()->node_type;
				if (named_using) {
					TypeInfo const* used = get_base_type(field_type);
					if (ast::NodeType::IDENTIFIER != names_node->node_type || used == nullptr
						|| (TypeInfoVariant::POINTER != used->variant && TypeInfoVariant::STRUCT != used->variant)
						|| (TypeInfoVariant::POINTER == used->variant && static_cast<TypeInfoPointer const*>(used)->base_type == nullptr)) {
						return type_error(walk, ErrorCode::E4014, names_node, std::format("using needs one field, a struct or a pointer to something, not {}",
							to_string(field_type)));
					}
					type->members.push_back({ names_node->value.value, field_type, 0, has_value, true, default_integer, default_member });
				}
				else if (ast::NodeType::UNDERSCORE == names_node->node_type) {
					// Its members are the struct's own
					type->members.push_back({ nullptr, field_type, 0, has_value, true, default_integer, default_member });
				}
				else if (ast::NodeType::LIST == names_node->node_type) {
					for (ast::Node* name : names_node->children) {
						type->members.push_back({ name->value.value, field_type, 0, has_value, false, default_integer, default_member });
					}
				}
				else {
					type->members.push_back({ names_node->value.value, field_type, 0, has_value, false, default_integer, default_member });
				}
			}
			else if (ast::NodeType::USING == child_type && !child->children.empty()) {
				// using Name, or using package.Name: the walker bound the last part
				ast::Node* binding = child->children.size() >= 3 ? child->children[2] : child->children[0];
				TypeInfo* included = nullptr;
				Declaration* generic = nullptr;
				Progress progress = named_type(walk, binding, binding->value.value, included, generic);
				if (progress == Progress::DONE && included == nullptr) {
					progress = type_error(walk, ErrorCode::E4014, binding, "using needs a struct");
				}
				if (progress == Progress::DONE) {
					progress = require_complete(walk, binding, included);
				}
				if (progress != Progress::DONE) {
					return progress;
				}
				if (TypeInfoVariant::STRUCT != get_base_type(included)->variant) {
					return type_error(walk, ErrorCode::E4014, binding,
						std::format("using needs a struct, and {} isn't one", to_string(included)));
				}
				type->members.push_back({ binding->value.value, included, 0, false, true, 0, std::string() });
			}
		}
		/*
		 * Holding an owner makes a struct owned (docs/memory.md, Owned Types). One of its own, not an
		 * instance of a generic, says so, with the function that releases it.
		 */
		if (!type->is_owned && type->instance == nullptr && !has_owned_directive(node)) {
			for (const StructMember& member : type->members) {
				if (is_owned(member.member_type)) {
					return type_error(walk, ErrorCode::E4035, node, std::format("{} holds {}, which is #owned, so it's owned too: "
						"say so, with the function that releases it, like #owned(release_{})", name_text(type->name),
						to_string(member.member_type), name_text(type->name)));
				}
			}
		}
		lay_out_struct(type);
		return Progress::DONE;
	}

	// docs/types.md, Unions: variants, each with the types of its values.
	static Progress union_body(Walk& walk, ast::Node* node, TypeInfoUnion* type) {
		type->variants.clear();
		for (ast::Node* child : node->children) {
			if (ast::NodeType::IDENTIFIER == child->node_type) {
				UnionVariant variant;
				variant.name = child->value.value;
				type->variants.push_back(variant);
			}
			else if (ast::NodeType::PAREN_GROUP == child->node_type && !type->variants.empty()) {
				for (ast::Node* value : child->children) {
					TypeInfo* value_type = nullptr;
					Progress progress = member_type(walk, value, value_type);
					if (progress != Progress::DONE) {
						return progress;
					}
					// A void value is none at all, so Result[void, E]'s Ok holds nothing, like None
					if (value_type != BUILTIN_void) {
						type->variants.back().types.push_back(value_type);
					}
				}
			}
		}
		lay_out_union(type);
		return Progress::DONE;
	}

	static bool is_unsigned_integer(TypeInfo const* type) {
		type = get_base_type(type);
		return type != nullptr && TypeInfoVariant::INTEGER == type->variant
			&& !static_cast<TypeInfoInteger const*>(type)->is_signed
			&& Endianness::SYSTEM == static_cast<TypeInfoInteger const*>(type)->endianness;
	}

	// docs/types.md, Enums: #backed_by, and members counting up from 0 unless given a value.
	static Progress enum_body(Walk& walk, ast::Node* node, TypeInfoEnum* type) {
		type->backing_type = BUILTIN_uint;
		type->members.clear();
		type->values.clear();
		uint64_t next = 0;
		for (ast::Node* child : node->children) {
			if (ast::NodeType::DIRECTIVE == child->node_type && is_text(child->value.value, "#backed_by")) {
				ast::Node* backing = directive_argument(child);
				TypeInfo* backing_type = nullptr;
				Progress progress = backing == nullptr
					? type_error(walk, ErrorCode::E4014, child, "#backed_by needs a type")
					: type_of(walk, backing, Need::RESOLVED, backing_type);
				if (progress != Progress::DONE) {
					return progress;
				}
				if (!is_unsigned_integer(backing_type)) {
					return type_error(walk, ErrorCode::E4014, backing,
						std::format("an enum is backed by an unsigned integer, not {}", to_string(backing_type)));
				}
				type->backing_type = backing_type;
			}
			else if (ast::NodeType::IDENTIFIER == child->node_type) {
				uint64_t value = next;
				if (!child->children.empty() && !child->children[0]->children.empty()) {
					ConstantValue constant;
					ast::Node* expression = child->children[0]->children[0];
					Progress progress = evaluate_in(walk, expression, constant);
					if (progress != Progress::DONE) {
						return progress;
					}
					if (ConstantValue::Kind::INTEGER != constant.kind || constant.integer < 0) {
						return type_error(walk, ErrorCode::E4014, expression,
							"an enum member's value must be an integer of 0 or more");
					}
					value = static_cast<uint64_t>(constant.integer);
				}
				type->members.push_back(child->value.value);
				type->values.push_back(value);
				next = value + 1;
			}
		}
		const size_t bits = get_base_type(type->backing_type)->size * 8;
		for (size_t i = 0; i < type->values.size(); ++i) {
			if (bits < 64 && type->values[i] >= (uint64_t{ 1 } << bits)) {
				return type_error(walk, ErrorCode::E4014, node, std::format("{} = {} doesn't fit in {}",
					name_text(type->members[i]), type->values[i], to_string(type->backing_type)));
			}
		}
		lay_out_enum(type);
		return Progress::DONE;
	}

	// alias T and distinct alias T: the aliased type is the definition's last part.
	static Progress alias_body(Walk& walk, ast::Node* definition, TypeInfoAlias* alias) {
		ast::Node* aliased = definition->children.back();
		// Word :: distinct alias u32 #secret (docs/memory.md, Secrets)
		for (ast::Node* part : definition->children) {
			if (ast::NodeType::KEYWORD_ALIAS != part->node_type) {
				continue;
			}
			for (ast::Node* directive : part->children) {
				if (ast::NodeType::DIRECTIVE != directive->node_type) {
					continue;
				}
				if (!is_text(directive->value.value, "#secret")) {
					return type_error(walk, ErrorCode::E4014, directive, std::format("an alias takes #secret, not {}",
						name_text(directive->value.value)));
				}
				if (!alias->distinct) {
					return type_error(walk, ErrorCode::E4014, directive,
						"only a distinct alias is #secret, since an alias is the same type as what it names");
				}
				alias->is_secret = true;
			}
		}
		TypeInfo* base = nullptr;
		Progress progress = type_of(walk, aliased, Need::RESOLVED, base);
		if (progress == Progress::DONE) {
			progress = require_complete(walk, aliased, base);
		}
		if (progress != Progress::DONE) {
			return progress;
		}
		alias->base_type = base;
		lay_out_alias(alias);
		return Progress::DONE;
	}

	// Whether a value names a type, like Y in X :: Y, which makes X an alias of it.
	static bool is_type_expression(Walk& walk, ast::Node* node) {
		const ast::NodeType type = node->node_type;
		if (ast::NodeType::TYPE == type) {
			return true;
		}
		if (ast::NodeType::UNARY_OPERATOR == type) {
			return TokenType::SYM_QUESTION == node->value.type;
		}
		if (ast::NodeType::IDENTIFIER != type) {
			return false;
		}
		const NamedHead head = head_of(walk, node);
		ast::Node* binding = head.binding;
		InternedString name = head.name;
		// After the name, only a type's own parts: [arguments] and array dimensions
		for (size_t i = head.next; i < node->children.size(); ++i) {
			if (ast::NodeType::DOT_ACCESS == node->children[i]->node_type) {
				return false;
			}
		}
		auto bound = walk.bindings.find(binding);
		if (bound != walk.bindings.end()) {
			return DeclarationKind::GENERIC_TYPE == bound->second->kind || bound->second->type_value != nullptr;
		}
		return is_pointer_name(name_text(name)) || is_vector_name(name_text(name)) || builtin_type(name_text(name)) != nullptr
			|| walk.generic_types.contains(name_text(name));
	}

	// Directives a #foreign function can't have, since #foreign decides its convention.
	static bool foreign_conflicts(ast::Node* directive) {
		return is_text(directive->value.value, "#calling_convention") || is_text(directive->value.value, "#no_context")
			|| is_text(directive->value.value, "#export");
	}

	/*
	 * #foreign(LIBRARY) and #link_name("symbol") on a function without a body (docs/directives.md,
	 * #foreign): the library comes from LIBRARY :: #library("name"), in this package or an imported one.
	 */
	static Progress foreign_directives(Walk& walk, ast::Node* definition, Declaration* declaration) {
		ast::Node* foreign = nullptr;
		ast::Node* link_name = nullptr;
		ast::Node* conflict = nullptr;
		for (ast::Node* directive : definition->children[0]->children) {
			if (is_text(directive->value.value, "#foreign")) {
				foreign = directive;
			}
			else if (is_text(directive->value.value, "#link_name")) {
				link_name = directive;
			}
			else if (foreign_conflicts(directive)) {
				conflict = directive;
			}
		}
		if (foreign == nullptr) {
			if (link_name != nullptr) {
				return type_error(walk, ErrorCode::E4014, link_name, "#link_name is only for #foreign functions");
			}
			return Progress::DONE;
		}
		if (conflict != nullptr) {
			return type_error(walk, ErrorCode::E4014, conflict,
				"a #foreign function uses the platform's C convention without a context, so it takes no other");
		}
		if (function_body(declaration) != nullptr) {
			return type_error(walk, ErrorCode::E4014, foreign, "a #foreign function has no body: declare it with : ---");
		}
		ast::Node* library = directive_argument(foreign);
		if (library == nullptr || ast::NodeType::IDENTIFIER != library->node_type) {
			return type_error(walk, ErrorCode::E4014, foreign,
				"#foreign needs the name of a library constant, like #foreign(KERNEL32) for KERNEL32 :: #library(\"kernel32\")");
		}
		// LIBRARY, or package.LIBRARY
		ast::Node* qualifier = library->children.size() == 2 && ast::NodeType::DOT_ACCESS == library->children[0]->node_type
			? library->children[1] : nullptr;
		bool head_was_package = false;
		Progress progress = require_qualified(walk, library, library->value.value, qualifier, Need::DECLARED, head_was_package);
		if (progress != Progress::DONE) {
			return progress;
		}
		auto bound = walk.bindings.find(head_was_package ? qualifier : library);
		Declaration* constant = bound != walk.bindings.end() ? bound->second : nullptr;
		ast::Node* value = constant != nullptr && constant->node != nullptr ? definition_value(constant->node) : nullptr;
		ast::Node* name = value != nullptr && ast::NodeType::DIRECTIVE == value->node_type && is_text(value->value.value, "#library")
			? directive_argument(value) : nullptr;
		if (name == nullptr || ast::NodeType::LITERAL != name->node_type || TokenType::LITERAL_STRING != name->value.type) {
			return type_error(walk, ErrorCode::E4014, library, "#foreign needs a constant declared as #library(\"name\")");
		}
		// The lexer keeps a string literal's quotes
		std::string_view text(*name->value.value);
		declaration->foreign_library = intern(std::string(text.substr(1, text.size() - 2)));
		declaration->link_name = declaration->name;
		if (link_name != nullptr) {
			ast::Node* symbol = directive_argument(link_name);
			if (symbol == nullptr || ast::NodeType::LITERAL != symbol->node_type || TokenType::LITERAL_STRING != symbol->value.type) {
				return type_error(walk, ErrorCode::E4014, link_name, "#link_name needs a string, the symbol's name");
			}
			std::string_view symbol_text(*symbol->value.value);
			declaration->link_name = intern(std::string(symbol_text.substr(1, symbol_text.size() - 2)));
		}
		return Progress::DONE;
	}

	/*
	 * #target_features("aes,pclmul") on a function with a body (docs/directives.md, Functions): CPU
	 * features its code may use beyond the target's, so it's only called once the CPU is known to have
	 * them. Names are LLVM's, comma separated; each is added, as +name.
	 */
	static Progress target_features_directive(Walk& walk, ast::Node* definition, Declaration* declaration) {
		for (ast::Node* directive : definition->children[0]->children) {
			if (!is_text(directive->value.value, "#target_features")) {
				continue;
			}
			ast::Node* argument = directive_argument(directive);
			if (argument == nullptr || ast::NodeType::LITERAL != argument->node_type || TokenType::LITERAL_STRING != argument->value.type) {
				return type_error(walk, ErrorCode::E4014, directive, "#target_features needs a string of feature names, like \"aes,pclmul\"");
			}
			if (declaration->foreign_library != nullptr || function_body(declaration) == nullptr) {
				return type_error(walk, ErrorCode::E4014, directive, "#target_features is for a function with a body, whose code uses them");
			}
			std::string_view text(*argument->value.value);
			text = text.substr(1, text.size() - 2);
			std::string features;
			while (!text.empty()) {
				const size_t comma = text.find(',');
				std::string_view feature = text.substr(0, comma);
				while (!feature.empty() && feature.front() == ' ') {
					feature.remove_prefix(1);
				}
				while (!feature.empty() && feature.back() == ' ') {
					feature.remove_suffix(1);
				}
				if (feature.empty() || feature.front() == '+' || feature.front() == '-') {
					return type_error(walk, ErrorCode::E4014, directive,
						"#target_features names the features to add, like \"aes,pclmul\", without + or -");
				}
				features += std::format("{}+{}", features.empty() ? "" : ",", feature);
				text = comma == std::string_view::npos ? std::string_view() : text.substr(comma + 1);
			}
			declaration->target_features = intern(features);
		}
		return Progress::DONE;
	}

	// The directives after a declaration's name, like #externally_initialized (docs/directives.md).
	static Progress name_directives(Walk& walk, ast::Node* definition, Declaration* declaration) {
		ast::Node* names_node = definition->children[0];
		ast::Node* name_node = names_node;
		if (ast::NodeType::LIST == names_node->node_type) {
			for (ast::Node* each : names_node->children) {
				if (each->value.value == declaration->name) {
					name_node = each;
				}
			}
		}
		ast::Node* section = nullptr;
		for (ast::Node* directive : name_node->children) {
			if (is_text(directive->value.value, "#externally_initialized")) {
				declaration->externally_initialized = true;
			}
			else if (is_text(directive->value.value, "#section")) {
				section = directive;
				ast::Node* name = directive_argument(directive);
				if (name == nullptr || ast::NodeType::LITERAL != name->node_type
					|| TokenType::LITERAL_STRING != name->value.type) {
					return type_error(walk, ErrorCode::E4014, directive, "#section needs a string, the section's name");
				}
				// The lexer keeps a string literal's quotes
				std::string_view text(*name->value.value);
				declaration->section = intern(std::string(text.substr(1, text.size() - 2)));
			}
		}
		if (section != nullptr && !declaration->externally_initialized) {
			return type_error(walk, ErrorCode::E4014, section,
				"#section is only allowed together with #externally_initialized");
		}
		if (declaration->externally_initialized && DeclarationKind::VALUE != declaration->kind) {
			return type_error(walk, ErrorCode::E4014, name_node,
				"#externally_initialized is only for constants");
		}
		return Progress::DONE;
	}

	Progress compute_declaration(Walk& walk, const std::vector<Declaration*>& declarations,
		ast::Node* definition) {

		NameRegistry& names = walk.executor.program_info->names;
		Declaration* declaration = declarations[0];
		ast::Node* value = definition_value(definition);
		ast::Node* declared = definition_declared_type(definition);
		for (Declaration* each : declarations) {
			Progress progress = name_directives(walk, definition, each);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		if (DeclarationKind::GENERIC_TYPE == declaration->kind) {
			// Its instances are worked out with their arguments
			return Progress::DONE;
		}
		if (DeclarationKind::TYPE == declaration->kind) {
			TypeInfo* type = declaration->type_value;
			if (TypeInfoVariant::STRUCT == type->variant) {
				return struct_body(walk, value, static_cast<TypeInfoStruct*>(type));
			}
			if (TypeInfoVariant::UNION == type->variant) {
				return union_body(walk, value, static_cast<TypeInfoUnion*>(type));
			}
			if (TypeInfoVariant::ENUM == type->variant) {
				return enum_body(walk, value, static_cast<TypeInfoEnum*>(type));
			}
			if (TypeInfoVariant::ALIAS == type->variant) {
				return alias_body(walk, definition, static_cast<TypeInfoAlias*>(type));
			}
			if (has_child(value, ast::NodeType::GENERIC_TAG)) {
				return type_error(walk, ErrorCode::E4014, value, "a function type can't be generic");
			}
			return function_signature(walk, value, static_cast<TypeInfoFunction*>(type));
		}
		if (DeclarationKind::FUNCTION == declaration->kind) {
			ast::Node* signature = value != nullptr && ast::NodeType::FUNCTION == value->node_type
				? value : declared;
			if (signature == nullptr || has_child(signature, ast::NodeType::GENERIC_TAG)) {
				// A generic function's types are worked out for each call
				return Progress::DONE;
			}
			TypeInfo* function = nullptr;
			Progress progress = function_type(walk, signature, function);
			if (progress != Progress::DONE) {
				return progress;
			}
			// A function's own defaults are checked with its body
			if (signature == value && has_body(definition)) {
				function = with_defaults_in_body(walk, static_cast<TypeInfoFunction*>(function));
			}
			if (declared != nullptr && declared != signature) {
				progress = defaults_from_stated_type(walk, declarations[0]->name, declared, function);
				if (progress != Progress::DONE) {
					return progress;
				}
			}
			/*
			 * #never_returns and #calling_convention after the name, like
			 * trap #never_returns : fn() : --- or handler #calling_convention(.interrupt) :: fn(...),
			 * are the type's. So is #foreign's convention: the platform's C convention, without a context.
			 */
			progress = foreign_directives(walk, definition, declarations[0]);
			if (progress != Progress::DONE) {
				return progress;
			}
			progress = target_features_directive(walk, definition, declarations[0]);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (declarations[0]->foreign_library != nullptr) {
				function = with_convention(walk, static_cast<TypeInfoFunction*>(without_context(walk, static_cast<TypeInfoFunction*>(function))),
					intern(std::string("c")));
			}
			for (ast::Node* directive : definition->children[0]->children) {
				if (is_text(directive->value.value, "#never_returns")) {
					function = never_returning(walk, static_cast<TypeInfoFunction*>(function));
				}
				else if (is_text(directive->value.value, "#no_context")) {
					function = without_context(walk, static_cast<TypeInfoFunction*>(function));
				}
				else if (is_text(directive->value.value, "#calling_convention")) {
					ast::Node* convention = directive_argument(directive);
					function = with_convention(walk, static_cast<TypeInfoFunction*>(function),
						convention != nullptr ? convention->value.value : nullptr);
				}
			}
			for (Declaration* each : declarations) {
				each->value_type = function;
			}
			return Progress::DONE;
		}

		// A constant, or a name for a type, like my_int :: i32 (docs/types.md, Type Aliases)
		TypeInfo* value_type = nullptr;
		auto checked = std::make_shared<CheckedBody>();
		if (declared != nullptr) {
			Progress progress = type_of(walk, declared, Need::DECLARED, value_type);
			if (progress != Progress::DONE) {
				return progress;
			}
			// Its value, which has to fit, and is recorded for generating it
			if (value != nullptr && ast::NodeType::UNINITIALIZED != value->node_type) {
				progress = require_complete(walk, declared, value_type);
				if (progress != Progress::DONE) {
					return progress;
				}
				Value constant;
				progress = check_constant(walk, value, value_type, constant, checked.get());
				if (progress != Progress::DONE) {
					return progress;
				}
			}
		}
		else if (value != nullptr && is_type_expression(walk, value)) {
			TypeInfo* aliased = nullptr;
			Progress progress = type_of(walk, value, Need::RESOLVED, aliased);
			if (progress == Progress::DONE) {
				progress = require_complete(walk, value, aliased);
			}
			if (progress != Progress::DONE) {
				return progress;
			}
			for (Declaration* each : declarations) {
				TypeInfoAlias* alias = make_type<TypeInfoAlias>(names, each->name, false);
				alias->base_type = aliased;
				lay_out_alias(alias);
				std::scoped_lock<std::mutex> lock(names.mutex);
				each->type_value = alias;
				names.type_declarations[alias] = each;
			}
			return Progress::DONE;
		}
		else if (value != nullptr && ast::NodeType::UNINITIALIZED != value->node_type) {
			// Its value's type, or what kind of literal it is (docs/types.md)
			Value constant;
			Progress progress = check_constant(walk, value, nullptr, constant, checked.get());
			if (progress != Progress::DONE) {
				return progress;
			}
			value_type = ValueKind::VALUE == constant.kind ? constant.type : nullptr;
			const Untyped untyped = ValueKind::UNTYPED_INTEGER == constant.kind ? Untyped::INTEGER
				: ValueKind::UNTYPED_FLOAT == constant.kind ? Untyped::FLOAT
				: ValueKind::UNTYPED_STRING == constant.kind ? Untyped::STRING
				: ValueKind::UNTYPED_BOOLEAN == constant.kind ? Untyped::BOOLEAN
				: Untyped::NONE;
			for (Declaration* each : declarations) {
				each->untyped = untyped;
				// One name's value, like X :: 300; several share one value only in name
				each->integer_known = declarations.size() == 1 && ValueKind::UNTYPED_INTEGER == constant.kind
					&& constant.integer_known;
				each->integer_negative = constant.integer_negative;
				each->integer_magnitude = constant.integer_magnitude;
			}
		}
		for (Declaration* each : declarations) {
			each->value_type = value_type;
			each->checked = checked;
		}
		return Progress::DONE;
	}

	// A generic parameter's name: T, or capacity in capacity: usize.
	static InternedString generic_parameter_name(const ast::Node* parameter) {
		return ast::NodeType::COLON == parameter->node_type && !parameter->children.empty()
			? parameter->children[0]->value.value : parameter->value.value;
	}

	bool generic_parameter_is_value(NameRegistry& names, const Declaration* generic, size_t index) {
		ast::Node* value = generic_node(generic);
		size_t at = 0;
		for (ast::Node* child : value != nullptr ? value->children : MyVector<ast::Node*>{}) {
			if (ast::NodeType::GENERIC_TAG != child->node_type) {
				continue;
			}
			for (ast::Node* parameter : child->children) {
				if (at++ == index) {
					// A derived one, like atomic = true, is a value unless it's written as a type
					if (ast::NodeType::DERIVED_PARAMETER == parameter->node_type) {
						return !derived_parameter_is_type(names, generic, parameter);
					}
					return ast::NodeType::COLON == parameter->node_type && !generic_parameter_is_constrained(names, generic, parameter);
				}
			}
		}
		return false;
	}

	Progress generic_type_arguments(Walk& walk, const Declaration* generic, const std::vector<ast::Node*>& nodes,
		const std::function<Progress(ast::Node*, TypeInfo*&)>& type_of, std::vector<TypeInfo*>& arguments,
		std::vector<ConstantValue>& values) {

		arguments.clear();
		values.clear();
		for (size_t i = 0; i < nodes.size(); ++i) {
			ast::Node* argument = nodes[i];
			if (generic_parameter_is_value(walk.executor.program_info->names, generic, i)) {
				// A compile-time value: a literal, a named constant, an enum member or #run's result
				ConstantValue value;
				Progress progress = evaluate_in(walk, argument, value);
				if (progress != Progress::DONE) {
					return progress;
				}
				arguments.push_back(nullptr);
				values.push_back(value);
				continue;
			}
			TypeInfo* type = nullptr;
			Progress progress = type_of(argument, type);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (has_child(argument, ast::NodeType::MUTABLE) || names_mutable_parameter(walk, argument)) {
				type = mutable_argument(walk, type);
			}
			arguments.push_back(type);
			values.push_back({});
		}
		return Progress::DONE;
	}

	ast::Node* generic_node(const Declaration* generic) {
		ast::Node* value = definition_value(generic->node);
		if (value != nullptr && (ast::NodeType::STRUCT == value->node_type || ast::NodeType::UNION == value->node_type
			|| ast::NodeType::FUNCTION == value->node_type)) {
			return value;
		}
		// A function declared without a body, like array_add : fn[T](...) : ---
		ast::Node* declared = definition_declared_type(generic->node);
		return declared != nullptr && ast::NodeType::FUNCTION == declared->node_type ? declared : value;
	}

	Progress compute_instance(Walk& walk, Declaration* instance) {
		ast::Node* value = generic_node(instance->generic != nullptr ? instance->generic : instance);
		// Bind the generic parameters to the instance's arguments
		walk.generic_types.clear();
		size_t index = 0;
		for (ast::Node* child : value->children) {
			if (ast::NodeType::GENERIC_TAG != child->node_type) {
				continue;
			}
			for (ast::Node* parameter : child->children) {
				if (index >= instance->generic_arguments.size()) {
					return type_error(walk, ErrorCode::E4014, parameter, "this generic parameter has no argument");
				}
				const bool is_value = ast::NodeType::DERIVED_PARAMETER == parameter->node_type
					? !derived_parameter_is_type(walk.executor.program_info->names, instance->generic, parameter)
					: ast::NodeType::COLON == parameter->node_type
						&& !generic_parameter_is_constrained(walk.executor.program_info->names, instance->generic, parameter);
				const std::string name = name_text(generic_parameter_name(parameter));
				// A value, like capacity: usize, takes a compile-time value; a derived one either; anything else a type
				if (is_value != (instance->generic_arguments[index] == nullptr)
					&& ast::NodeType::FUNCTION != value->node_type && ast::NodeType::DERIVED_PARAMETER != parameter->node_type) {
					return type_error(walk, ErrorCode::E4014, parameter, is_value
						? std::format("{} is a value, so it takes one, not a type", name)
						: std::format("{} is a type, so it takes one, not a value", name));
				}
				if (is_value && parameter->children.size() > 1) {
					TypeInfo* declared = nullptr;
					Progress progress = type_of(walk, parameter->children[1], Need::DECLARED, declared);
					if (progress != Progress::DONE) {
						return progress;
					}
					const ConstantValue& given = instance->generic_values[index];
					TypeInfo const* kind = get_base_type(declared);
					// An unknown value, in a body checked before any instance, is whatever its type allows
					const bool fits = kind == nullptr || ConstantValue::Kind::UNKNOWN == given.kind
						|| (TypeInfoVariant::INTEGER == kind->variant && ConstantValue::Kind::INTEGER == given.kind)
						|| (TypeInfoVariant::BOOLEAN == kind->variant && ConstantValue::Kind::BOOLEAN == given.kind)
						|| (TypeInfoVariant::ENUM == kind->variant && ConstantValue::Kind::ENUM_MEMBER == given.kind)
						|| (TypeInfoVariant::FUNCTION == kind->variant && ConstantValue::Kind::FUNCTION == given.kind);
					if (!fits) {
						return type_error(walk, ErrorCode::E4014, parameter, std::format("{} takes a {}, not {}",
							name, to_string(declared), constant_text(given)));
					}
				}
				// A type, or a compile-time parameter's value
				if (instance->generic_arguments[index] == nullptr) {
					walk.generic_values[name] = instance->generic_values[index];
				}
				else {
					bind_generic_type(walk, name, instance->generic_arguments[index]);
				}
				++index;
			}
		}
		if (ast::NodeType::FUNCTION == value->node_type) {
			return function_type(walk, value, instance->value_type);
		}
		// A generic alias's instance: what it names, with the instance's arguments
		if (TypeInfoVariant::ALIAS == instance->type_value->variant) {
			return alias_body(walk, instance->node, static_cast<TypeInfoAlias*>(instance->type_value));
		}
		if (TypeInfoVariant::STRUCT == instance->type_value->variant) {
			return struct_body(walk, value, static_cast<TypeInfoStruct*>(instance->type_value));
		}
		return union_body(walk, value, static_cast<TypeInfoUnion*>(instance->type_value));
	}
}
