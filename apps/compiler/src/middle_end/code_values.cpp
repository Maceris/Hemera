#include "middle_end/code_values.h"

#include <algorithm>
#include <cmath>
#include <iostream>
#include <format>
#include <mutex>
#include <string_view>
#include <unordered_map>

#include "parser/printing.h"

namespace hemera {

	namespace {

		bool is_directive(const ast::Node* node, std::string_view name) {
			return ast::NodeType::DIRECTIVE == node->node_type && node->value.value != nullptr && *node->value.value == name;
		}

		Token token_at(const Token& where, TokenType type, const std::string& text) {
			return Token(type, where.column_number, where.line_number, text.empty() ? nullptr : intern(text));
		}

		// Text as a string or character literal's, quotes and escapes included.
		std::string quoted_text(std::string_view text, char quote) {
			std::string out(1, quote);
			for (const char c : text) {
				if (c == '\\' || c == quote) {
					out += '\\';
					out += c;
				}
				else if (c == '\n') {
					out += "\\n";
				}
				else if (c == '\t') {
					out += "\\t";
				}
				else if (c == '\r') {
					out += "\\r";
				}
				else if (c == '\0') {
					out += "\\0";
				}
				else {
					out += c;
				}
			}
			return out + quote;
		}

		std::string utf8(uint64_t code_point) {
			std::string out;
			if (code_point < 0x80) {
				out += static_cast<char>(code_point);
			}
			else if (code_point < 0x800) {
				out += static_cast<char>(0xc0 | (code_point >> 6));
				out += static_cast<char>(0x80 | (code_point & 0x3f));
			}
			else if (code_point < 0x10000) {
				out += static_cast<char>(0xe0 | (code_point >> 12));
				out += static_cast<char>(0x80 | ((code_point >> 6) & 0x3f));
				out += static_cast<char>(0x80 | (code_point & 0x3f));
			}
			else {
				out += static_cast<char>(0xf0 | (code_point >> 18));
				out += static_cast<char>(0x80 | ((code_point >> 12) & 0x3f));
				out += static_cast<char>(0x80 | ((code_point >> 6) & 0x3f));
				out += static_cast<char>(0x80 | (code_point & 0x3f));
			}
			return out;
		}

		/*
		 * Copies a quote's tree, filling in its #inserts, with its nodes made in a program's NodeStore, whose
		 * lock is held meanwhile.
		 */
		struct Copier {
			ast::NodeStore& nodes;
			ast::QuoteTable& quotes;
			const std::vector<Spliced>& spliced;
			// Where nodes that have no origin come from: the quote's file
			std::shared_ptr<const ast::Origin> base_origin;
			// For a copy put somewhere by an #insert, where
			const ast::InsertionSite* site = nullptr;
			// How the site got where it is, when it was inserted itself
			const ast::Origin* at = nullptr;
			// For a macro's expansion, its mark, for what the macro wrote (docs/compilation.md, Macros)
			uint32_t expansion = 0;
			// The next of spliced to put in place
			size_t next = 0;
			// Each origin a copied node had, with site after it
			std::unordered_map<const ast::Origin*, std::shared_ptr<const ast::Origin>> inserted_origins = {};

			// A new node, from the quote unless copy says otherwise.
			ast::Node* make(ast::NodeType type, Token value) {
				ast::Node* node = nodes.make(type, value);
				nodes.set_origin(node, base_origin);
				return node;
			}

			// Where the copy of original comes from: where original does, and the #insert putting it here.
			std::shared_ptr<const ast::Origin> origin_of(const ast::Node* original) {
				std::shared_ptr<const ast::Origin> origin = nodes.origin(original);
				if (origin == nullptr) {
					origin = base_origin;
				}
				// A macro's argument stays the caller's code, with the caller's mark
				const bool to_caller = site == nullptr && base_origin->from_caller && !origin->from_caller;
				if (site == nullptr && !to_caller) {
					return origin;
				}
				std::shared_ptr<const ast::Origin>& derived = inserted_origins[origin.get()];
				if (derived == nullptr) {
					auto made = std::make_shared<ast::Origin>(*origin);
					if (to_caller) {
						made->from_caller = true;
					}
					else {
						if (at != nullptr) {
							made->inserted.insert(made->inserted.end(), at->inserted.begin(), at->inserted.end());
						}
						made->inserted.push_back(*site);
						// Expanded, the caller's code is the caller's again, and what the macro wrote is marked
						if (expansion != 0) {
							if (made->from_caller) {
								made->from_caller = false;
							}
							else {
								made->mark = expansion;
							}
						}
					}
					derived = made;
				}
				return derived;
			}

			// A literal's node, negated with a unary minus when the value is negative, at where.
			ast::Node* literal_node(const Token& where, TokenType type, const std::string& text, bool negative) {
				ast::Node* literal = make(ast::NodeType::LITERAL, token_at(where, type, text));
				if (!negative) {
					return literal;
				}
				ast::Node* minus = make(ast::NodeType::UNARY_OPERATOR, token_at(where, TokenType::OPERATOR_MINUS, ""));
				minus->children.push_back(literal);
				return minus;
			}

			/*
			 * What one #insert puts at where: a copy of a Code's tree, the type itself, or a literal. A type
			 * node holds its type, so nothing is looked up by name for it.
			 */
			ast::Node* spliced_node(const Token& where, const Spliced& value) {
				if (value.kind == Spliced::Kind::CODE) {
					return value.tree != nullptr ? copy(value.tree, false) : nullptr;
				}
				else if (value.kind == Spliced::Kind::TYPE) {
					ast::Node* type = make(ast::NodeType::TYPE, token_at(where, TokenType::IDENTIFIER, to_string(value.type)));
					type->type = const_cast<TypeInfo*>(value.type);
					return type;
				}
				else if (value.kind == Spliced::Kind::INTEGER) {
					return literal_node(where, TokenType::LITERAL_INTEGER, std::to_string(value.magnitude), value.negative);
				}
				else if (value.kind == Spliced::Kind::FLOAT) {
					std::string text = std::format("{}", std::fabs(value.floating));
					if (text.find_first_of(".e") == std::string::npos) {
						text += ".0";
					}
					else if (text.find('.') == std::string::npos) {
						text.insert(text.find('e'), ".0");
					}
					return literal_node(where, TokenType::LITERAL_FLOATING_POINT, text, std::signbit(value.floating));
				}
				else if (value.kind == Spliced::Kind::BOOLEAN) {
					return literal_node(where, value.magnitude != 0 ? TokenType::KEYWORD_TRUE : TokenType::KEYWORD_FALSE,
						value.magnitude != 0 ? "true" : "false", false);
				}
				else if (value.kind == Spliced::Kind::CHARACTER) {
					return literal_node(where, TokenType::LITERAL_CHAR, quoted_text(utf8(value.magnitude), '\''), false);
				}
				else if (value.kind == Spliced::Kind::STRING) {
					return literal_node(where, TokenType::LITERAL_STRING, quoted_text(value.text, '"'), false);
				}
				else if (value.kind == Spliced::Kind::ENUM_MEMBER) {
					// The enum, as its type, then .Member
					ast::Node* name = make(ast::NodeType::IDENTIFIER, token_at(where, TokenType::IDENTIFIER, to_string(value.type)));
					name->type = const_cast<TypeInfo*>(value.type);
					name->children.push_back(make(ast::NodeType::DOT_ACCESS, token_at(where, TokenType::SYM_DOT, "")));
					name->children.push_back(make(ast::NodeType::IDENTIFIER, token_at(where, TokenType::IDENTIFIER, value.text)));
					return name;
				}
				return nullptr;
			}

			/*
			 * A copy of node, with each #insert in it (not in a #code within it) replaced by the next spliced
			 * value when splicing. Statements spliced into a block go in as its statements.
			 */
			ast::Node* copy(const ast::Node* node, bool splicing) {
				ast::Node* result = nodes.make(node->node_type, node->value);
				nodes.set_origin(result, origin_of(node));
				result->type = node->type;
				const bool nested_quote = is_directive(node, "#code");
				for (const ast::Node* child : node->children) {
					// Every #insert in a quote's tree is a place to splice, its operand gone to the #code node
					if (splicing && !nested_quote && is_directive(child, "#insert")) {
						if (next >= spliced.size()) {
							continue;
						}
						ast::Node* value = spliced_node(child->value, spliced[next++]);
						if (value == nullptr) {
							continue;
						}
						// A type given with mut, like ptr[mut #insert T], is given with mut
						for (const ast::Node* marker : child->children) {
							if (ast::NodeType::MUTABLE == marker->node_type && ast::NodeType::TYPE == value->node_type) {
								value->children.insert(value->children.begin(), copy(marker, false));
							}
						}
						const bool statements = ast::NodeType::BLOCK == node->node_type && ast::NodeType::BLOCK == value->node_type;
						if (statements || is_code_list(value)) {
							for (ast::Node* item : value->children) {
								result->children.push_back(item);
							}
							continue;
						}
						result->children.push_back(value);
						continue;
					}
					result->children.push_back(copy(child, splicing && !nested_quote));
				}
				// A quote in the copy quotes the same tree, which never changes
				if (nested_quote) {
					quotes.set(result, quotes.get(node), quotes.file_of(node));
				}
				return result;
			}
		};
	}

	const ast::Node* make_code(ast::NodeStore& nodes, ast::QuoteTable& quotes, const ast::Node* quote,
		const std::vector<Spliced>& spliced) {
		const ast::Node* tree = quotes.get(quote);
		if (tree == nullptr) {
			return nullptr;
		}
		auto origin = std::make_shared<ast::Origin>();
		origin->file = quotes.file_of(quote);
		origin->from_caller = quotes.from_caller(quote);
		const std::unique_lock<std::mutex> lock = nodes.hold();
		Copier copier{ nodes, quotes, spliced, origin };
		// The quote's own root can be an #insert, as in #code(#insert x)
		if (is_directive(tree, "#insert") && tree->children.empty()) {
			return spliced.empty() ? nullptr : copier.spliced_node(tree->value, spliced[0]);
		}
		return copier.copy(tree, true);
	}

	bool is_code_list(const ast::Node* tree) {
		return tree != nullptr && ast::NodeType::LIST == tree->node_type && tree->value.value != nullptr
			&& *tree->value.value == CODE_LIST;
	}

	namespace {
		// A node of code made from a value, from file, at line.
		ast::Node* made(ast::NodeStore& nodes, const std::shared_ptr<const ast::Origin>& origin, ast::NodeType type,
			TokenType token_type, std::string_view text, uint32_t line) {
			ast::Node* node = nodes.make(type, Token(token_type, 0, line, text.empty() ? nullptr : intern(std::string(text))));
			nodes.set_origin(node, origin);
			return node;
		}

		std::shared_ptr<const ast::Origin> origin_in(const std::string& file) {
			auto origin = std::make_shared<ast::Origin>();
			origin->file = file;
			return origin;
		}
	}

	const ast::Node* make_name(ast::NodeStore& nodes, std::string_view name, const std::string& file, uint32_t line) {
		const std::unique_lock<std::mutex> lock = nodes.hold();
		return made(nodes, origin_in(file), ast::NodeType::IDENTIFIER, TokenType::IDENTIFIER, name, line);
	}

	const ast::Node* make_value(ast::NodeStore& nodes, ast::QuoteTable& quotes, const Spliced& value, const std::string& file,
		uint32_t line) {
		const std::vector<Spliced> none;
		const std::unique_lock<std::mutex> lock = nodes.hold();
		Copier copier{ nodes, quotes, none, origin_in(file) };
		return copier.spliced_node(Token(TokenType::IDENTIFIER, 0, line), value);
	}

	const ast::Node* make_list(ast::NodeStore& nodes, const std::vector<const ast::Node*>& items, const std::string& file,
		uint32_t line) {
		const std::unique_lock<std::mutex> lock = nodes.hold();
		ast::Node* list = made(nodes, origin_in(file), ast::NodeType::LIST, TokenType::IDENTIFIER, CODE_LIST, line);
		for (const ast::Node* item : items) {
			// Trees never change once made, so a list can hold another Code's; statements are each an item
			if (ast::NodeType::BLOCK == item->node_type || is_code_list(item)) {
				for (ast::Node* statement : item->children) {
					list->children.push_back(statement);
				}
				continue;
			}
			list->children.push_back(const_cast<ast::Node*>(item));
		}
		return list;
	}

	const ast::Node* make_parameters(ast::NodeStore& nodes, TypeInfoFunction const* function, bool as_arguments,
		const std::string& file, uint32_t line) {
		const std::unique_lock<std::mutex> lock = nodes.hold();
		const std::shared_ptr<const ast::Origin> origin = origin_in(file);
		ast::Node* list = made(nodes, origin, ast::NodeType::LIST, TokenType::IDENTIFIER, CODE_LIST, line);
		for (size_t i = 0; i < function->input.size(); ++i) {
			const FunctionInput& input = function->input[i];
			const std::string name = input.name != nullptr ? std::string(*input.name) : std::format("p{}", i);
			ast::Node* name_node = made(nodes, origin, ast::NodeType::IDENTIFIER, TokenType::IDENTIFIER, name, line);
			if (as_arguments) {
				list->children.push_back(name_node);
				continue;
			}
			// name: Type, the type as itself
			ast::Node* parameter = made(nodes, origin, ast::NodeType::COLON, TokenType::SYM_COLON, "", line);
			ast::Node* type = made(nodes, origin, ast::NodeType::TYPE, TokenType::IDENTIFIER, to_string(input.type), line);
			type->type = input.type;
			parameter->children.push_back(name_node);
			parameter->children.push_back(type);
			if (input.is_varargs) {
				parameter->children.push_back(made(nodes, origin, ast::NodeType::ELLIIPSIS, TokenType::SYM_ELLIPSIS, "", line));
			}
			list->children.push_back(parameter);
		}
		return list;
	}

	const ast::Node* copy_to_insert(ast::NodeStore& nodes, ast::QuoteTable& quotes, const ast::Node* tree,
		const ast::InsertionSite& site, const ast::Origin* at, bool hygienic) {
		if (tree == nullptr) {
			return nullptr;
		}
		auto origin = std::make_shared<ast::Origin>();
		origin->file = site.file;
		const std::vector<Spliced> none;
		const uint32_t expansion = hygienic ? nodes.new_mark() : 0;
		const std::unique_lock<std::mutex> lock = nodes.hold();
		Copier copier{ nodes, quotes, none, origin, &site };
		copier.at = at;
		copier.expansion = expansion;
		return copier.copy(tree, false);
	}

	void show_inserted(const Options* options, const ast::InsertionSite& site, const ast::Node* tree,
		const ast::QuoteTable& quotes) {
		if (options == nullptr) {
			return;
		}
		std::string file = site.file;
		std::replace(file.begin(), file.end(), '\\', '/');
		for (const auto& [wanted, line] : options->show_inserted) {
			if (line == site.line && file.ends_with(wanted)) {
				std::string source = code_source(tree, quotes);
				if (!source.ends_with('\n')) {
					source += '\n';
				}
				std::cout << std::format("// Inserted at {}({},{}):\n{}", site.file, site.line, site.column, source);
				std::cout.flush();
			}
		}
	}

	std::string code_source(const ast::Node* tree, const ast::QuoteTable& quotes) {
		if (tree == nullptr) {
			return "";
		}
		if (ast::NodeType::BLOCK == tree->node_type) {
			return ast::source_of_statements(tree, &quotes);
		}
		return ast::source_of(tree, &quotes);
	}

}
