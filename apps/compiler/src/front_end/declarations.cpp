#include <algorithm>
#include <format>
#include <memory>

#include "error/reporting.h"
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
				}
			}
			else if (ast::NodeType::ENUM == value_type) {
				kind = DeclarationKind::TYPE;
				type = make_type<TypeInfoEnum>(names, declaration->name);
			}
			else if (ast::NodeType::KEYWORD_ALIAS == value_type
				|| ast::NodeType::KEYWORD_DISTINCT == value_type) {
				kind = DeclarationKind::TYPE;
				type = make_type<TypeInfoAlias>(names, declaration->name,
					ast::NodeType::KEYWORD_DISTINCT == value_type);
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
		report_error(code, walk.file_path, where->value.line_number, where->value.column_number,
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

	static TypeInfo* pointer_to(Walk& walk, TypeInfo* base, bool is_mutable, bool is_relative, size_t size) {
		return derived_type(walk,
			std::format("ptr {} {} {} {}", static_cast<const void*>(base), is_mutable, is_relative, size),
			[&] { return new TypeInfoPointer(base, is_relative, is_mutable, size); });
	}

	static TypeInfo* array_of(Walk& walk, TypeInfo* element, ArrayType array_type, size_t count) {
		return derived_type(walk,
			std::format("array {} {} {}", static_cast<const void*>(element), static_cast<int>(array_type), count),
			[&] { return new TypeInfoArray(element, array_type, count); });
	}

	static Progress type_of(Walk& walk, ast::Node* node, Need need, TypeInfo*& result);

	// An instance of a generic type, made the first time it's asked for, resolved when need asks.
	static Progress instance_type(Walk& walk, ast::Node* where, Declaration* generic,
		const std::vector<TypeInfo*>& arguments, Need need, TypeInfo*& result) {

		ast::Node* value = definition_value(generic->node);
		size_t parameters = 0;
		for (ast::Node* child : value->children) {
			if (ast::NodeType::GENERIC_TAG == child->node_type) {
				parameters = child->children.size();
			}
		}
		if (parameters != arguments.size()) {
			return type_error(walk, ErrorCode::E4014, where, std::format("{} takes {} generic arguments, not {}",
				name_text(generic->name), parameters, arguments.size()));
		}
		Declaration* instance = instance_of(walk, generic, arguments);
		Progress progress = require_resolved(walk, where, instance, need);
		if (progress != Progress::DONE) {
			return progress;
		}
		result = instance->type_value;
		return Progress::DONE;
	}

	// T?, an instance of base/builtin's Optional.
	static Progress optional_of(Walk& walk, ast::Node* where, TypeInfo* type, Need need, TypeInfo*& result) {
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
		TypeInfo* current = nullptr;
		Declaration* generic = nullptr;
		if (!pointer) {
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
					current = pointer_to(walk, target, has_child(part.arguments[0], ast::NodeType::MUTABLE),
						text != "ptr", size);
				}
				else {
					std::vector<TypeInfo*> arguments;
					for (ast::Node* argument : part.arguments) {
						if (ast::NodeType::LITERAL == argument->node_type) {
							//TODO(ches) values in generic lists (docs/types.md, Values in Generic Lists)
							return type_error(walk, ErrorCode::E4014, argument,
								"values as generic arguments aren't supported yet");
						}
						TypeInfo* argument_type = nullptr;
						Progress progress = type_of(walk, argument, Need::DECLARED, argument_type);
						if (progress != Progress::DONE) {
							return progress;
						}
						arguments.push_back(argument_type);
					}
					Progress progress = instance_type(walk, part.node, generic, arguments, head_need, current);
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
		const bool takes_arguments = (is_pointer_name(name_text(name)) && !walk.bindings.contains(binding))
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
	static Progress function_type(Walk& walk, ast::Node* node, TypeInfo*& result) {
		TypeInfoFunction signature;
		Progress progress = function_signature(walk, node, &signature);
		if (progress != Progress::DONE) {
			return progress;
		}
		std::string key = "fn";
		for (const FunctionInput& input : signature.input) {
			key += std::format(" {}:{}:{}{}{}", name_text(input.name), static_cast<const void*>(input.type),
				input.has_default, input.is_varargs, input.is_escaping);
		}
		key += " ->";
		for (const FunctionOutput& output : signature.output) {
			key += std::format(" {}:{}", name_text(output.name), static_cast<const void*>(output.type));
		}
		key += std::format(" {} {}", signature.never_returns, name_text(signature.calling_convention));
		result = derived_type(walk, key, [&] {
			auto function = new TypeInfoFunction();
			function->input = signature.input;
			function->output = signature.output;
			function->never_returns = signature.never_returns;
			function->calling_convention = signature.calling_convention;
			return function;
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

	static Progress type_of(Walk& walk, ast::Node* node, Need need, TypeInfo*& result) {
		const ast::NodeType type = node->node_type;
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
					for (ast::Node* name : parameter_names) {
						FunctionInput input;
						input.name = name->value.value;
						//TODO(ches) a type from the default, like allocator := context.allocator, needs type checking
						input.type = parameter_type;
						input.has_default = has_default;
						input.is_varargs = is_varargs;
						for (ast::Node* directive : name->children) {
							if (is_text(directive->value.value, "#escaping")) {
								input.is_escaping = true;
							}
						}
						function->input.push_back(input);
					}
				}
			}
			else if (ast::NodeType::LIST == type) {
				// Several results; named ones are flat, as each name, a COLON, then the type
				const bool named = has_child(child, ast::NodeType::COLON);
				for (size_t i = 0; i < child->children.size(); ++i) {
					ast::Node* part = child->children[i];
					if (ast::NodeType::COLON == part->node_type) {
						continue;
					}
					if (named && !(i > 0 && ast::NodeType::COLON == child->children[i - 1]->node_type)) {
						continue;
					}
					FunctionOutput output;
					if (named) {
						output.name = child->children[i - 2]->value.value;
					}
					Progress progress = type_of(walk, part, Need::DECLARED, output.type);
					if (progress != Progress::DONE) {
						return progress;
					}
					function->output.push_back(output);
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
				else if (is_text(child->value.value, "#calling_convention")) {
					ast::Node* convention = directive_argument(child);
					function->calling_convention = convention != nullptr ? convention->value.value : nullptr;
				}
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

	// docs/types.md, Structs: fields, using, anonymous structs, and #packed, #align, #union, #scoped.
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
				const bool has_value = std::any_of(child->children.begin(), child->children.end(),
					[](const ast::Node* part) { return is_assign(part); });
				ast::Node* names_node = child->children[0];
				if (ast::NodeType::UNDERSCORE == names_node->node_type) {
					// Its members are the struct's own
					type->members.push_back({ nullptr, field_type, 0, has_value, true });
				}
				else if (ast::NodeType::LIST == names_node->node_type) {
					for (ast::Node* name : names_node->children) {
						type->members.push_back({ name->value.value, field_type, 0, has_value, false });
					}
				}
				else {
					type->members.push_back({ names_node->value.value, field_type, 0, has_value, false });
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
				type->members.push_back({ binding->value.value, included, 0, false, true });
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
					type->variants.back().types.push_back(value_type);
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
		return is_pointer_name(name_text(name)) || builtin_type(name_text(name)) != nullptr
			|| walk.generic_types.contains(name_text(name));
	}

	/*
	 * The type of a constant's value where its syntax shows it: a struct or array literal, or
	 * another constant or function. Other values are typed by type checking.
	 */
	static Progress value_type_of(Walk& walk, ast::Node* value, TypeInfo*& result) {
		result = nullptr;
		const ast::NodeType type = value->node_type;
		if (ast::NodeType::IDENTIFIER == type) {
			const NamedHead head = head_of(walk, value);
			auto bound = walk.bindings.find(head.binding);
			if (bound == walk.bindings.end()) {
				return Progress::DONE;
			}
			if (head.next == value->children.size()) {
				// Another constant or function
				result = bound->second->value_type;
			}
			else if (head.next + 2 == value->children.size() && bound->second->type_value != nullptr
				&& TypeInfoVariant::ENUM == get_base_type(bound->second->type_value)->variant) {
				// An enum member, like Mode.Fast
				result = bound->second->type_value;
			}
			return Progress::DONE;
		}
		if (ast::NodeType::STRUCT_LITERAL == type || ast::NodeType::ARRAY_LITERAL == type) {
			std::vector<TypePart> parts;
			ast::Node* binding = value;
			InternedString name = value->value.value;
			size_t elements = 0;
			for (size_t i = 0; i < value->children.size(); ++i) {
				ast::Node* child = value->children[i];
				if (ast::NodeType::DOT_ACCESS == child->node_type && i + 1 < value->children.size()) {
					binding = value->children[++i];
					name = binding->value.value;
				}
				else if (ast::NodeType::GENERIC_TAG == child->node_type) {
					parts.push_back({ TypePart::Kind::ARGUMENTS, child,
						std::vector<ast::Node*>(child->children.begin(), child->children.end()) });
				}
				else if (ast::NodeType::LIST == child->node_type) {
					elements = child->children.size();
				}
			}
			TypeInfo* named = nullptr;
			Progress progress = compose_type(walk, value, binding, name, parts, Need::RESOLVED, named);
			if (progress != Progress::DONE) {
				return progress;
			}
			if (ast::NodeType::ARRAY_LITERAL == type) {
				progress = require_complete(walk, value, named);
				if (progress != Progress::DONE) {
					return progress;
				}
				named = array_of(walk, named, ArrayType::STATIC, elements);
			}
			result = named;
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
			for (Declaration* each : declarations) {
				each->value_type = function;
			}
			return Progress::DONE;
		}

		// A constant, or a name for a type, like my_int :: i32 (docs/types.md, Type Aliases)
		TypeInfo* value_type = nullptr;
		if (declared != nullptr) {
			Progress progress = type_of(walk, declared, Need::DECLARED, value_type);
			if (progress != Progress::DONE) {
				return progress;
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
		else if (value != nullptr) {
			Progress progress = value_type_of(walk, value, value_type);
			if (progress != Progress::DONE) {
				return progress;
			}
		}
		for (Declaration* each : declarations) {
			each->value_type = value_type;
		}
		return Progress::DONE;
	}

	Progress compute_instance(Walk& walk, Declaration* instance) {
		ast::Node* value = definition_value(instance->node);
		// Bind the generic parameters to the instance's arguments
		walk.generic_types.clear();
		size_t index = 0;
		for (ast::Node* child : value->children) {
			if (ast::NodeType::GENERIC_TAG != child->node_type) {
				continue;
			}
			for (ast::Node* parameter : child->children) {
				if (ast::NodeType::COLON == parameter->node_type || index >= instance->generic_arguments.size()) {
					//TODO(ches) values in generic lists
					return type_error(walk, ErrorCode::E4014, parameter,
						"values as generic parameters aren't supported yet");
				}
				walk.generic_types[name_text(parameter->value.value)] = instance->generic_arguments[index++];
			}
		}
		if (TypeInfoVariant::STRUCT == instance->type_value->variant) {
			return struct_body(walk, value, static_cast<TypeInfoStruct*>(instance->type_value));
		}
		return union_body(walk, value, static_cast<TypeInfoUnion*>(instance->type_value));
	}
}
