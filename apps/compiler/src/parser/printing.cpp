#include "parser/printing.h"

#include <format>
#include <string_view>
#include <utility>
#include <vector>

namespace hemera::ast {

	/*
	 * Writes a tree back as Hemera, by the shapes the parser makes (parser.cpp): the same tree comes back
	 * when the text is parsed, which the parser's round-trip test checks against every file in base, std
	 * and the scenarios. A tree the parser didn't make, like code compile-time code built, gets the
	 * parentheses its operators need, which parsing turns into PAREN_GROUP nodes.
	 */
	namespace {

		// How tightly an expression binds, by where the parser parses it: an operand needs at least its level.
		enum Level : int {
			ANY = 0,
			ASSIGNMENT = 1,
			// or_else, or_return, is_none, is_some, or_break, or_continue, and if
			FALLBACK = 2,
			RANGE = 3,
			OR = 4,
			AND = 5,
			COMPARISON = 6,
			SUM = 7,
			PRODUCT = 8,
			PREFIX = 10,
			ATOM = 11,
		};

		std::string_view text_of(const Node* node) {
			return node->value.value != nullptr ? std::string_view(*node->value.value) : std::string_view();
		}

		bool is_token(const Node* node, TokenType type) {
			return node->value.type == type;
		}

		std::string_view operator_text(TokenType type) {
			if (type == TokenType::OPERATOR_AND) {
				return "&&";
			}
			else if (type == TokenType::OPERATOR_ASSIGN) {
				return "=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_ADD) {
				return "+=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_AND) {
				return "&&=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_BITWISE_AND) {
				return "&=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_BITWISE_OR) {
				return "|=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_BITWISE_XOR) {
				return "~=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_DIV) {
				return "/=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_LEFT_SHIFT) {
				return "<<=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_MOD) {
				return "%=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_MUL) {
				return "*=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_OR) {
				return "||=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_REMAINDER) {
				return "%%=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC) {
				return ">>=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL) {
				return ">>>=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_SUB) {
				return "-=";
			}
			else if (type == TokenType::OPERATOR_BITWISE_OR) {
				return "|";
			}
			else if (type == TokenType::OPERATOR_BITWISE_XOR) {
				return "~";
			}
			else if (type == TokenType::OPERATOR_DIVIDE) {
				return "/";
			}
			else if (type == TokenType::OPERATOR_DEREFERENCE) {
				return "^";
			}
			else if (type == TokenType::OPERATOR_EQUAL) {
				return "==";
			}
			else if (type == TokenType::OPERATOR_GREATER_THAN_OR_EQUAL) {
				return ">=";
			}
			else if (type == TokenType::OPERATOR_LEFT_SHIFT) {
				return "<<";
			}
			else if (type == TokenType::OPERATOR_LESS_THAN_OR_EQUAL) {
				return "<=";
			}
			else if (type == TokenType::OPERATOR_MINUS) {
				return "-";
			}
			else if (type == TokenType::OPERATOR_MODULUS) {
				return "%";
			}
			else if (type == TokenType::OPERATOR_MULTIPLY) {
				return "*";
			}
			else if (type == TokenType::OPERATOR_NOT) {
				return "!";
			}
			else if (type == TokenType::OPERATOR_NOT_EQUAL) {
				return "!=";
			}
			else if (type == TokenType::OPERATOR_OR) {
				return "||";
			}
			else if (type == TokenType::OPERATOR_PIPE) {
				return "|>";
			}
			else if (type == TokenType::OPERATOR_PLUS) {
				return "+";
			}
			else if (type == TokenType::OPERATOR_RANGE_ARRAY) {
				return "..";
			}
			else if (type == TokenType::OPERATOR_RANGE_EXCLUSIVE) {
				return "..<";
			}
			else if (type == TokenType::OPERATOR_RANGE_INCLUSIVE) {
				return "..=";
			}
			else if (type == TokenType::OPERATOR_REMAINDER) {
				return "%%";
			}
			else if (type == TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC) {
				return ">>";
			}
			else if (type == TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL) {
				return ">>>";
			}
			else if (type == TokenType::SYM_AMPERSAND) {
				return "&";
			}
			else if (type == TokenType::SYM_GT) {
				return ">";
			}
			else if (type == TokenType::SYM_LT) {
				return "<";
			}
			else if (type == TokenType::SYM_QUESTION) {
				return "?";
			}
			else if (type == TokenType::KEYWORD_OR_ELSE) {
				return "or_else";
			}
			else if (type == TokenType::KEYWORD_OR_RETURN) {
				return "or_return";
			}
			else if (type == TokenType::KEYWORD_IS_NONE) {
				return "is_none";
			}
			else if (type == TokenType::KEYWORD_IS_SOME) {
				return "is_some";
			}
			else if (type == TokenType::KEYWORD_OR_BREAK) {
				return "or_break";
			}
			else if (type == TokenType::KEYWORD_OR_CONTINUE) {
				return "or_continue";
			}
			else if (type == TokenType::KEYWORD_CAST) {
				return "cast";
			}
			else if (type == TokenType::KEYWORD_BIT_CAST) {
				return "bit_cast";
			}
			else if (type == TokenType::KEYWORD_AUTO_CAST) {
				return "auto_cast";
			}
			else {
				return "";
			}
		}

		bool is_assignment(TokenType type) {
			return TokenType::OPERATOR_ASSIGN == type || TokenType::OPERATOR_ASSIGN_ADD == type
				|| TokenType::OPERATOR_ASSIGN_AND == type || TokenType::OPERATOR_ASSIGN_BITWISE_AND == type
				|| TokenType::OPERATOR_ASSIGN_BITWISE_OR == type || TokenType::OPERATOR_ASSIGN_BITWISE_XOR == type
				|| TokenType::OPERATOR_ASSIGN_DIV == type || TokenType::OPERATOR_ASSIGN_LEFT_SHIFT == type
				|| TokenType::OPERATOR_ASSIGN_MOD == type || TokenType::OPERATOR_ASSIGN_MUL == type
				|| TokenType::OPERATOR_ASSIGN_OR == type || TokenType::OPERATOR_ASSIGN_REMAINDER == type
				|| TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC == type || TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL == type
				|| TokenType::OPERATOR_ASSIGN_SUB == type;
		}

		int binary_level(TokenType type) {
			if (is_assignment(type)) {
				return ASSIGNMENT;
			}
			if (type == TokenType::KEYWORD_OR_ELSE || type == TokenType::KEYWORD_OR_RETURN) {
				return FALLBACK;
			}
			else if (type == TokenType::OPERATOR_RANGE_EXCLUSIVE || type == TokenType::OPERATOR_RANGE_INCLUSIVE) {
				return RANGE;
			}
			else if (type == TokenType::OPERATOR_OR) {
				return OR;
			}
			else if (type == TokenType::OPERATOR_AND) {
				return AND;
			}
			else if (type == TokenType::OPERATOR_EQUAL || type == TokenType::OPERATOR_NOT_EQUAL || type == TokenType::SYM_LT || type == TokenType::SYM_GT || type == TokenType::OPERATOR_LESS_THAN_OR_EQUAL || type == TokenType::OPERATOR_GREATER_THAN_OR_EQUAL) {
				return COMPARISON;
			}
			else if (type == TokenType::OPERATOR_PLUS || type == TokenType::OPERATOR_MINUS || type == TokenType::OPERATOR_BITWISE_OR || type == TokenType::OPERATOR_BITWISE_XOR) {
				return SUM;
			}
			else if (type == TokenType::OPERATOR_PIPE) {
				return ATOM;
			}
			else {
				return PRODUCT;
			}
		}

		// A postfix marker in a chain like a.b[c](d)^: the operations are siblings after the value's head.
		bool is_marker(const Node* node) {
			if (!node->children.empty()) {
				return false;
			}
			return NodeType::DOT_ACCESS == node->node_type || NodeType::ARRAY_DIMENSION == node->node_type
				|| NodeType::PAREN_GROUP == node->node_type
				|| (NodeType::UNARY_OPERATOR == node->node_type && is_token(node, TokenType::OPERATOR_DEREFERENCE));
		}

		bool is_prefix(const Node* node) {
			return NodeType::UNARY_OPERATOR == node->node_type && !node->children.empty()
				&& (is_token(node, TokenType::OPERATOR_MINUS) || is_token(node, TokenType::OPERATOR_PLUS)
					|| is_token(node, TokenType::OPERATOR_BITWISE_XOR) || is_token(node, TokenType::OPERATOR_NOT));
		}

		int level_of(const Node* node) {
			if (node->node_type == NodeType::BINARY_OPERATOR) {
				return binary_level(node->value.type);
			}
			else if (node->node_type == NodeType::UNARY_OPERATOR) {
				if (is_prefix(node) || is_token(node, TokenType::SYM_QUESTION)) {
					return PREFIX;
				}
				if (is_token(node, TokenType::SYM_AMPERSAND)) {
					return ATOM;
				}
				return FALLBACK;
			}
			else if (node->node_type == NodeType::IF) {
				return FALLBACK;
			}
			else if (node->node_type == NodeType::LIST) {
				return ASSIGNMENT;
			}
			else if (node->node_type == NodeType::MATCH || node->node_type == NodeType::BLOCK) {
				return ANY;
			}
			else {
				return ATOM;
			}
		}

		bool is_type_node(const Node* node) {
			return NodeType::TYPE == node->node_type || NodeType::FUNCTION == node->node_type || NodeType::VOID == node->node_type;
		}

		// The = of a variable's definition, kept as an IDENTIFIER, or a constant's COLON.
		bool is_separator(const Node* node) {
			return NodeType::COLON == node->node_type
				|| (NodeType::IDENTIFIER == node->node_type && is_token(node, TokenType::OPERATOR_ASSIGN));
		}

		bool is_question(const Node* node) {
			return NodeType::UNARY_OPERATOR == node->node_type && node->children.empty() && is_token(node, TokenType::SYM_QUESTION);
		}

		struct Printer {
			const QuoteTable* quote_table = nullptr;
			size_t depth = 0;
			// The #code quotes being printed, innermost last, each with the next of its splices to print
			std::vector<std::pair<const Node*, size_t>> quotes;

			std::string indent() const {
				return std::string(depth * 4, ' ');
			}

			// ---------------------------------------------------------------------------------
			// Files and declarations

			std::string file(const Node* node) {
				std::string out;
				for (const Node* child : node->children) {
					if (NodeType::PACKAGE == child->node_type) {
						out += std::format("package {}\n\n", child->children.empty() ? "" : text_of(child->children[0]));
					}
					else {
						out += top_level(child) + "\n";
					}
				}
				return out;
			}

			std::string top_level(const Node* node) {
				if (NodeType::IMPORT == node->node_type) {
					return import(node);
				}
				if (NodeType::DIRECTIVE == node->node_type) {
					return top_level_directive(node);
				}
				return indent() + statement(node);
			}

			std::string import(const Node* node) {
				std::string out = indent() + "import";
				for (const Node* child : node->children) {
					if (NodeType::KEYWORD_AS == child->node_type) {
						out += " as";
					}
					else if (NodeType::KEYWORD_FROM == child->node_type) {
						out += " from";
					}
					else {
						out += std::format(" {}", text_of(child));
					}
				}
				return out;
			}

			// #if, #else_if and #else at the top level hold imports and declarations; #run and #assert an expression.
			std::string top_level_directive(const Node* node) {
				const std::string_view name = text_of(node);
				if (name == "#if" || name == "#else_if" || name == "#else") {
					std::string out = indent() + std::string(name);
					size_t first = 0;
					if (name != "#else" && !node->children.empty()) {
						out += " " + expression(node->children[0], ANY);
						first = 1;
					}
					out += " {\n";
					++depth;
					for (size_t i = first; i < node->children.size(); ++i) {
						out += top_level(node->children[i]) + "\n";
					}
					--depth;
					return out + indent() + "}";
				}
				return indent() + directive(node);
			}

			std::string names(const Node* node) {
				if (NodeType::LIST == node->node_type) {
					std::string out;
					for (size_t i = 0; i < node->children.size(); ++i) {
						out += (i > 0 ? ", " : "") + names(node->children[i]);
					}
					return out;
				}
				if (NodeType::UNDERSCORE == node->node_type) {
					return "_";
				}
				std::string out(text_of(node));
				for (const Node* child : node->children) {
					if (NodeType::DIRECTIVE == child->node_type) {
						out += " " + directive(child);
					}
				}
				return out;
			}

			/*
			 * A definition: names, the type if one is written, then :: or : for a constant, := or = for a
			 * variable, and the value. Annotations, which follow everything, go before it.
			 */
			std::string definition(const Node* node) {
				std::string prefix;
				std::string out = node->children.empty() ? "" : names(node->children[0]);
				bool is_using = false;
				size_t i = 1;
				const Node* written_type = nullptr;
				while (i < node->children.size() && !is_separator(node->children[i])) {
					const Node* child = node->children[i];
					if (NodeType::ANNOTATION == child->node_type) {
						prefix += std::string(text_of(child)) + "\n" + indent();
					}
					else if (NodeType::USING == child->node_type) {
						is_using = true;
					}
					else {
						written_type = child;
					}
					++i;
				}
				if (written_type != nullptr) {
					out += " : " + type(written_type, false);
				}
				if (i < node->children.size()) {
					const bool constant = NodeType::COLON == node->children[i]->node_type;
					if (written_type != nullptr) {
						out += constant ? " : " : " = ";
					}
					else {
						out += constant ? " :: " : " := ";
					}
					++i;
					out += value(node, i, prefix, is_using);
				}
				else if (written_type == nullptr) {
					out += " :";
				}
				return prefix + (is_using ? "using " : "") + out;
			}

			// What a definition's separator is followed by, from children[i] on.
			std::string value(const Node* node, size_t i, std::string& prefix, bool& is_using) {
				std::string out;
				bool first = true;
				for (; i < node->children.size(); ++i) {
					const Node* child = node->children[i];
					if (child->node_type == NodeType::ANNOTATION) {
						prefix += std::string(text_of(child)) + "\n" + indent();
						continue;
					}
					else if (child->node_type == NodeType::USING) {
						is_using = true;
						continue;
					}
					else if (child->node_type == NodeType::FUNCTION) {
						out += signature(child);
					}
					else if (child->node_type == NodeType::BLOCK) {
						out += " " + block(child);
					}
					else if (child->node_type == NodeType::STRUCT) {
						out += struct_declaration(child);
					}
					else if (child->node_type == NodeType::UNION) {
						out += union_declaration(child);
					}
					else if (child->node_type == NodeType::ENUM) {
						out += enum_declaration(child);
					}
					else if (child->node_type == NodeType::UNINITIALIZED) {
						out += "---";
					}
					else if (child->node_type == NodeType::KEYWORD_DISTINCT || child->node_type == NodeType::KEYWORD_ALIAS) {
						out += alias(node, i);
					}
					else {
						out += (first ? "" : " ") + expression(child, ANY);
					}
					first = false;
				}
				return out;
			}

			/*
			 * distinct alias[V] T #directives where C: the generic list and where clause are on the first
			 * word, the directives on alias, and the type after. i moves past what it prints.
			 */
			std::string alias(const Node* node, size_t& i) {
				const Node* first = node->children[i];
				const Node* alias_word = first;
				std::string out;
				if (NodeType::KEYWORD_DISTINCT == first->node_type) {
					out += "distinct ";
					if (i + 1 < node->children.size()) {
						alias_word = node->children[++i];
					}
				}
				out += "alias";
				for (const Node* child : first->children) {
					if (NodeType::GENERIC_TAG == child->node_type) {
						out += generic_list(child);
					}
				}
				if (i + 1 < node->children.size()) {
					out += " " + type(node->children[++i], false);
				}
				for (const Node* child : alias_word->children) {
					if (NodeType::DIRECTIVE == child->node_type) {
						out += " " + directive(child);
					}
				}
				for (const Node* child : first->children) {
					if (NodeType::WHERE_CLAUSE == child->node_type) {
						out += where_clause(child);
					}
				}
				return out;
			}

			std::string where_clause(const Node* node) {
				return node->children.empty() ? std::string(" where") : " where " + expression(node->children[0], ANY);
			}

			std::string struct_declaration(const Node* node) {
				std::string out = "struct";
				std::string members;
				++depth;
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::GENERIC_TAG) {
						out += generic_list(child);
					}
					else if (child->node_type == NodeType::DIRECTIVE) {
						out += " " + directive(child);
					}
					else if (child->node_type == NodeType::WHERE_CLAUSE) {
						out += where_clause(child);
					}
					else if (child->node_type == NodeType::USING) {
						members += indent() + "using " + qualified(child, 0) + ",\n";
					}
					else {
						members += indent() + definition(child) + ",\n";
					}
				}
				--depth;
				return out + " {\n" + members + indent() + "}";
			}

			std::string union_declaration(const Node* node) {
				std::string out = "union";
				std::string variants;
				++depth;
				for (size_t i = 0; i < node->children.size(); ++i) {
					const Node* child = node->children[i];
					if (NodeType::GENERIC_TAG == child->node_type) {
						out += generic_list(child);
					}
					else if (NodeType::WHERE_CLAUSE == child->node_type) {
						out += where_clause(child);
					}
					else if (NodeType::IDENTIFIER == child->node_type) {
						variants += indent() + std::string(text_of(child));
						if (i + 1 < node->children.size() && NodeType::PAREN_GROUP == node->children[i + 1]->node_type) {
							// A payload's function types are written without parentheses, which a union's payload doesn't take
							variants += "(" + list(node->children[++i]->children, [&](const Node* t) { return type(t, false); }) + ")";
						}
						variants += ",\n";
					}
				}
				--depth;
				return out + " {\n" + variants + indent() + "}";
			}

			std::string enum_declaration(const Node* node) {
				std::string out = "enum";
				std::string members;
				++depth;
				for (const Node* child : node->children) {
					if (NodeType::DIRECTIVE == child->node_type) {
						out += " " + directive(child);
						continue;
					}
					members += indent() + std::string(text_of(child));
					for (const Node* assign : child->children) {
						if (!assign->children.empty()) {
							members += " = " + expression(assign->children[0], ANY);
						}
					}
					members += ",\n";
				}
				--depth;
				return out + " {\n" + members + indent() + "}";
			}

			// ---------------------------------------------------------------------------------
			// Types

			/*
			 * A type where one goes. Function types are written in parentheses where they're a part of
			 * something else, which needs them in parameter and result lists, and lets a ? follow.
			 */
			std::string type(const Node* node, bool part) {
				if (node->node_type == NodeType::VOID) {
					return "void";
				}
				else if (node->node_type == NodeType::FUNCTION) {
					bool optional = false;
					for (const Node* child : node->children) {
						optional = optional || is_question(child);
					}
					if (part || optional) {
						return "(" + signature(node) + ")" + (optional ? "?" : "");
					}
					return signature(node);
				}
				else if (node->node_type == NodeType::TYPE) {
					return simple_type(node);
				}
				// An anonymous struct member's, like _ : struct #packed { ... }
				else if (node->node_type == NodeType::STRUCT) {
					return struct_declaration(node);
				}
				else {
					return expression(node, ANY);
				}
			}

			// mut, a name maybe qualified by package, generic arguments, dimensions, ?, and a result's directives.
			std::string simple_type(const Node* node) {
				std::string out;
				std::string after;
				bool mutable_type = false;
				out += text_of(node);
				for (size_t i = 0; i < node->children.size(); ++i) {
					const Node* child = node->children[i];
					if (child->node_type == NodeType::MUTABLE) {
						mutable_type = true;
					}
					else if (child->node_type == NodeType::DOT_ACCESS) {
						out += ".";
					}
					else if (child->node_type == NodeType::IDENTIFIER) {
						out += text_of(child);
					}
					else if (child->node_type == NodeType::GENERIC_TAG) {
						out += generic_list(child);
					}
					else if (child->node_type == NodeType::ARRAY_DIMENSION) {
						out += dimension(child);
					}
					else if (child->node_type == NodeType::UNARY_OPERATOR) {
						out += "?";
					}
					else if (child->node_type == NodeType::DIRECTIVE) {
						after += " " + directive(child);
					}
				}
				return (mutable_type ? "mut " : "") + out + after;
			}

			std::string dimension(const Node* node) {
				if (node->children.empty()) {
					return "[]";
				}
				if (node->children.size() == 1) {
					const Node* child = node->children[0];
					if (NodeType::RANGE_ARRAY == child->node_type) {
						return "[..]";
					}
					return "[" + expression(child, ANY) + "]";
				}
				return "[" + qualified(node, 0) + "]";
			}

			// A name and its package qualifiers, from children[first] on: net.MTU, compiler.TypeInfo.
			std::string qualified(const Node* node, size_t first) {
				std::string out;
				for (size_t i = first; i < node->children.size(); ++i) {
					const Node* child = node->children[i];
					out += NodeType::DOT_ACCESS == child->node_type ? std::string(".") : std::string(text_of(child));
				}
				return out;
			}

			std::string generic_list(const Node* node) {
				return "[" + list(node->children, [&](const Node* item) { return generic_item(item); }) + "]";
			}

			std::string generic_item(const Node* node) {
				if (NodeType::COLON == node->node_type && node->children.size() == 2) {
					return std::format("{}: {}", text_of(node->children[0]), type(node->children[1], true));
				}
				if (NodeType::DERIVED_PARAMETER == node->node_type) {
					return std::format("{} = {}", text_of(node), node->children.empty() ? "" : expression(node->children[0], ANY));
				}
				return is_type_node(node) ? type(node, true) : expression(node, ANY);
			}

			// fn[generics](parameters) -> results #directives where constraints
			std::string signature(const Node* node) {
				std::string out = "fn";
				bool seen_parameters = false;
				std::string after;
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::GENERIC_TAG) {
						out += generic_list(child);
					}
					else if (child->node_type == NodeType::LIST) {
						if (!seen_parameters) {
							seen_parameters = true;
							out += "(" + list(child->children, [&](const Node* p) { return parameter(p); }) + ")";
						}
						else {
							out += " -> (" + results(child) + ")";
						}
					}
					else if (child->node_type == NodeType::VOID) {
						out += " -> void";
					}
					else if (child->node_type == NodeType::TYPE) {
						out += " -> " + simple_type(child);
					}
					else if (child->node_type == NodeType::FUNCTION) {
						out += " -> " + type(child, true);
					}
					else if (child->node_type == NodeType::DIRECTIVE) {
						out += " " + directive(child);
					}
					else if (child->node_type == NodeType::WHERE_CLAUSE) {
						after += where_clause(child);
					}
				}
				if (!seen_parameters) {
					out.insert(out.find("fn") + 2, "()");
				}
				return out + after;
			}

			/*
			 * A parameter: names and a type (name, name2 #escaping : T...), or a type alone in a function
			 * type, with = default.
			 */
			std::string parameter(const Node* node) {
				if (NodeType::BINARY_OPERATOR == node->node_type && is_token(node, TokenType::OPERATOR_ASSIGN)
					&& !node->children.empty()) {
					const Node* names_and_type = node->children[0];
					const std::string value = node->children.size() > 1 ? expression(node->children[1], ANY) : "";
					const bool deduced = NodeType::COLON == names_and_type->node_type && names_and_type->children.size() == 1;
					if (deduced) {
						return names(names_and_type->children[0]) + " := " + value;
					}
					return parameter(names_and_type) + " = " + value;
				}
				if (NodeType::COLON != node->node_type) {
					return type(node, true) + varargs(node);
				}
				std::string out;
				std::string type_text;
				bool is_varargs = false;
				for (const Node* part : node->children) {
					if (NodeType::ELLIIPSIS == part->node_type) {
						is_varargs = true;
					}
					else if (out.empty() && (NodeType::IDENTIFIER == part->node_type || NodeType::LIST == part->node_type)) {
						out = names(part);
					}
					else {
						type_text = type(part, true) + varargs(part);
					}
				}
				return out + ": " + type_text + (is_varargs ? "..." : "");
			}

			std::string varargs(const Node* node) {
				for (const Node* child : node->children) {
					if (NodeType::ELLIIPSIS == child->node_type) {
						return "...";
					}
				}
				return "";
			}

			// Several results: types, or names sharing the type after a COLON, like a: u16, b, c: f32.
			std::string results(const Node* node) {
				std::string out;
				for (size_t i = 0; i < node->children.size(); ++i) {
					const Node* part = node->children[i];
					if (NodeType::COLON == part->node_type) {
						out += ": ";
						continue;
					}
					if (i > 0 && NodeType::COLON != node->children[i - 1]->node_type) {
						out += ", ";
					}
					out += type(part, true);
				}
				return out;
			}

			// ---------------------------------------------------------------------------------
			// Statements

			std::string block(const Node* node) {
				if (node->children.empty()) {
					return "{}";
				}
				++depth;
				std::string out = "{\n";
				for (const Node* child : node->children) {
					out += indent() + statement(child) + "\n";
				}
				--depth;
				return out + indent() + "}";
			}

			std::string statements(const Node* node) {
				std::string out;
				for (const Node* child : node->children) {
					out += indent() + statement(child) + "\n";
				}
				return out;
			}

			std::string statement(const Node* node) {
				if (node->node_type == NodeType::DEFINITION) {
					return definition(node);
				}
				else if (node->node_type == NodeType::RETURN) {
					std::string out = "return";
					for (size_t i = 0; i < node->children.size(); ++i) {
						const Node* child = node->children[i];
						out += (i > 0 ? ", " : " ") + (NodeType::VOID == child->node_type ? std::string("void") : expression(child, ANY));
					}
					return out;
				}
				else if (node->node_type == NodeType::DEFER) {
					return "defer " + (node->children.empty() ? std::string() : statement(node->children[0]));
				}
				else if (node->node_type == NodeType::BREAK) {
					std::string out = "break";
					for (const Node* child : node->children) {
						out += NodeType::KEYWORD_ALL == child->node_type ? std::string(" all") : " " + std::string(text_of(child));
					}
					return out;
				}
				else if (node->node_type == NodeType::CONTINUE) {
					return "continue";
				}
				else if (node->node_type == NodeType::DIRECTIVE) {
					return statement_directive(node);
				}
				else if (node->node_type == NodeType::FOR_LOOP) {
					return for_loop(node);
				}
				else if (node->node_type == NodeType::LOOP) {
					return loop(node);
				}
				else if (node->node_type == NodeType::PUSH_CONTEXT) {
					return push_context(node);
				}
				else if (node->node_type == NodeType::SWITCH) {
					return switch_statement(node);
				}
				else if (node->node_type == NodeType::USING) {
					return "using " + qualified(node, 0);
				}
				else {
					return expression(node, ANY);
				}
			}

			// #if, #else_if and #else in a body hold a block; the rest are directives in an expression.
			std::string statement_directive(const Node* node) {
				const std::string_view name = text_of(node);
				if (name == "#if" || name == "#else_if" || name == "#else") {
					std::string out(name);
					for (const Node* child : node->children) {
						out += " " + (NodeType::BLOCK == child->node_type ? block(child) : expression(child, ANY));
					}
					return out;
				}
				return directive(node);
			}

			// for &value, index in iterable #directives { body }: the names, IN, the iterable, directives, the block.
			std::string for_loop(const Node* node) {
				std::string out = "for ";
				size_t i = 0;
				bool first_name = true;
				for (; i < node->children.size() && NodeType::IN != node->children[i]->node_type; ++i) {
					const Node* name = node->children[i];
					out += first_name ? "" : ", ";
					first_name = false;
					if (NodeType::UNARY_OPERATOR == name->node_type) {
						out += "&" + std::string(name->children.empty() ? "" : text_of(name->children[0]));
					}
					else {
						out += text_of(name);
					}
				}
				out += " in ";
				++i;
				if (i < node->children.size()) {
					out += expression(node->children[i], ANY);
					++i;
				}
				for (; i < node->children.size(); ++i) {
					const Node* child = node->children[i];
					out += " " + (NodeType::BLOCK == child->node_type ? block(child) : directive(child));
				}
				return out;
			}

			// with { definitions } loop #directive { body } while condition
			std::string loop(const Node* node) {
				std::string out;
				std::string after;
				std::string loop_directive;
				std::string body;
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::WITH_CLAUSE) {
						out += "with {\n";
						++depth;
						for (const Node* definitions : child->children) {
							for (const Node* definition_node : definitions->children) {
								out += indent() + definition(definition_node) + "\n";
							}
						}
						--depth;
						out += indent() + "}\n" + indent();
					}
					else if (child->node_type == NodeType::DIRECTIVE) {
						loop_directive = " " + directive(child);
					}
					else if (child->node_type == NodeType::BLOCK) {
						body = " " + block(child);
					}
					else if (child->node_type == NodeType::WHILE_CLAUSE) {
						after = "\n" + indent() + "while " + (child->children.empty() ? std::string() : expression(child->children[0], ANY));
					}
				}
				return out + "loop" + loop_directive + body + after;
			}

			std::string push_context(const Node* node) {
				std::string out = "push_context";
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::IDENTIFIER) {
						out += " " + std::string(text_of(child));
					}
					else if (child->node_type == NodeType::KEYWORD_FROM) {
						out += " from " + (child->children.empty() ? std::string() : expression(child->children[0], ANY));
					}
					else if (child->node_type == NodeType::LIST) {
						out += " (" + list(child->children, [&](const Node* assign) { return field_value(assign); }) + ")";
					}
					else if (child->node_type == NodeType::BLOCK) {
						out += " " + block(child);
					}
				}
				return out;
			}

			std::string field_value(const Node* assign) {
				if (NodeType::BINARY_OPERATOR == assign->node_type && is_token(assign, TokenType::OPERATOR_ASSIGN)
					&& assign->children.size() == 2) {
					return std::format("{} = {}", text_of(assign->children[0]), argument(assign->children[1]));
				}
				return expression(assign, ANY);
			}

			std::string switch_statement(const Node* node) {
				std::string out = "switch " + (node->children.empty() ? std::string() : expression(node->children[0], ANY)) + " {\n";
				if (node->children.size() > 1) {
					for (const Node* item : node->children[1]->children) {
						if (NodeType::DIRECTIVE == item->node_type) {
							++depth;
							out += indent() + directive(item) + "\n";
							--depth;
							continue;
						}
						std::string entries;
						const Node* body = nullptr;
						for (const Node* part : item->children) {
							if (NodeType::BLOCK == part->node_type) {
								body = part;
							}
							else {
								entries += (entries.empty() ? "" : ", ") + case_entry(part);
							}
						}
						out += indent() + "case " + entries + ":\n";
						if (body != nullptr) {
							++depth;
							out += statements(body);
							--depth;
						}
					}
				}
				return out + indent() + "}";
			}

			// A case's or arm's entry: a literal, a range, Enum.Member, .Member, _, or a pattern like Some(x).
			std::string case_entry(const Node* node) {
				if (node->node_type == NodeType::BINARY_OPERATOR) {
					return node->children.size() == 2
						? std::format("{}{}{}", text_of(node->children[0]), operator_text(node->value.type), text_of(node->children[1]))
						: std::string();
				}
				else if (node->node_type == NodeType::DOT_ACCESS) {
					return node->children.size() == 2 ? std::format("{}.{}", text_of(node->children[0]), text_of(node->children[1])) : std::string();
				}
				else if (node->node_type == NodeType::UNDERSCORE) {
					return "_";
				}
				else if (node->node_type == NodeType::IDENTIFIER) {
					std::string out(text_of(node));
					for (const Node* child : node->children) {
						if (NodeType::PAREN_GROUP == child->node_type) {
							out += "(" + list(child->children, [&](const Node* p) { return case_entry(p); }) + ")";
						}
					}
					return out;
				}
				else {
					return expression(node, ANY);
				}
			}

			std::string match(const Node* node) {
				std::string out = "match " + (node->children.empty() ? std::string() : expression(node->children[0], ANY)) + " {\n";
				++depth;
				if (node->children.size() > 1) {
					for (const Node* arm : node->children[1]->children) {
						std::string entries;
						for (size_t i = 0; i + 1 < arm->children.size(); ++i) {
							entries += (i > 0 ? ", " : "") + case_entry(arm->children[i]);
						}
						out += indent() + "case " + entries + " => " + (arm->children.empty() ? std::string() : statement(arm->children.back())) + "\n";
					}
				}
				--depth;
				return out + indent() + "}";
			}

			// ---------------------------------------------------------------------------------
			// Expressions

			template <typename F>
			std::string list(const MyVector<Node*>& items, F each) {
				std::string out;
				for (size_t i = 0; i < items.size(); ++i) {
					out += (i > 0 ? ", " : "") + each(items[i]);
				}
				return out;
			}

			std::string expression(const Node* node, int needed) {
				if (level_of(node) < needed) {
					return "(" + expression(node, ANY) + ")";
				}
				if (node->node_type == NodeType::LITERAL) {
					return literal(node);
				}
				else if (node->node_type == NodeType::IDENTIFIER || node->node_type == NodeType::PIPE_REORDER_IDENTIFIER) {
					return std::string(text_of(node)) + chain(node, 0);
				}
				else if (node->node_type == NodeType::UNDERSCORE) {
					return "_";
				}
				else if (node->node_type == NodeType::VOID) {
					return "void";
				}
				else if (node->node_type == NodeType::RANGE_ARRAY) {
					return "..";
				}
				else if (node->node_type == NodeType::UNINITIALIZED) {
					return "---";
				}
				else if (node->node_type == NodeType::TYPE || node->node_type == NodeType::FUNCTION) {
					return type(node, true);
				}
				else if (node->node_type == NodeType::PAREN_GROUP) {
					return "(" + (node->children.empty() ? std::string() : expression(node->children[0], ANY)) + ")";
				}
				else if (node->node_type == NodeType::BINARY_OPERATOR) {
					return binary(node);
				}
				else if (node->node_type == NodeType::UNARY_OPERATOR) {
					return unary(node);
				}
				else if (node->node_type == NodeType::CAST) {
					return cast(node);
				}
				else if (node->node_type == NodeType::STRUCT_LITERAL) {
					return typed_literal(node, ".{", "}");
				}
				else if (node->node_type == NodeType::ARRAY_LITERAL) {
					return typed_literal(node, ".[", "]");
				}
				else if (node->node_type == NodeType::ENUM_SHORTHAND) {
					return "." + std::string(text_of(node)) + chain(node, 0);
				}
				else if (node->node_type == NodeType::IF) {
					return if_expression(node);
				}
				else if (node->node_type == NodeType::MATCH) {
					return match(node);
				}
				else if (node->node_type == NodeType::BLOCK) {
					return block(node);
				}
				else if (node->node_type == NodeType::LIST) {
					return list(node->children, [&](const Node* item) { return expression(item, FALLBACK); });
				}
				else if (node->node_type == NodeType::DIRECTIVE) {
					return directive(node);
				}
				else if (node->node_type == NodeType::DEFINITION) {
					return definition(node);
				}
				else if (node->node_type == NodeType::STRUCT) {
					return struct_declaration(node);
				}
				// Statements, which a match arm's body can be
				else if (node->node_type == NodeType::RETURN || node->node_type == NodeType::DEFER
					|| node->node_type == NodeType::BREAK || node->node_type == NodeType::CONTINUE
					|| node->node_type == NodeType::FOR_LOOP || node->node_type == NodeType::LOOP
					|| node->node_type == NodeType::PUSH_CONTEXT || node->node_type == NodeType::SWITCH
					|| node->node_type == NodeType::USING) {
					return statement(node);
				}
				else {
					return std::string(text_of(node));
				}
			}

			std::string literal(const Node* node) {
				std::string out(text_of(node));
				// A multiline string: a line per token, each starting with \\.
				for (const Node* line : node->children) {
					out += "\n" + indent() + std::string(text_of(line));
				}
				return out;
			}

			/*
			 * What follows a chain's head, from children[first] on: .name, [index], (arguments) and ^, each
			 * a marker followed by what belongs to it.
			 */
			std::string chain(const Node* node, size_t first) {
				std::string out;
				const auto& children = node->children;
				size_t i = first;
				while (i < children.size()) {
					const Node* marker = children[i];
					++i;
					if (!is_marker(marker)) {
						// Not a chain, like a match arm's pattern: written as it is
						out += expression(marker, ANY);
						continue;
					}
					if (NodeType::UNARY_OPERATOR == marker->node_type) {
						out += "^";
						continue;
					}
					if (NodeType::DOT_ACCESS == marker->node_type) {
						out += ".";
						if (i < children.size()) {
							out += text_of(children[i]);
							++i;
						}
						continue;
					}
					std::string inside;
					bool first_item = true;
					while (i < children.size() && !is_marker(children[i])) {
						const Node* item = children[i];
						inside += (first_item ? "" : ", ") + (NodeType::PAREN_GROUP == marker->node_type ? argument(item) : index(item));
						first_item = false;
						++i;
					}
					out += NodeType::PAREN_GROUP == marker->node_type ? "(" + inside + ")" : "[" + inside + "]";
				}
				return out;
			}

			std::string argument(const Node* node) {
				if (NodeType::BINARY_OPERATOR == node->node_type && is_token(node, TokenType::OPERATOR_ASSIGN)
					&& node->children.size() == 2 && NodeType::IDENTIFIER == node->children[0]->node_type
					&& node->children[0]->children.empty()) {
					return std::format("{} = {}", text_of(node->children[0]), argument(node->children[1]));
				}
				if (NodeType::TYPE == node->node_type) {
					return simple_type(node);
				}
				return expression(node, FALLBACK);
			}

			// What's between a chain's brackets: an index, an open range like ..<5 or 5.., or a type argument.
			std::string index(const Node* node) {
				if (NodeType::BINARY_OPERATOR == node->node_type && node->children.size() == 2) {
					if (NodeType::RANGE_ARRAY == node->children[0]->node_type) {
						return std::string(operator_text(node->value.type)) + expression(node->children[1], ANY);
					}
					if (NodeType::RANGE_ARRAY == node->children[1]->node_type) {
						return expression(node->children[0], ANY) + "..";
					}
				}
				// A function type as a value, like Callbacks[fn(int) -> bool], is written without parentheses there
				if (is_type_node(node)) {
					return type(node, false);
				}
				return expression(node, ANY);
			}

			std::string binary(const Node* node) {
				const TokenType op = node->value.type;
				if (node->children.empty()) {
					return std::string(operator_text(op));
				}
				const Node* lhs = node->children[0];
				// a |> f(b): the function's name and its arguments, in a PAREN_GROUP
				if (TokenType::OPERATOR_PIPE == op) {
					std::string out = expression(lhs, ATOM);
					for (size_t i = 1; i < node->children.size(); ++i) {
						const Node* part = node->children[i];
						if (NodeType::PAREN_GROUP == part->node_type) {
							out += "(" + list(part->children, [&](const Node* a) { return argument(a); }) + ")";
						}
						else {
							out += " |> " + std::string(text_of(part));
						}
					}
					return out;
				}
				const Node* rhs = node->children.size() > 1 ? node->children[1] : nullptr;
				/*
				 * What each side has to be, by where the parser parses it: the next level up, or the same on
				 * the side an operator groups to (left for arithmetic, right for || and &&).
				 */
				const int level = binary_level(op);
				int left = PRODUCT;
				int right = PREFIX;
				if (ASSIGNMENT == level) {
					left = FALLBACK;
					right = ANY;
				}
				else if (FALLBACK == level) {
					left = RANGE;
					right = ANY;
				}
				else if (RANGE == level) {
					left = OR;
					right = OR;
				}
				else if (OR == level) {
					left = AND;
					right = OR;
				}
				else if (AND == level) {
					left = COMPARISON;
					right = AND;
				}
				else if (COMPARISON == level) {
					left = SUM;
					right = SUM;
				}
				else if (SUM == level) {
					left = SUM;
					right = PRODUCT;
				}
				// An assignment's targets can be a list, and a range has no spaces
				std::string left_text = NodeType::LIST == lhs->node_type && ASSIGNMENT == binary_level(op)
					? expression(lhs, ANY) : expression(lhs, left);
				if (rhs == nullptr) {
					return left_text + " " + std::string(operator_text(op));
				}
				std::string right_text = NodeType::VOID == rhs->node_type ? std::string("void") : expression(rhs, right);
				if (RANGE == binary_level(op)) {
					return left_text + std::string(operator_text(op)) + right_text;
				}
				return std::format("{} {} {}", left_text, operator_text(op), right_text);
			}

			std::string unary(const Node* node) {
				if (node->children.empty()) {
					return std::string(operator_text(node->value.type));
				}
				const Node* operand = node->children[0];
				const TokenType op = node->value.type;
				if (TokenType::SYM_AMPERSAND == op) {
					return "&" + expression(operand, ATOM);
				}
				if (is_prefix(node)) {
					return std::string(operator_text(op)) + expression(operand, PREFIX);
				}
				if (TokenType::SYM_QUESTION == op) {
					// x?: its operand is a prefix operation or an atom, but not another ?
					const bool needs_parentheses = level_of(operand) < PREFIX || is_token(operand, TokenType::SYM_QUESTION);
					return (needs_parentheses ? "(" + expression(operand, ANY) + ")" : expression(operand, PREFIX)) + "?";
				}
				return expression(operand, RANGE) + " " + std::string(operator_text(op));
			}

			// cast[T](x), bit_cast[T](x) or auto_cast(x), and a chain after it.
			std::string cast(const Node* node) {
				std::string out(operator_text(node->value.type));
				size_t i = 0;
				if (!is_token(node, TokenType::KEYWORD_AUTO_CAST) && i < node->children.size()) {
					out += "[" + type(node->children[i], true) + "]";
					++i;
				}
				if (i < node->children.size()) {
					out += "(" + expression(node->children[i], ANY) + ")";
					++i;
				}
				return out + chain(node, i);
			}

			// Type.{...} or Type.[...], or .{...} for the type expected there.
			std::string typed_literal(const Node* node, std::string_view open, std::string_view close) {
				std::string out = is_token(node, TokenType::SYM_DOT) ? std::string() : std::string(text_of(node));
				const Node* items = nullptr;
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::DOT_ACCESS) {
						out += ".";
					}
					else if (child->node_type == NodeType::IDENTIFIER) {
						out += text_of(child);
					}
					else if (child->node_type == NodeType::GENERIC_TAG) {
						out += generic_list(child);
					}
					else if (child->node_type == NodeType::LIST) {
						items = child;
					}
				}
				out += open;
				if (items == nullptr || items->children.empty()) {
					return out + std::string(close);
				}
				const std::string inline_items = list(items->children, [&](const Node* item) { return field_value(item); });
				if (inline_items.size() <= 100 && inline_items.find('\n') == std::string::npos) {
					return out + inline_items + std::string(close);
				}
				// Long ones, like a table, an item to a line
				++depth;
				std::string lines = "\n";
				for (const Node* item : items->children) {
					lines += indent() + field_value(item) + ",\n";
				}
				--depth;
				return out + lines + indent() + std::string(close);
			}

			std::string if_expression(const Node* node) {
				std::string out = "if";
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::BLOCK) {
						out += " " + block(child);
					}
					else if (child->node_type == NodeType::ELSE) {
						out += " else";
						for (const Node* branch : child->children) {
							out += " " + (NodeType::IF == branch->node_type ? if_expression(branch) : block(branch));
						}
					}
					else {
						out += " " + expression(child, ANY);
					}
				}
				return out;
			}

			// A directive in an expression: alone, with an expression (#run x), or with arguments (#align(16)).
			std::string directive(const Node* node) {
				std::string out(text_of(node));
				if (out == "#code") {
					return quote(node);
				}
				// An #insert in a quote's tree: what its #code splices next
				if (out == "#insert" && node->children.empty() && !quotes.empty()) {
					auto& [splicing, next] = quotes.back();
					if (next < splicing->children.size()) {
						const Node* spliced = splicing->children[next++];
						// It's printed in the quote around this one
						const auto inner = quotes.back();
						quotes.pop_back();
						out += " " + expression(spliced, PREFIX);
						quotes.push_back(inner);
					}
					return out;
				}
				if (node->children.empty()) {
					return out;
				}
				if (is_marker(node->children[0]) && NodeType::PAREN_GROUP == node->children[0]->node_type) {
					std::string inside;
					for (size_t i = 1; i < node->children.size(); ++i) {
						inside += (i > 1 ? ", " : "") + argument(node->children[i]);
					}
					return out + "(" + inside + ")";
				}
				// #insert's operand binds like a prefix operator's; #run's and #assert's is an expression
				const int needed = out == "#insert" ? PREFIX : ANY;
				for (const Node* child : node->children) {
					out += " " + expression(child, needed);
				}
				return out;
			}
			// #code(expression) or #code { statements }, with what it splices where its #inserts are.
			std::string quote(const Node* node) {
				const Node* tree = quote_table != nullptr ? quote_table->get(node) : nullptr;
				if (tree == nullptr) {
					return "#code";
				}
				quotes.push_back({ node, 0 });
				std::string out = NodeType::BLOCK == tree->node_type ? "#code " + block(tree) : "#code(" + expression(tree, ANY) + ")";
				quotes.pop_back();
				return out;
			}
		};
	}

	std::string source_of(const Node* node, const QuoteTable* quotes) {
		if (node == nullptr) {
			return "";
		}
		Printer printer;
		printer.quote_table = quotes;
		if (NodeType::FILE == node->node_type) {
			return printer.file(node);
		}
		return printer.statement(node);
	}

	std::string source_of_statements(const Node* block, const QuoteTable* quotes) {
		if (block == nullptr) {
			return "";
		}
		Printer printer;
		printer.quote_table = quotes;
		return printer.statements(block);
	}

}
