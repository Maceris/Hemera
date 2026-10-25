#include <format>

#include "error/reporting.h"

#include "parser/parser.h"
#include "util/logger.h"

namespace hemera::parser {

	ParserState::ParserState(std::string_view file_path, 
		MyVector<Token>& tokens, Allocator<ast::Node> node_alloc, ast::QuoteTable* quotes)
		: current{ 0 }
		, tokens{ tokens }
		, node_alloc{ node_alloc }
		, file_path{ file_path }
		, quotes{ quotes }
		, has_errors{ false }
	{}
	ParserState::ParserState(const ParserState&) = default;
	ParserState::~ParserState() = default;

	ExprResult::ExprResult(bool success, ast::Node* result)
		: success{ success }
		, result{ result }
	{}
	ExprResult::ExprResult(const ExprResult&) = default;
	ExprResult::ExprResult(ExprResult&&) = default;
	ExprResult& ExprResult::operator=(const ExprResult&) = default;
	ExprResult& ExprResult::operator=(ExprResult&&) = default;
	ExprResult::~ExprResult() = default;

	static inline size_t clamp_index(size_t index, size_t size) {
		static const size_t ZERO = 0;
		return std::max(ZERO, std::min(size - 1, index));
	}

	static inline Token current_token(ParserState* state) {
		size_t index = clamp_index(state->current, state->tokens.size());
		return state->tokens[index];
	}

	static inline Token next_token(ParserState* state, size_t offset = 1) {
		size_t index = clamp_index(state->current + offset,
			state->tokens.size());
		return state->tokens[index];
	}

	static inline void report_error_on_last_token(ParserState* state,
		ErrorCode code) {
		Token token = current_token(state);
		report_error(code, state->file_path, token.line_number,
			token.column_number);
		state->has_errors = true;
	}

	static inline void report_error_on_last_token(ParserState* state,
		ErrorCode code, std::string_view additional_info) {
		Token token = current_token(state);
		report_error(code, state->file_path, token.line_number, 
			token.column_number, additional_info);
		state->has_errors = true;
	}

	static void delete_node(Allocator<ast::Node>& node_alloc, ast::Node* node) {
		if (node == nullptr) {
			return;
		}
		for (ast::Node* child : node->children) {
			delete_node(node_alloc, child);
		}
		node->children.clear();
		node_alloc.delete_object<ast::Node>(node);
	}

	/// <summary>
	/// Quick type deduction for obvious types.
	/// </summary>
	/// <param name="node">The node to check.</param>
	static void type_check_node(ast::Node* node) {
		LOG_ASSERT(node != nullptr);
		if (node == nullptr) {
			return;
		}

		ast::NodeType type = node->node_type;
		TokenType token_type = node->value.type;

		if (type == ast::NodeType::LITERAL) {
			if (token_type == TokenType::LITERAL_CHAR) {
				node->type = BUILTIN_char;
			}
			if (token_type == TokenType::LITERAL_FLOATING_POINT) {
				node->type = BUILTIN_f64;
			}
			if (token_type == TokenType::LITERAL_INTEGER) {
				node->type = BUILTIN_int;
			}
			if (token_type == TokenType::LITERAL_STRING) {
				node->type = BUILTIN_string;
			}
			if (token_type == TokenType::KEYWORD_TRUE) {
				node->type = BUILTIN_bool;
			}
			if (token_type == TokenType::KEYWORD_FALSE) {
				node->type = BUILTIN_bool;
			}
			if (token_type == TokenType::KEYWORD_NULL) {
				node->type = BUILTIN_void;
			}
		}
		//TODO(ches) handle more types here
	}

	ast::Node& next_as_node(ParserState* state, ast::NodeType type,
		ast::Node* parent) {
		Token current = current_token(state);
		ast::Node* result = state->node_alloc.new_object<ast::Node>(type, current);
		if (parent != nullptr) {
			parent->children.push_back(result);
		}
		state->current += 1;
		type_check_node(result);
		return *result;
	}

	bool accept(ParserState* state, TokenType token, ast::NodeType type,
		ast::Node& parent) {
		if (current_token(state).type == token) {
			Token current = current_token(state);
			ast::Node* child = state->node_alloc.new_object<ast::Node>(type, current);
			parent.children.push_back(child);
			state->current += 1;

			type_check_node(child);
			return true;
		}
		return false;
	}

	bool expect(ParserState* state, TokenType token) {
		return current_token(state).type == token;
	}

	bool skip(ParserState* state, TokenType token) {
		if (current_token(state).type == token) {
			state->current += 1;
			return true;
		}
		return false;
	}

	static bool could_be_function_input(const TokenType& type) {
		return TokenType::IDENTIFIER == type
			// A type given with mut, like compiler.Mutable(mut Config)
			|| TokenType::KEYWORD_MUT == type
			|| TokenType::SYM_AMPERSAND == type
			|| TokenType::SYM_UNDERSCORE == type
			|| TokenType::PIPE_REORDER_IDENTIFIER == type
			|| TokenType::DIRECTIVE == type
			|| TokenType::KEYWORD_MATCH == type
			|| TokenType::KEYWORD_IF == type
			|| TokenType::OPERATOR_PLUS == type
			|| TokenType::OPERATOR_MINUS == type
			|| TokenType::OPERATOR_BITWISE_XOR == type
			|| TokenType::OPERATOR_NOT == type
			|| TokenType::SYM_DOT == type
			|| TokenType::SYM_LPAREN == type
			|| TokenType::KEYWORD_AUTO_CAST == type
			|| TokenType::KEYWORD_BIT_CAST == type
			|| TokenType::KEYWORD_CAST == type
			|| TokenType::LITERAL_CHAR == type
			|| TokenType::LITERAL_FLOATING_POINT == type
			|| TokenType::LITERAL_IMAGINARY == type
			|| TokenType::LITERAL_INTEGER == type
			|| TokenType::LITERAL_STRING == type
			|| TokenType::KEYWORD_TRUE == type
			|| TokenType::KEYWORD_FALSE == type
			|| TokenType::KEYWORD_NULL == type
			;
	}

	// Whether this is one line of a multiline string, \\ followed by the text.
	static bool is_multiline_string_line(const Token& token) {
		return TokenType::LITERAL_STRING == token.type
			&& token.value != nullptr
			&& token.value->starts_with("\\\\");
	}

	/*
	 * Whether the tokens from the current one are the start of a declaration:
	 * names (or _) separated by commas, then a colon, like x : int or a, _ :: f().
	 */
	static bool is_declaration_start(ParserState* state) {
		for (size_t offset = 0;; offset += 2) {
			const TokenType name = next_token(state, offset).type;
			if (TokenType::IDENTIFIER != name && TokenType::SYM_UNDERSCORE != name) {
				return false;
			}
			// A name's directives, like owner #release :: open(path)
			while (TokenType::DIRECTIVE == next_token(state, offset + 1).type) {
				++offset;
			}
			const TokenType after = next_token(state, offset + 1).type;
			if (TokenType::SYM_COLON == after) {
				return true;
			}
			if (TokenType::SYM_COMMA != after) {
				return false;
			}
		}
	}

	// Whether an expression with a result could start with a token of this type.
	static bool could_start_expression(const TokenType& type) {
		return TokenType::IDENTIFIER == type
			|| TokenType::KEYWORD_MATCH == type
			|| TokenType::KEYWORD_IF == type
			|| TokenType::KEYWORD_TRUE == type
			|| TokenType::KEYWORD_FALSE == type
			|| TokenType::KEYWORD_NULL == type
			|| TokenType::KEYWORD_CAST == type
			|| TokenType::KEYWORD_BIT_CAST == type
			|| TokenType::KEYWORD_AUTO_CAST == type
			|| TokenType::LITERAL_CHAR == type
			|| TokenType::LITERAL_FLOATING_POINT == type
			|| TokenType::LITERAL_IMAGINARY == type
			|| TokenType::LITERAL_INTEGER == type
			|| TokenType::LITERAL_STRING == type
			|| TokenType::OPERATOR_PLUS == type
			|| TokenType::OPERATOR_MINUS == type
			|| TokenType::OPERATOR_BITWISE_XOR == type
			|| TokenType::OPERATOR_NOT == type
			|| TokenType::SYM_AMPERSAND == type
			|| TokenType::SYM_UNDERSCORE == type
			|| TokenType::SYM_DOT == type
			|| TokenType::SYM_LPAREN == type
			|| TokenType::SYM_LBRACE == type
			;
	}

	ast::Node* file(std::string_view file_path, MyVector<Token>& tokens,
		Allocator<ast::Node> node_alloc, ast::QuoteTable* quotes)
	{
		ParserState state(file_path, tokens, node_alloc, quotes);

		Token current(TokenType::START_OF_FILE, 0, 0);
		ast::Node* node = node_alloc.new_object<ast::Node>(ast::NodeType::FILE, current);

		//TODO(ches) stop bailing early and attempt to recover from errors
		const size_t errors_before = error_count();
		if (!package_statement(&state, *node)
			|| !imports(&state, *node)
			|| !const_definitions(&state, *node)) {
			/*
			 * Some failures don't report an error themselves; without this the rest of the file
			 * would be dropped silently. Another file's error can hide this, which only loses the
			 * generic message.
			 */
			if (error_count() == errors_before) {
				report_error_on_last_token(&state, ErrorCode::E3017);
			}
			return node;
		}
		if (!expect(&state, TokenType::END_OF_FILE)) {
			report_error_on_last_token(&state, ErrorCode::E3007);
		}

		return node;
	}

	/*
	 * Whether the token at offset is the word text: an identifier, since the contextual keywords
	 * (package, import, from, as, all, in, alias) are only keywords where they start their
	 * construct, and names everywhere else (docs/keywords.md).
	 */
	static bool where_clause(ParserState* state, ast::Node& parent);

	static bool is_word(ParserState* state, std::string_view text, size_t offset = 0) {
		const Token& token = offset == 0 ? current_token(state) : next_token(state, offset);
		return TokenType::IDENTIFIER == token.type && token.value != nullptr && *token.value == text;
	}

	// Whether a token is #run, whose value is a constant wherever a constant goes, like an array's count.
	static bool is_run(const Token& token) {
		return TokenType::DIRECTIVE == token.type && token.value != nullptr && *token.value == "#run";
	}

	// Whether a token can be a name where only a name can go: an identifier, or any keyword.
	static bool is_name(TokenType type) {
		return TokenType::IDENTIFIER == type
			|| (type >= TokenType::KEYWORD_AUTO_CAST && type <= TokenType::KEYWORD_WITH);
	}

	// A name where only a name can go, as an IDENTIFIER node under parent.
	static bool accept_name(ParserState* state, ast::Node& parent) {
		if (!is_name(current_token(state).type)) {
			return false;
		}
		next_as_node(state, ast::NodeType::IDENTIFIER, &parent);
		return true;
	}

	static bool is_insert(ParserState* state);
	static ExprResult insert_type(ParserState* state, ast::Node* mut);

	// An import, unless import is the name of a declaration (import :: ..., import #export : ...).
	static bool is_import(ParserState* state) {
		const TokenType next = next_token(state).type;
		return is_word(state, "import") && TokenType::SYM_COLON != next && TokenType::DIRECTIVE != next
			&& TokenType::SYM_COMMA != next;
	}

	bool package_statement(ParserState* state, ast::Node& parent) {
		if (!is_word(state, "package")) {
			report_error_on_last_token(state, ErrorCode::E3001);
			return false;
		}
		ast::Node& node = next_as_node(state, ast::NodeType::PACKAGE, &parent);

		if (!accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER, 
			node)) {
			report_error_on_last_token(state, ErrorCode::E3002);
			return false;
		}
		return true;
	}

	bool imports(ParserState* state, ast::Node& parent) {

		TokenType current_type = current_token(state).type;
		while (is_import(state)
			|| current_type == TokenType::DIRECTIVE
		) {
			if (current_type == TokenType::DIRECTIVE) {
				ast::Node& directive = next_as_node(state, ast::NodeType::DIRECTIVE, &parent);
				
				bool is_an_if = false;

				if (directive.value.value->compare("#if") == 0
					|| directive.value.value->compare("#else_if") == 0) {
					is_an_if = true;

					ExprResult conditional = expression_with_result(state, true);
					if (!conditional.success) {
						return false;
					}
					directive.children.push_back(conditional.result);
				}
		
				if (is_an_if || directive.value.value->compare("#else") == 0) {
					if (!expect(state, TokenType::SYM_LBRACE)) {
						report_error_on_last_token(state, ErrorCode::E3018);
						return false;
					}
					const Token& lbrace = current_token(state);
					skip(state, TokenType::SYM_LBRACE);
					if (!top_level_block(state, directive)) {
						return false;
					}
					if (!skip(state, TokenType::SYM_RBRACE)) {
						report_error_on_last_token(state, ErrorCode::E3019,
							std::format("Opening brace was at ({},{})",
								lbrace.line_number,
								lbrace.column_number));
						return false;
					}
				}

				// #run and #assert take an expression, #insert an operand (insert_operand)
				if (directive.value.value->compare("#run") == 0
					|| directive.value.value->compare("#assert") == 0
					|| directive.value.value->compare("#insert") == 0) {
					ExprResult expr = directive.value.value->compare("#insert") == 0 ? insert_operand(state)
						: expression_with_result(state, true);
					if (!expr.success) {
						return false;
					}
					directive.children.push_back(expr.result);
				}

			}
			else if (!import(state, parent)) {
				return false;
			}
			current_type = current_token(state).type;
		}
		return true;
	}

	/*
	 * The inside of a top-level #if, #else_if or #else block: imports and definitions, in any order,
	 * wherever the block is in the file.
	 */
	bool top_level_block(ParserState* state, ast::Node& parent) {
		while (true) {
			if (is_import(state)) {
				if (!import(state, parent)) {
					return false;
				}
			}
			else if (expect(state, TokenType::IDENTIFIER)
				|| expect(state, TokenType::DIRECTIVE)
				|| expect(state, TokenType::ANNOTATION)) {
				if (!const_definitions(state, parent)) {
					return false;
				}
			}
			else {
				return true;
			}
		}
	}

	bool import(ParserState* state, ast::Node& parent) {
		// The import word itself becomes the IMPORT node
		ast::Node& node = next_as_node(state, ast::NodeType::IMPORT, &parent);

		if (!accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER,
			node)) {
			report_error_on_last_token(state, ErrorCode::E3003);
			return false;
		}

		if (is_word(state, "as")) {
			next_as_node(state, ast::NodeType::KEYWORD_AS, &node);
			if (!accept(state, TokenType::IDENTIFIER,
				ast::NodeType::IDENTIFIER, node)) {
				report_error_on_last_token(state, ErrorCode::E3005);
				return false;
			}
		}

		if (is_word(state, "from")) {
			next_as_node(state, ast::NodeType::KEYWORD_FROM, &node);
			if (!accept(state, TokenType::LITERAL_STRING, 
				ast::NodeType::LITERAL, node)) {
				report_error_on_last_token(state, ErrorCode::E3004);
				return false;
			}
		}

		return true;
	}

	// A copy of a tree, for a part several definitions share once they're split apart.
	static ast::Node* clone_tree(ParserState* state, const ast::Node* node) {
		ast::Node* copy = state->node_alloc.new_object<ast::Node>(node->node_type, node->value);
		copy->type = node->type;
		for (const ast::Node* child : node->children) {
			copy->children.push_back(clone_tree(state, child));
		}
		return copy;
	}

	/*
	 * Several names at the top level, each with its value, like P, Q :: 4, 5 or R, S : u8 : 6, 7: a definition each, as if
	 * written apart, so each name's value is its own. Several names for one value, like a call's results, stay together.
	 */
	static void split_definition(ParserState* state, ast::Node& parent) {
		ast::Node* definition = parent.children.empty() ? nullptr : parent.children.back();
		if (definition == nullptr || ast::NodeType::DEFINITION != definition->node_type || definition->children.size() < 3) {
			return;
		}
		ast::Node* names = definition->children[0];
		ast::Node* values = definition->children.back();
		if (ast::NodeType::LIST != names->node_type || ast::NodeType::LIST != values->node_type
			|| names->children.size() != values->children.size()) {
			return;
		}
		parent.children.pop_back();
		for (size_t i = 0; i < names->children.size(); ++i) {
			ast::Node* single = state->node_alloc.new_object<ast::Node>(ast::NodeType::DEFINITION, definition->value);
			single->children.push_back(names->children[i]);
			// The type and the separator between, and any annotations after the value
			for (size_t j = 1; j + 1 < definition->children.size(); ++j) {
				single->children.push_back(clone_tree(state, definition->children[j]));
			}
			single->children.push_back(values->children[i]);
			parent.children.push_back(single);
		}
	}

	bool const_definitions(ParserState* state, ast::Node& parent) {
		while ((expect(state, TokenType::IDENTIFIER) && !is_import(state))
			|| expect(state, TokenType::DIRECTIVE)
			|| expect(state, TokenType::ANNOTATION)) {

			if (expect(state, TokenType::DIRECTIVE)) {
				ast::Node& directive = next_as_node(state, ast::NodeType::DIRECTIVE, &parent);

				bool is_an_if = false;

				if (directive.value.value->compare("#if") == 0
					|| directive.value.value->compare("#else_if") == 0) {
					is_an_if = true;

					ExprResult conditional = expression_with_result(state, true);
					if (!conditional.success) {
						return false;
					}
					directive.children.push_back(conditional.result);
				}

				if (is_an_if || directive.value.value->compare("#else") == 0) {
					if (!expect(state, TokenType::SYM_LBRACE)) {
						report_error_on_last_token(state, ErrorCode::E3018);
						return false;
					}
					const Token& lbrace = current_token(state);
					skip(state, TokenType::SYM_LBRACE);
					if (!top_level_block(state, directive)) {
						return false;
					}
					if (!skip(state, TokenType::SYM_RBRACE)) {
						report_error_on_last_token(state, ErrorCode::E3019,
							std::format("Opening brace was at ({},{})",
								lbrace.line_number,
								lbrace.column_number));
						return false;
					}
				}

				// #run and #assert take an expression, #insert an operand (insert_operand)
				if (directive.value.value->compare("#run") == 0
					|| directive.value.value->compare("#assert") == 0
					|| directive.value.value->compare("#insert") == 0) {
					ExprResult expr = directive.value.value->compare("#insert") == 0 ? insert_operand(state)
						: expression_with_result(state, true);
					if (!expr.success) {
						return false;
					}
					directive.children.push_back(expr.result);
					if (directive.value.value->compare("#insert") == 0 && expect(state, TokenType::SYM_COLON)) {
						parent.children.pop_back();
						if (!inserted_name_definition(state, parent, directive)) {
							return false;
						}
					}
				}
				continue;
			}

			MyVector<ast::Node*> annotations{};
			while (expect(state, TokenType::ANNOTATION)) {
				annotations.push_back(&next_as_node(state, ast::NodeType::ANNOTATION));
			}

			ExprResult decl = declaration(state, parent);

			if (!decl.success) {
				for (ast::Node* annotation : annotations) {
					delete_node(state->node_alloc, annotation);
				}
				return false;
			}
			for (ast::Node* annotation : annotations) {
				decl.result->children.push_back(annotation);
			}

			if (!const_definition_rhs(state, *decl.result)) {
				return false;
			}
			split_definition(state, parent);
		}
		return true;
	}

	bool any_definition(ParserState* state, ast::Node& parent) {
		ExprResult decl = declaration(state, parent);

		if (!decl.success) {
			return false;
		}

		if (expect(state, TokenType::SYM_COLON)) {
			return const_definition_rhs(state, *decl.result);
		}
		else if (expect(state, TokenType::OPERATOR_ASSIGN)) {
			return mut_definition_rhs(state, *decl.result);
		}
		else {
			report_error_on_last_token(state, ErrorCode::E3006);
			return false;
		}
	}

	bool const_definition_rhs(ParserState* state, ast::Node& parent) {
		if (!accept(state, TokenType::SYM_COLON, ast::NodeType::COLON, parent)) {
			report_error_on_last_token(state, ErrorCode::E3007);
			return false;
		}
		return decl_rhs(state, parent);
	}

	bool mut_definition_rhs(ParserState* state, ast::Node& parent) {
		if (!accept(state, TokenType::OPERATOR_ASSIGN, ast::NodeType::IDENTIFIER, parent)) {
			return false;
		}
		return decl_rhs(state, parent);
	}

	/*
	 * A directive, followed by its arguments if it has any, like #align(16),
	 * #backed_by(u8) or #calling_convention(.interrupt).
	 */
	ExprResult directive_with_arguments(ParserState* state, ast::Node* parent) {
		ast::Node& directive = next_as_node(state, ast::NodeType::DIRECTIVE, parent);

		if (expect(state, TokenType::SYM_LPAREN)) {
			const Token lparen = current_token(state);
			accept(state, TokenType::SYM_LPAREN, ast::NodeType::PAREN_GROUP, directive);

			if (could_be_function_input(current_token(state).type)
				&& !function_call_input_list(state, directive)) {
				return ExprResult{ false };
			}
			if (!skip(state, TokenType::SYM_RPAREN)) {
				report_error_on_last_token(state, ErrorCode::E3015,
					std::format("Opening parenthesis was at ({},{})",
						lparen.line_number,
						lparen.column_number));
				return ExprResult{ false };
			}
		}
		return ExprResult{ true, &directive };
	}

	ExprResult declaration(ParserState* state, ast::Node& parent) {
		if (!expect(state, TokenType::IDENTIFIER)
			&& !expect(state, TokenType::SYM_UNDERSCORE)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			return ExprResult{ false };
		}

		// Several names, like a, _ :: two_results(), are a list
		if (TokenType::SYM_COMMA == next_token(state).type) {
			ast::Node* names = nullptr;
			do {
				const bool is_underscore = expect(state, TokenType::SYM_UNDERSCORE);
				if (!is_underscore && !expect(state, TokenType::IDENTIFIER)) {
					report_error_on_last_token(state, ErrorCode::E3009);
					delete_node(state->node_alloc, names);
					return ExprResult{ false };
				}
				ast::Node& name = next_as_node(state, is_underscore
					? ast::NodeType::UNDERSCORE : ast::NodeType::IDENTIFIER);
				if (names == nullptr) {
					names = &next_as_node(state, ast::NodeType::LIST);
					names->children.push_back(&name);
				}
				else {
					names->children.push_back(&name);
					if (!skip(state, TokenType::SYM_COMMA)) {
						break;
					}
				}
			} while (true);

			if (!expect(state, TokenType::SYM_COLON)) {
				report_error_on_last_token(state, ErrorCode::E3010);
				delete_node(state->node_alloc, names);
				return ExprResult{ false };
			}
			return definition_after_names(state, parent, *names);
		}

		if (!expect(state, TokenType::IDENTIFIER)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			return ExprResult{ false };
		}
		ast::Node& lhs = next_as_node(state, ast::NodeType::IDENTIFIER);

		while (expect(state, TokenType::DIRECTIVE)) {
			ExprResult directive_result = directive_with_arguments(state, &lhs);
			if (!directive_result.success) {
				delete_node(state->node_alloc, &lhs);
				return ExprResult{ false };
			}
			const ast::Node& directive = *directive_result.result;

			bool expected = false;
			if (directive.value.value->compare("#export") == 0
				|| directive.value.value->compare("#calling_convention") == 0
				|| directive.value.value->compare("#no_context") == 0
				|| directive.value.value->compare("#never_returns") == 0
				|| directive.value.value->compare("#externally_initialized") == 0
				|| directive.value.value->compare("#section") == 0
				|| directive.value.value->compare("#foreign") == 0
				|| directive.value.value->compare("#link_name") == 0
				|| directive.value.value->compare("#target_features") == 0
				|| directive.value.value->compare("#constant_time") == 0
				|| directive.value.value->compare("#constraint") == 0
				|| directive.value.value->compare("#macro") == 0
				|| directive.value.value->compare("#release") == 0) {
				expected = true;
			}
			if (!expected) {
				report_error_on_last_token(state, ErrorCode::E3020);
				return false;
			}
		}

		if (!expect(state, TokenType::SYM_COLON)) {
			report_error_on_last_token(state, ErrorCode::E3010);
			delete_node(state->node_alloc, &lhs);
			return ExprResult{ false };
		}
		return definition_after_names(state, parent, lhs);
	}

	// The rest of a declaration once its names are parsed: the colon, and the type if there is one.
	ExprResult definition_after_names(ParserState* state, ast::Node& parent, ast::Node& names) {
		ast::Node& colon = next_as_node(state, ast::NodeType::DEFINITION, &parent);
		colon.children.push_back(&names);
		
		if (!expect(state, TokenType::SYM_COLON) 
			&& !expect(state, TokenType::OPERATOR_ASSIGN)) {
			// we aren't deducing the type, there's something here

			ExprResult rhs = type(state);
			if (!rhs.success) {
				return ExprResult{ false };
			}
			colon.children.push_back(rhs.result);
		}

		return ExprResult{ true, &colon };
	}

	bool decl_rhs(ParserState* state, ast::Node& parent) {
		const TokenType current_type = current_token(state).type;

		if (TokenType::KEYWORD_FN == current_type) {
			return function_decl(state, parent);
		}
		if (TokenType::KEYWORD_STRUCT == current_type) {
			return struct_decl(state, parent);
		}
		if (TokenType::KEYWORD_UNION == current_type) {
			return union_decl(state, parent);
		}
		if (TokenType::KEYWORD_ENUM == current_type) {
			return enum_decl(state, parent);
		}
		if (TokenType::SYM_UNINITIALIZED == current_type) {
			next_as_node(state, ast::NodeType::UNINITIALIZED, &parent);
			return true;
		}
		/*
		 * Anything starting with an identifier is parsed as an expression, which also covers
		 * naming a type (Foo :: Bar). alias is required after distinct, so that the word makes
		 * sense, and otherwise optional, showing the value is meant to be a type.
		 */
		const bool is_alias = is_word(state, "alias") && (TokenType::IDENTIFIER == next_token(state).type
			|| TokenType::KEYWORD_FN == next_token(state).type || TokenType::KEYWORD_MUT == next_token(state).type
			|| TokenType::SYM_LBRACK == next_token(state).type);
		if (TokenType::KEYWORD_DISTINCT == current_type || is_alias) {
			ast::Node* first = nullptr;
			if (expect(state, TokenType::KEYWORD_DISTINCT)) {
				first = &next_as_node(state, ast::NodeType::KEYWORD_DISTINCT, &parent);
				if (!is_word(state, "alias")) {
					report_error_on_last_token(state, ErrorCode::E3033);
					return false;
				}
			}
			ast::Node& alias = next_as_node(state, ast::NodeType::KEYWORD_ALIAS, &parent);
			if (first == nullptr) {
				first = &alias;
			}
			// A generic alias, like StringMap :: alias[V] HashMap[string, V, hash_string]: its list on the first word
			if (expect(state, TokenType::SYM_LBRACK) && !generic_tag(state, *first, true)) {
				return false;
			}

			ExprResult rhs = type(state);
			if (!rhs.success) {
				return false;
			}
			parent.children.push_back(rhs.result);
			// Like Word :: distinct alias u32 #secret: on its line, so a directive starting the next line, like #if, is its own
			while (expect(state, TokenType::DIRECTIVE) && state->current > 0
				&& current_token(state).line_number == state->tokens[state->current - 1].line_number) {
				next_as_node(state, ast::NodeType::DIRECTIVE, &alias);
			}
			return where_clause(state, *first);
		}
		// Several names take a value each, like x, y := 1, 2, or one for them all
		const bool several = !parent.children.empty() && ast::NodeType::LIST == parent.children[0]->node_type;
		ExprResult rhs = expression_with_result(state, !several);
		if (!rhs.success) {
			return false;
		}
		parent.children.push_back(rhs.result);
		return true;
	}

	bool function_decl(ParserState* state, ast::Node& parent) {
		ExprResult sig = function_signature(state);
		if (!sig.success) {
			return false;
		}
		parent.children.push_back(sig.result);

		if (!expect(state, TokenType::SYM_LBRACE)) {
			// We don't have a function body, can just stop now
			return true;
		}
		ExprResult result = block(state);
		if (!result.success) {
			return false;
		}
		parent.children.push_back(result.result);
		return true;
	}

	bool struct_decl(ParserState* state, ast::Node& parent) {
		ast::Node& node = next_as_node(state, ast::NodeType::STRUCT, &parent);

		if (expect(state, TokenType::SYM_LBRACK)) {
			if (!generic_tag(state, node, true)) {
				return false;
			}
		}

		while (expect(state, TokenType::DIRECTIVE)) {
			if (!directive_with_arguments(state, &node).success) {
				return false;
			}
		}
		if (!where_clause(state, node)) {
			return false;
		}

		if (!expect(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return false;
		}
		const Token& lbrace = current_token(state);
		skip(state, TokenType::SYM_LBRACE);
		if (!struct_body(state, node)) {
			return false;
		}
		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019,
				std::format("Opening brace was at ({},{})",
					lbrace.line_number,
					lbrace.column_number));
			return false;
		}
		return true;
	}

	bool union_decl(ParserState* state, ast::Node& parent) {
		if (!expect(state, TokenType::KEYWORD_UNION)) {
			return false;
		}
		ast::Node& node = next_as_node(state, ast::NodeType::UNION, &parent);

		if (expect(state, TokenType::SYM_LBRACK)) {
			if (!generic_tag(state, node, true)) {
				return false;
			}
		}
		if (!where_clause(state, node)) {
			return false;
		}
		if (!expect(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return false;
		}
		const Token& lbrace = current_token(state);
		skip(state, TokenType::SYM_LBRACE);

		if (!union_body(state, node)) {
			return false;
		}
		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019,
				std::format("Opening brace was at ({},{})",
					lbrace.line_number,
					lbrace.column_number));
			return false;
		}
		return true;
	}

	bool enum_decl(ParserState* state, ast::Node& parent) {
		if (!expect(state, TokenType::KEYWORD_ENUM)) {
			return false;
		}
		ast::Node& node = next_as_node(state, ast::NodeType::ENUM, &parent);

		while (expect(state, TokenType::DIRECTIVE)) {
			if (!directive_with_arguments(state, &node).success) {
				return false;
			}
		}

		if (!expect(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return false;
		}
		const Token& lbrace = current_token(state);
		skip(state, TokenType::SYM_LBRACE);
		if (!enum_body(state, node)) {
			return false;
		}
		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019,
				std::format("Opening brace was at ({},{})",
					lbrace.line_number,
					lbrace.column_number));
			return false;
		}
		return true;
	}

	/*
	 * A type in parentheses, like (mut u8[]) in ptr[mut (mut u8[])]: a PAREN_GROUP holding it, whose own mut, if mut
	 * comes before it, is a MUTABLE child after it, so the type inside keeps its own (docs/types.md, Mutability).
	 */
	static ExprResult parenthesized_type(ParserState* state, ast::Node* mut) {
		const Token lparen = current_token(state);
		ast::Node& group = next_as_node(state, ast::NodeType::PAREN_GROUP);
		ExprResult inner = type(state);
		if (!inner.success) {
			return inner;
		}
		group.children.push_back(inner.result);
		if (!skip(state, TokenType::SYM_RPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3015,
				std::format("Opening parenthesis was at ({},{})", lparen.line_number, lparen.column_number));
			return ExprResult{ false };
		}
		if (mut != nullptr) {
			group.children.push_back(mut);
		}
		accept(state, TokenType::SYM_QUESTION, ast::NodeType::UNARY_OPERATOR, group);
		return ExprResult{ true, &group };
	}

	ExprResult type(ParserState* state) {

		if (expect(state, TokenType::KEYWORD_MUT) && TokenType::SYM_LPAREN == next_token(state).type
			&& TokenType::KEYWORD_FN != next_token(state, 2).type) {
			ast::Node* mut = &next_as_node(state, ast::NodeType::MUTABLE);
			return parenthesized_type(state, mut);
		}
		if (expect(state, TokenType::KEYWORD_MUT) ||
			expect(state, TokenType::IDENTIFIER)) {
			return simple_type(state);
		}
		if (is_insert(state)) {
			return insert_type(state, nullptr);
		}
		// void as a type, like Result[void, MapError]: a result with nothing on success
		if (expect(state, TokenType::KEYWORD_VOID)) {
			return ExprResult{ true, &next_as_node(state, ast::NodeType::VOID) };
		}
		else if (expect(state, TokenType::KEYWORD_FN)) {
			ExprResult result = complicated_type(state);
			if (result.success) {
				accept(state, TokenType::SYM_QUESTION, ast::NodeType::UNARY_OPERATOR,
					*result.result);
			}
			return result;
		}
		// (fn(n: int) -> int)?: a function type in parentheses, so a ? after it is the function's, not its result's
		else if (expect(state, TokenType::SYM_LPAREN) && TokenType::KEYWORD_FN != next_token(state).type) {
			return parenthesized_type(state, nullptr);
		}
		else if (expect(state, TokenType::SYM_LPAREN) && TokenType::KEYWORD_FN == next_token(state).type) {
			const Token lparen = current_token(state);
			skip(state, TokenType::SYM_LPAREN);
			ExprResult result = complicated_type(state);
			if (!result.success) {
				return result;
			}
			if (!skip(state, TokenType::SYM_RPAREN)) {
				report_error_on_last_token(state, ErrorCode::E3015,
					std::format("Opening parenthesis was at ({},{})", lparen.line_number, lparen.column_number));
				return ExprResult{ false };
			}
			accept(state, TokenType::SYM_QUESTION, ast::NodeType::UNARY_OPERATOR, *result.result);
			return result;
		}
		else {
			report_error_on_last_token(state, ErrorCode::E3017);
			return ExprResult{ false };
		}
	}

	ExprResult simple_type(ParserState* state) {
		ast::Node* mut = nullptr;

		if (expect(state, TokenType::KEYWORD_MUT)) {
			mut = &next_as_node(state, ast::NodeType::MUTABLE);
		}
		if (is_insert(state)) {
			return insert_type(state, mut);
		}

		if (!expect(state, TokenType::IDENTIFIER)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			if (mut != nullptr) {
				delete_node(state->node_alloc, mut);
			}
			return ExprResult{ false };
		}
		ast::Node& type = next_as_node(state, ast::NodeType::TYPE);
		if (mut != nullptr) {
			type.children.push_back(mut);
		}
		// Qualified by package, like runtime.Fiber
		while (expect(state, TokenType::SYM_DOT)
			&& TokenType::IDENTIFIER == next_token(state).type) {
			accept(state, TokenType::SYM_DOT, ast::NodeType::DOT_ACCESS, type);
			accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER, type);
		}

		if (expect(state, TokenType::SYM_LBRACK)) {
			const TokenType next = next_token(state).type;
			const bool is_dimension = next == TokenType::LITERAL_INTEGER
				|| next == TokenType::OPERATOR_RANGE_ARRAY
				|| next == TokenType::SYM_RBRACK
				|| is_run(next_token(state))
				;
			if (!is_dimension && !generic_tag(state, type, false)) {
				delete_node(state->node_alloc, &type);
				return ExprResult{ false };
			}
		}
		while (expect(state, TokenType::SYM_LBRACK)) {
			if (!array_dimension(state, type)) {
				delete_node(state->node_alloc, &type);
				return ExprResult{ false };
			}
		}
		accept(state, TokenType::SYM_QUESTION, ast::NodeType::UNARY_OPERATOR, type);
		return ExprResult{ true, &type };
	}

	ExprResult complicated_type(ParserState* state) {
		if (expect(state, TokenType::KEYWORD_FN)) {
			return function_signature(state);
		}
		else {
			report_error_on_last_token(state, ErrorCode::E3017);
			return ExprResult{ false };
		}
	}

	// Whether a token continues a name into arithmetic, making it a value rather than a type.
	static bool is_arithmetic(TokenType type) {
		return TokenType::OPERATOR_PLUS == type || TokenType::OPERATOR_MINUS == type || TokenType::OPERATOR_MULTIPLY == type
			|| TokenType::OPERATOR_DIVIDE == type || TokenType::OPERATOR_MODULUS == type || TokenType::OPERATOR_LEFT_SHIFT == type
			|| TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL == type || TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC == type
			|| TokenType::SYM_AMPERSAND == type || TokenType::OPERATOR_BITWISE_OR == type;
	}

	bool array_dimension(ParserState* state, ast::Node& parent) {
		ast::Node& dims = next_as_node(state, ast::NodeType::ARRAY_DIMENSION,
			&parent);
		const bool simple = expect(state, TokenType::OPERATOR_RANGE_ARRAY) || expect(state, TokenType::SYM_RBRACK)
			|| ((expect(state, TokenType::LITERAL_INTEGER) || expect(state, TokenType::IDENTIFIER))
				&& TokenType::SYM_RBRACK == next_token(state).type);
		if (!simple) {
			// A constant expression, like [CAPACITY * 2], [(bits + 63) / 64] or [package.SIZE]
			ExprResult count = expression_with_result(state, true);
			if (!count.success) {
				return false;
			}
			dims.children.push_back(count.result);
		}
		else if (expect(state, TokenType::LITERAL_INTEGER)) {
			accept(state, TokenType::LITERAL_INTEGER, ast::NodeType::LITERAL,
				dims);
		}
		else if (expect(state, TokenType::OPERATOR_RANGE_ARRAY)) {
			accept(state, TokenType::OPERATOR_RANGE_ARRAY, 
				ast::NodeType::RANGE_ARRAY, dims);
		}
		else if (expect(state, TokenType::IDENTIFIER)) {
			// A named constant, like [QUEUE_SIZE]
			accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER, dims);
		}
		if (!skip(state, TokenType::SYM_RBRACK)) {
			report_error_on_last_token(state, ErrorCode::E3012, 
				std::format("Opening bracket was at ({},{})", 
					dims.value.line_number, dims.value.column_number));
			return false;
		}
		return true;
	}

	ExprResult function_signature(ParserState* state) {
		if (!expect(state, TokenType::KEYWORD_FN)) {
			report_error_on_last_token(state, ErrorCode::E3013);
			return ExprResult{ false };
		}

		ast::Node& node = next_as_node(state, ast::NodeType::FUNCTION);
		
		if (expect(state, TokenType::SYM_LBRACK)) {
			if (!generic_tag(state, node, true)) {
				delete_node(state->node_alloc, &node);
				return ExprResult{ false };
			}
		}
		if (!expect(state, TokenType::SYM_LPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3014);
			delete_node(state->node_alloc, &node);
			return ExprResult{ false };
		}
		const Token& lparen = current_token(state);
		if (!expect(state, TokenType::SYM_RPAREN)) {
			if (!function_parameter_list(state, node)) {
				delete_node(state->node_alloc, &node);
				return ExprResult{ false };
			}
		}
		if (!skip(state, TokenType::SYM_RPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3015,
				std::format("Opening parenthesis was at ({},{})",
					lparen.line_number,
					lparen.column_number));
			delete_node(state->node_alloc, &node);
			return ExprResult{ false };
		}
		if (skip(state, TokenType::SYM_ARROW_SINGLE)) {
			if (!function_output_list(state, node)) {
				delete_node(state->node_alloc, &node);
				return ExprResult{ false };
			}
		}
		/*
		 * #never_returns, #no_context and #unrestricted (every result) are part of the function's
		 * type. Only they continue a signature, since line breaks mean nothing, and the next
		 * statement may start with a directive (#if).
		 */
		while (expect(state, TokenType::DIRECTIVE)
			&& (current_token(state).value->compare("#never_returns") == 0
				|| current_token(state).value->compare("#no_context") == 0
				|| current_token(state).value->compare("#unrestricted") == 0)) {
			next_as_node(state, ast::NodeType::DIRECTIVE, &node);
		}
		if (!where_clause(state, node)) {
			delete_node(state->node_alloc, &node);
			return ExprResult{ false };
		}
		return ExprResult{ true, &node };
	}

	bool function_parameter_list(ParserState* state, ast::Node& parent) {
		ast::Node& node = next_as_node(state, ast::NodeType::LIST, &parent);

		TokenType token_type = current_token(state).type;

		while (TokenType::IDENTIFIER == token_type
			|| TokenType::KEYWORD_MUT == token_type
			|| TokenType::SYM_LPAREN == token_type
			|| TokenType::KEYWORD_FN == token_type
			|| is_insert(state)
			) {

			if (is_insert(state)) {
				if (!insert_item(state, node)) {
					return false;
				}
				token_type = current_token(state).type;
				continue;
			}

			if (expect(state, TokenType::KEYWORD_FN)) {
				// Missing paren for a function without an identifier
				//TODO(ches) add a test for this
				report_error_on_last_token(state, ErrorCode::E3008);
				return false;
			}

			ast::Node* param = nullptr;

			bool its_a_name = false;
			bool its_complicated = false;

			if (TokenType::SYM_LPAREN == token_type) {
				// fn type
				its_complicated = true;
			}
			else {
				// identifier, ambiguous
				const TokenType next_type = next_token(state).type;

				if (TokenType::SYM_COLON == next_type
					|| TokenType::DIRECTIVE == next_type) {
					// name : type, or name #escaping : type
					its_a_name = true;
				}
				else if (TokenType::SYM_COMMA == next_type) {
					// list, still ambiguous

					// Scan ahead a while until we can tell what it is
					for (size_t i = 1; i < 1024; ++i) {
						const TokenType future_type = next_token(state, i).type;
						if (TokenType::SYM_RPAREN == future_type
							|| TokenType::SYM_LBRACE == future_type
							|| TokenType::OPERATOR_EQUAL == future_type) {
							break;
						}
						if (TokenType::SYM_COLON == future_type) {
							its_a_name = true;
							break;
						}
					}
				}
				if (its_a_name) {
					// identifier, possibly a list of them
					ast::Node& name = next_as_node(state, ast::NodeType::IDENTIFIER);
					while (expect(state, TokenType::DIRECTIVE)) {
						next_as_node(state, ast::NodeType::DIRECTIVE, &name);
					}

					ast::Node* name_part = nullptr;
					ast::Node* list_part = nullptr;

					while (expect(state, TokenType::SYM_COMMA)) {
						if (list_part == nullptr) {
							list_part = &next_as_node(state, ast::NodeType::LIST);
							list_part->children.push_back(&name);
						}
						else {
							skip(state, TokenType::SYM_COMMA);
						}
						if (!accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER, *list_part)) {
							//TODO(ches) make sure we have a test for this
							report_error_on_last_token(state, ErrorCode::E3009);
							return false;
						}
						ast::Node* listed_name = list_part->children.back();
						while (expect(state, TokenType::DIRECTIVE)) {
							next_as_node(state, ast::NodeType::DIRECTIVE, listed_name);
						}
					}
					if (list_part == nullptr) {
						name_part = &name;
					}
					else {
						name_part = list_part;
					}

					if (!expect(state, TokenType::SYM_COLON)) {
						//TODO(ches) make sure we have a test for this
						report_error_on_last_token(state, ErrorCode::E3010);
						return false;
					}

					param = &next_as_node(state, ast::NodeType::COLON);
					param->children.push_back(name_part);

					// name := default, with the type deduced from the default
					const bool type_deduced = expect(state, TokenType::OPERATOR_ASSIGN);

					const Token lparen = current_token(state);
					const bool was_a_fn = !type_deduced
						&& skip(state, TokenType::SYM_LPAREN);
					if (!was_a_fn && expect(state, TokenType::KEYWORD_FN)) {
						//TODO(ches) add a test for this
						report_error_on_last_token(state, ErrorCode::E3008);
						return false;
					}
					if (!type_deduced
						&& !expect(state, TokenType::KEYWORD_MUT)
						&& !expect(state, TokenType::IDENTIFIER)
						&& !expect(state, TokenType::KEYWORD_FN)
						&& !is_insert(state)
						) {
						report_error_on_last_token(state, ErrorCode::E3016);
						return false;
					}
					if (!type_deduced) {
						ExprResult type_part = type(state);

						if (!type_part.success) {
							return false;
						}
						param->children.push_back(type_part.result);
					}
					if (was_a_fn) {
						if (!skip(state, TokenType::SYM_RPAREN)) {
							//TODO(ches) make sure we have a test for this
							report_error_on_last_token(state, ErrorCode::E3015,
								std::format("Opening parenthesis was at ({},{})",
									lparen.line_number,
									lparen.column_number));
							return false;
						}
						// (fn(n: int) -> int)?: the function is optional
						if (!type_deduced && !param->children.empty()) {
							accept(state, TokenType::SYM_QUESTION, ast::NodeType::UNARY_OPERATOR, *param->children.back());
						}
					}
				}
				else {
					const Token& lparen = current_token(state);
					if (its_complicated) {
						skip(state, TokenType::SYM_LPAREN);
					}

					ExprResult type_part = type(state);
					if (!type_part.success) {
						return false;
					}
					param = type_part.result;

					if (its_complicated) {
						if (!skip(state, TokenType::SYM_RPAREN)) {
							//TODO(ches) make sure we have a test for this
							report_error_on_last_token(state, ErrorCode::E3015,
								std::format("Opening parenthesis was at ({},{})",
									lparen.line_number,
									lparen.column_number));
							return false;
						}
						accept(state, TokenType::SYM_QUESTION, ast::NodeType::UNARY_OPERATOR, *param);
					}
				}

			}
			// param is now either the type node, or a colon

			if (expect(state, TokenType::SYM_ELLIPSIS)) {
				next_as_node(state, ast::NodeType::ELLIIPSIS, param);
			}

			ast::Node* node_to_add = nullptr;

			if (expect(state, TokenType::OPERATOR_ASSIGN)) {
				node_to_add = &next_as_node(state, ast::NodeType::BINARY_OPERATOR);
				node_to_add->children.push_back(param);

				if (!default_value(state, *node_to_add)) {
					delete_node(state->node_alloc, node_to_add);
					return false;
				}
			}
			else {
				node_to_add = param;
			}
			node.children.push_back(node_to_add);

			skip(state, TokenType::SYM_COMMA);

			token_type = current_token(state).type;
		}

		return true;
	}

	// Whether a type in parentheses comes next, like (mut u8[])? or mut (u8[]), and not a function type's (fn ...).
	static bool is_parenthesized_type(ParserState* state) {
		if (expect(state, TokenType::KEYWORD_MUT)) {
			return TokenType::SYM_LPAREN == next_token(state).type && TokenType::KEYWORD_FN != next_token(state, 2).type;
		}
		return expect(state, TokenType::SYM_LPAREN) && TokenType::KEYWORD_FN != next_token(state).type;
	}

	bool function_output_list(ParserState* state, ast::Node& parent) {
		if (is_insert(state)) {
			ExprResult inserted = insert_type(state, nullptr);
			if (!inserted.success) {
				return false;
			}
			parent.children.push_back(inserted.result);
			return true;
		}
		if (expect(state, TokenType::KEYWORD_VOID)) {
			accept(state, TokenType::KEYWORD_VOID, ast::NodeType::VOID, parent);
			return true;
		}
		// A type, like int, or a mut one, like mut u8[]
		if (expect(state, TokenType::IDENTIFIER) || expect(state, TokenType::KEYWORD_MUT)) {
			ExprResult id = simple_type(state);
			if (!id.success) {
				return false;
			}
			parent.children.push_back(id.result);
			return true;
		}
		if (expect(state, TokenType::SYM_LPAREN)) {
			const Token& lparen = current_token(state);
			ast::Node* single_fn = nullptr;
			if (TokenType::KEYWORD_FN == next_token(state).type) {
				skip(state, TokenType::SYM_LPAREN);
				ExprResult fn = function_signature(state);
				if (!fn.success) {
					return false;
				}
				parent.children.push_back(fn.result);
				single_fn = fn.result;
			}
			else {
				ast::Node& node = next_as_node(state, ast::NodeType::LIST, &parent);

				while (expect(state, TokenType::SYM_LPAREN)
					|| expect(state, TokenType::KEYWORD_MUT)
					|| expect(state, TokenType::IDENTIFIER)
					|| is_insert(state)
					) {

					// A type an #insert puts there, in a quote (docs/compilation.md, Code Values)
					if (is_insert(state)) {
						ExprResult inserted = insert_type(state, nullptr);
						if (!inserted.success) {
							return false;
						}
						node.children.push_back(inserted.result);
						skip(state, TokenType::SYM_COMMA);
						continue;
					}
					// A type in parentheses, like ((mut u8[])?), an optional view (docs/functions.md)
					if (is_parenthesized_type(state)) {
						ExprResult grouped = type(state);
						if (!grouped.success) {
							return false;
						}
						node.children.push_back(grouped.result);
						skip(state, TokenType::SYM_COMMA);
						continue;
					}
					const Token& next_lparen = current_token(state);
					if (skip(state, TokenType::SYM_LPAREN)) {
						ExprResult fn = function_signature(state);
						if (!fn.success) {
							return false;
						}
						node.children.push_back(fn.result);

						if (!skip(state, TokenType::SYM_RPAREN)) {
							report_error_on_last_token(state, ErrorCode::E3015,
								std::format("Opening parenthesis was at ({},{})",
									next_lparen.line_number,
									next_lparen.column_number));
							return false;
						}
						// (fn() -> int)?: the function is optional
						accept(state, TokenType::SYM_QUESTION, ast::NodeType::UNARY_OPERATOR, *fn.result);
						skip(state, TokenType::SYM_COMMA);
						continue;
					}
					if (expect(state, TokenType::KEYWORD_MUT) 
						|| expect(state, TokenType::IDENTIFIER)) {
						ExprResult type = simple_type(state);
						if (!type.success) {
							return false;
						}
						node.children.push_back(type.result);
						// A named result's directives, like text #unrestricted : string
						while (expect(state, TokenType::DIRECTIVE)) {
							next_as_node(state, ast::NodeType::DIRECTIVE, type.result);
						}
					}
					skip(state, TokenType::SYM_COMMA);
					if (accept(state, TokenType::SYM_COLON,
						ast::NodeType::COLON, node)) {
						// f: (fn() -> int), a named function result, optional with a ?
						const Token& named_lparen = current_token(state);
						if (expect(state, TokenType::SYM_LPAREN)
							&& TokenType::KEYWORD_FN == next_token(state).type) {
							skip(state, TokenType::SYM_LPAREN);
							ExprResult fn = function_signature(state);
							if (!fn.success) {
								return false;
							}
							node.children.push_back(fn.result);
							if (!skip(state, TokenType::SYM_RPAREN)) {
								report_error_on_last_token(state, ErrorCode::E3015,
									std::format("Opening parenthesis was at ({},{})",
										named_lparen.line_number,
										named_lparen.column_number));
								return false;
							}
							accept(state, TokenType::SYM_QUESTION, ast::NodeType::UNARY_OPERATOR, *fn.result);
							skip(state, TokenType::SYM_COMMA);
							continue;
						}
						if (is_insert(state)) {
							ExprResult inserted = insert_type(state, nullptr);
							if (!inserted.success) {
								return false;
							}
							node.children.push_back(inserted.result);
							skip(state, TokenType::SYM_COMMA);
							continue;
						}
						// view : (mut u8[])?, a named result of a type in parentheses
						if (is_parenthesized_type(state)) {
							ExprResult grouped = type(state);
							if (!grouped.success) {
								return false;
							}
							node.children.push_back(grouped.result);
							skip(state, TokenType::SYM_COMMA);
							continue;
						}
						if (!expect(state, TokenType::IDENTIFIER)
							&& !expect(state, TokenType::KEYWORD_MUT)) {
							report_error_on_last_token(state, ErrorCode::E3016);
							return false;
						}
						ExprResult named_type = simple_type(state);
						if (!named_type.success) {
							return false;
						}
						node.children.push_back(named_type.result);
						skip(state, TokenType::SYM_COMMA);
					}
				}
			}
			if (!skip(state, TokenType::SYM_RPAREN)) {
				report_error_on_last_token(state, ErrorCode::E3015,
					std::format("Opening parenthesis was at ({},{})",
						lparen.line_number,
						lparen.column_number));
				return false;
			}
			if (single_fn != nullptr) {
				// -> (fn() -> int)?: the function is optional
				accept(state, TokenType::SYM_QUESTION, ast::NodeType::UNARY_OPERATOR, *single_fn);
			}
			return true;
		}
		//TODO(ches) write a test for this
		report_error_on_last_token(state, ErrorCode::E3017);
		return false;
	}

	bool default_value(ParserState* state, ast::Node& parent) {
		if (expect(state, TokenType::DIRECTIVE)) {
			ast::Node& directive = next_as_node(state, 
				ast::NodeType::DIRECTIVE, &parent);
			if (directive.value.value->compare("#run") == 0) {
				ExprResult expr = expression_with_result(state, true);
				if (!expr.success) {
					return false;
				}
				directive.children.push_back(expr.result);
			}
			return true;
		}
		// Any expression, like allocator := context.allocator
		ExprResult expr = expression_with_result(state, true);
		if (!expr.success || expr.result == nullptr) {
			report_error_on_last_token(state, ErrorCode::E3006);
			return false;
		}
		parent.children.push_back(expr.result);
		return true;
	}

	// =, or an operator and =, like +=.
	static bool is_assign_operator(TokenType current) {
		return current == TokenType::OPERATOR_ASSIGN
			|| current == TokenType::OPERATOR_ASSIGN_ADD
			|| current == TokenType::OPERATOR_ASSIGN_AND
			|| current == TokenType::OPERATOR_ASSIGN_BITWISE_AND
			|| current == TokenType::OPERATOR_ASSIGN_BITWISE_OR
			|| current == TokenType::OPERATOR_ASSIGN_BITWISE_XOR
			|| current == TokenType::OPERATOR_ASSIGN_DIV
			|| current == TokenType::OPERATOR_ASSIGN_LEFT_SHIFT
			|| current == TokenType::OPERATOR_ASSIGN_MOD
			|| current == TokenType::OPERATOR_ASSIGN_MUL
			|| current == TokenType::OPERATOR_ASSIGN_OR
			|| current == TokenType::OPERATOR_ASSIGN_REMAINDER
			|| current == TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC
			|| current == TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL
			|| current == TokenType::OPERATOR_ASSIGN_SUB;
	}

	/*
	 * One statement in a block, or the body of a match arm: an expression, return, defer,
	 * break, continue, or a directive like #if.
	 */
	bool statement(ParserState* state, ast::Node& parent) {
		switch (current_token(state).type) {
		case TokenType::IDENTIFIER:
		case TokenType::KEYWORD_NULL:
		case TokenType::KEYWORD_CAST:
		case TokenType::KEYWORD_BIT_CAST:
		case TokenType::KEYWORD_AUTO_CAST:
		case TokenType::SYM_AMPERSAND:
		case TokenType::SYM_UNDERSCORE:
		case TokenType::SYM_DOT:
		case TokenType::SYM_LPAREN:
		case TokenType::KEYWORD_FALSE:
		case TokenType::KEYWORD_FOR:
		case TokenType::KEYWORD_IF:
		case TokenType::KEYWORD_LOOP:
		case TokenType::KEYWORD_MATCH:
		case TokenType::KEYWORD_PUSH_CONTEXT:
		case TokenType::KEYWORD_SWITCH:
		case TokenType::KEYWORD_TRUE:
		case TokenType::KEYWORD_WITH:
		case TokenType::LITERAL_CHAR:
		case TokenType::LITERAL_FLOATING_POINT:
		case TokenType::LITERAL_IMAGINARY:
		case TokenType::LITERAL_INTEGER:
		case TokenType::LITERAL_STRING:
		case TokenType::OPERATOR_BITWISE_XOR:
		case TokenType::OPERATOR_MINUS:
		case TokenType::OPERATOR_NOT:
		case TokenType::OPERATOR_PLUS:
		case TokenType::SYM_LBRACE:
		{
			if (!expression(state, parent)) {
				return false;
			}
			return true;
		}
		case TokenType::KEYWORD_RETURN:
		{
			ast::Node& ret = next_as_node(state, ast::NodeType::RETURN, &parent);
			if (expect(state, TokenType::KEYWORD_VOID)) {
				accept(state, TokenType::KEYWORD_VOID, ast::NodeType::VOID,
					ret);
			}
			else {
				ExprResult expr = expression_with_result(state, true);
				if (!expr.success) {
					return false;
				}
				ret.children.push_back(expr.result);
				while (skip(state, TokenType::SYM_COMMA)) {
					ExprResult another_expr = expression_with_result(state, true);
					if (!another_expr.success) {
						return false;
					}
					ret.children.push_back(another_expr.result);
				}
			}
			return true;
		}
		case TokenType::KEYWORD_DEFER:
		{
			ast::Node& defer = next_as_node(state, ast::NodeType::DEFER, &parent);
			if (!expression(state, defer)) {
				return false;
			}
			return true;
		}
		case TokenType::KEYWORD_BREAK:
		{
			ast::Node& break_node = next_as_node(state, ast::NodeType::BREAK, &parent);
			if (expect(state, TokenType::LITERAL_INTEGER)) {
				next_as_node(state, ast::NodeType::LITERAL, &break_node);
			}
			else if (is_word(state, "all")) {
				next_as_node(state, ast::NodeType::KEYWORD_ALL, &break_node);
			}
			return true;
		}
		case TokenType::KEYWORD_CONTINUE:
		{
			next_as_node(state, ast::NodeType::CONTINUE, &parent);
			return true;
		}
		case TokenType::DIRECTIVE:
		{
			ast::Node& directive = next_as_node(state, ast::NodeType::DIRECTIVE, &parent);
			
			bool is_an_if = false;

			if (directive.value.value->compare("#if") == 0
				|| directive.value.value->compare("#else_if") == 0) {
				is_an_if = true;

				ExprResult conditional = expression_with_result(state, true);
				if (!conditional.success) {
					return false;
				}
				directive.children.push_back(conditional.result);
			}

			if (is_an_if || directive.value.value->compare("#else") == 0) {
				if (!expect(state, TokenType::SYM_LBRACE)) {
					report_error_on_last_token(state, ErrorCode::E3018);
					return false;
				}
				ExprResult block_contents = block(state);
				if (!block_contents.success) {
					return false;
				}
				directive.children.push_back(block_contents.result);
			}

			// #run and #assert take an expression, what to run or the condition to check; #insert an operand, the code to put there
			if (directive.value.value->compare("#run") == 0
				|| directive.value.value->compare("#assert") == 0
				|| directive.value.value->compare("#insert") == 0) {
				ExprResult expr = directive.value.value->compare("#insert") == 0 ? insert_operand(state)
					: expression_with_result(state, true);
				if (!expr.success) {
					return false;
				}
				directive.children.push_back(expr.result);
				if (directive.value.value->compare("#insert") == 0 && expect(state, TokenType::SYM_COLON)) {
					parent.children.pop_back();
					return inserted_name_definition(state, parent, directive);
				}
				// An assignment to what's inserted, like #insert total += 1
				if (directive.value.value->compare("#insert") == 0 && is_assign_operator(current_token(state).type)) {
					parent.children.pop_back();
					ast::Node& assignment = next_as_node(state, ast::NodeType::BINARY_OPERATOR, &parent);
					assignment.children.push_back(&directive);
					ExprResult rhs = expression_with_result(state, true);
					if (!rhs.success) {
						return false;
					}
					assignment.children.push_back(rhs.result);
				}
			}
			return true;
		}
		case TokenType::ANNOTATION:
		case TokenType::COMMENT_BLOCK:
		case TokenType::COMMENT_LINE:
		case TokenType::INVALID:
		case TokenType::KEYWORD_CASE:
		case TokenType::KEYWORD_DISTINCT:
		case TokenType::KEYWORD_ELSE:
		case TokenType::KEYWORD_ENUM:
		case TokenType::KEYWORD_FN:
		case TokenType::KEYWORD_IS_NONE:
		case TokenType::KEYWORD_IS_SOME:
		case TokenType::KEYWORD_MUT:
		case TokenType::KEYWORD_OR_BREAK:
		case TokenType::KEYWORD_OR_CONTINUE:
		case TokenType::KEYWORD_OR_ELSE:
		case TokenType::KEYWORD_OR_RETURN:
		case TokenType::KEYWORD_STRUCT:
		case TokenType::KEYWORD_UNION:
		case TokenType::KEYWORD_USING:
		case TokenType::KEYWORD_VOID:
		case TokenType::OPERATOR_AND:
		case TokenType::OPERATOR_ASSIGN:
		case TokenType::OPERATOR_ASSIGN_ADD:
		case TokenType::OPERATOR_ASSIGN_AND:
		case TokenType::OPERATOR_ASSIGN_BITWISE_AND:
		case TokenType::OPERATOR_ASSIGN_BITWISE_OR:
		case TokenType::OPERATOR_ASSIGN_BITWISE_XOR:
		case TokenType::OPERATOR_ASSIGN_DIV:
		case TokenType::OPERATOR_ASSIGN_LEFT_SHIFT:
		case TokenType::OPERATOR_ASSIGN_MOD:
		case TokenType::OPERATOR_ASSIGN_MUL:
		case TokenType::OPERATOR_ASSIGN_OR:
		case TokenType::OPERATOR_ASSIGN_REMAINDER:
		case TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC:
		case TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL:
		case TokenType::OPERATOR_ASSIGN_SUB:
		case TokenType::OPERATOR_BITWISE_OR:
		case TokenType::OPERATOR_DIVIDE:
		case TokenType::OPERATOR_DEREFERENCE:
		case TokenType::OPERATOR_EQUAL:
		case TokenType::OPERATOR_GREATER_THAN_OR_EQUAL:
		case TokenType::OPERATOR_LEFT_SHIFT:
		case TokenType::OPERATOR_LESS_THAN_OR_EQUAL:
		case TokenType::OPERATOR_MODULUS:
		case TokenType::OPERATOR_MULTIPLY:
		case TokenType::OPERATOR_NOT_EQUAL:
		case TokenType::OPERATOR_OR:
		case TokenType::OPERATOR_PIPE:
		case TokenType::OPERATOR_RANGE_ARRAY:
		case TokenType::OPERATOR_RANGE_EXCLUSIVE:
		case TokenType::OPERATOR_RANGE_INCLUSIVE:
		case TokenType::OPERATOR_REMAINDER:
		case TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC:
		case TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL:
		case TokenType::PIPE_REORDER_IDENTIFIER:
		case TokenType::START_OF_FILE:
		case TokenType::SYM_ARROW_DOUBLE:
		case TokenType::SYM_ARROW_SINGLE:
		case TokenType::SYM_COLON:
		case TokenType::SYM_COMMA:
		case TokenType::SYM_ELLIPSIS:
		case TokenType::SYM_GT:
		case TokenType::SYM_LBRACK:
		case TokenType::SYM_LT:
		case TokenType::SYM_QUESTION:
		case TokenType::SYM_RBRACE:
		case TokenType::SYM_RBRACK:
		case TokenType::SYM_RPAREN:
		case TokenType::SYM_UNINITIALIZED:
			report_error_on_last_token(state, ErrorCode::E3017);
			return false;
		case TokenType::KEYWORD_WHILE:
		case TokenType::END_OF_FILE:
			report_error_on_last_token(state, ErrorCode::E3017);
			return false;
		}
		LOG_ERROR("We should have parsed a statement");
		return false;
	}

	ExprResult block(ParserState* state) {
		if (!expect(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return ExprResult{ false };
		}

		ast::Node& block_node = next_as_node(state, ast::NodeType::BLOCK);

		while (!expect(state, TokenType::SYM_RBRACE)) {
			if (expect(state, TokenType::END_OF_FILE)
				|| expect(state, TokenType::KEYWORD_WHILE)) {
				report_error_on_last_token(state, ErrorCode::E3019,
					std::format("Opening brace was at ({},{})",
						block_node.value.line_number,
						block_node.value.column_number));
				return ExprResult{ false };
			}
			if (!statement(state, block_node)) {
				return ExprResult{ false };
			}
		}

		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019,
				std::format("Opening brace was at ({},{})",
					block_node.value.line_number,
					block_node.value.column_number));
			return ExprResult{ false };
		}
		return ExprResult{ true, &block_node };
	}

	bool expression(ParserState* state, ast::Node& parent) {
		const TokenType current = current_token(state).type;

		if (is_declaration_start(state)) {
			return expression_without_result(state, parent);
		}
		if (TokenType::KEYWORD_FOR == current
			|| TokenType::KEYWORD_WITH == current
			|| TokenType::KEYWORD_LOOP == current
			|| TokenType::KEYWORD_PUSH_CONTEXT == current
			|| TokenType::KEYWORD_SWITCH == current) {
			return expression_without_result(state, parent);
		}
		if (!could_start_expression(current)) {
			report_error_on_last_token(state, ErrorCode::E3017);
			return false;
		}

		ExprResult result = expression_with_result(state, false);
		if (!result.success) {
			return false;
		}
		parent.children.push_back(result.result);
		return true;
	}
	
	ExprResult expression_with_result(ParserState* state, bool ignore_lists) {
		if (expect(state, TokenType::SYM_LBRACE)) {
			return block(state);
		}
		if (expect(state, TokenType::KEYWORD_MATCH)) {
			return match_expression(state);
		}
		// A typed literal is an operand like any other (expr_lvl_11), so Point.{1, 2} == p goes on past it
		return expr_lvl_1(state, ignore_lists);
	}

	bool expression_without_result(ParserState* state, ast::Node& parent) {
		const TokenType current = current_token(state).type;
		if (current == TokenType::KEYWORD_FOR) {
			return for_loop(state, parent);
		}
		if (current == TokenType::KEYWORD_WITH
			|| current == TokenType::KEYWORD_LOOP) {
			return loop(state, parent);
		}
		if (current == TokenType::KEYWORD_PUSH_CONTEXT) {
			return push_context(state, parent);
		}
		if (current == TokenType::KEYWORD_SWITCH) {
			return switch_statement(state, parent);
		}
		if (is_declaration_start(state)) {
			{
				ExprResult decl = declaration(state, parent);

				if (!decl.success) {
					return false;
				}

				if (expect(state, TokenType::SYM_COLON)) {
					return const_definition_rhs(state, *decl.result);
				}
				if (expect(state, TokenType::OPERATOR_ASSIGN)) {
					return mut_definition_rhs(state, *decl.result);
				}
				return true;
			}
		}
		return false;
	}

	bool literal(ParserState* state, ast::Node& parent) {
		const TokenType current = current_token(state).type;
		if (current == TokenType::LITERAL_CHAR
			|| current == TokenType::LITERAL_FLOATING_POINT
			|| current == TokenType::LITERAL_IMAGINARY
			|| current == TokenType::LITERAL_INTEGER
			|| current == TokenType::LITERAL_STRING
			|| current == TokenType::KEYWORD_TRUE
			|| current == TokenType::KEYWORD_FALSE
			|| current == TokenType::KEYWORD_NULL
			) {
			return accept(state, current, ast::NodeType::LITERAL, parent);
		}
		
		return false;
	}

	// A field's name: any word, as long as : or , follows (so using still starts a using).
	static bool is_field_name(ParserState* state) {
		const TokenType next = next_token(state).type;
		return is_name(current_token(state).type) && (TokenType::IDENTIFIER == current_token(state).type
			|| TokenType::SYM_COLON == next || TokenType::SYM_COMMA == next);
	}

	static bool field_after_names(ParserState* state, ast::Node& parent, ast::Node& names);

	bool struct_body(ParserState* state, ast::Node& parent) {
		while (is_field_name(state)
			|| expect(state, TokenType::KEYWORD_USING)
			|| expect(state, TokenType::SYM_UNDERSCORE)
			|| is_insert(state)) {

			// An #insert of fields, or of one field's name, like #insert name : int in a quote
			if (is_insert(state)) {
				ast::Node& directive = next_as_node(state, ast::NodeType::DIRECTIVE);
				ExprResult operand = insert_operand(state);
				if (!operand.success) {
					return false;
				}
				directive.children.push_back(operand.result);
				if (expect(state, TokenType::SYM_COLON)) {
					if (!field_after_names(state, parent, directive)) {
						return false;
					}
				}
				else {
					parent.children.push_back(&directive);
				}
				skip(state, TokenType::SYM_COMMA);
				continue;
			}
			// using value : ptr[T]: a named field whose members can be used as the struct's own
			const bool named_using = expect(state, TokenType::KEYWORD_USING) && TokenType::IDENTIFIER == next_token(state).type
				&& TokenType::SYM_COLON == next_token(state, 2).type;
			if (named_using) {
				ast::Node& marker = next_as_node(state, ast::NodeType::USING);
				const size_t before = parent.children.size();
				if (!struct_member(state, parent)) {
					return false;
				}
				// On the field's definition, after its names and type
				if (parent.children.size() > before) {
					parent.children.back()->children.push_back(&marker);
				}
			}
			else if (expect(state, TokenType::KEYWORD_USING) && !is_field_name(state)) {
				ast::Node& using_node = next_as_node(state, ast::NodeType::USING, &parent);
				if (!expect(state, TokenType::IDENTIFIER)) {
					report_error_on_last_token(state, ErrorCode::E3009);
					return false;
				}
				next_as_node(state, ast::NodeType::IDENTIFIER, &using_node);
				// Qualified by package, like using compiler.TypeInfo
				while (expect(state, TokenType::SYM_DOT)
					&& TokenType::IDENTIFIER == next_token(state).type) {
					accept(state, TokenType::SYM_DOT, ast::NodeType::DOT_ACCESS, using_node);
					accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER, using_node);
				}
			}
			else if (expect(state, TokenType::SYM_UNDERSCORE)) {
				ast::Node& underscore = next_as_node(state, ast::NodeType::UNDERSCORE);

				if (!expect(state, TokenType::SYM_COLON)) {
					report_error_on_last_token(state, ErrorCode::E3010);
					return false;
				}
				ast::Node& colon = next_as_node(state, ast::NodeType::DEFINITION, &parent);
				colon.children.push_back(&underscore);

				if (!expect(state, TokenType::KEYWORD_STRUCT)) {
					report_error_on_last_token(state, ErrorCode::E3023);
					return false;
				}
				if (!struct_decl(state, colon)) {
					return false;
				}
			}
			else if (!struct_member(state, parent)) {
				return false;
			}

			skip(state, TokenType::SYM_COMMA);
		}

		return true;
	}

	// name : type, or a, b, c : type, with an optional = default value
	bool struct_member(ParserState* state, ast::Node& parent) {
		ast::Node& name = next_as_node(state, ast::NodeType::IDENTIFIER);
		ast::Node* names = &name;

		while (expect(state, TokenType::SYM_COMMA)) {
			if (names == &name) {
				names = &next_as_node(state, ast::NodeType::LIST);
				names->children.push_back(&name);
			}
			else {
				skip(state, TokenType::SYM_COMMA);
			}
			if (!accept_name(state, *names)) {
				report_error_on_last_token(state, ErrorCode::E3009);
				delete_node(state->node_alloc, names);
				return false;
			}
		}
		return field_after_names(state, parent, *names);
	}

	// A field's : type, with an optional = default value, after its names.
	static bool field_after_names(ParserState* state, ast::Node& parent, ast::Node& names) {
		if (!expect(state, TokenType::SYM_COLON)) {
			report_error_on_last_token(state, ErrorCode::E3010);
			delete_node(state->node_alloc, &names);
			return false;
		}
		ast::Node& definition = next_as_node(state, ast::NodeType::DEFINITION, &parent);
		definition.children.push_back(&names);

		const Token lparen = current_token(state);
		const bool in_parens = skip(state, TokenType::SYM_LPAREN);
		ExprResult member_type = type(state);
		if (!member_type.success) {
			return false;
		}
		definition.children.push_back(member_type.result);
		if (in_parens && !skip(state, TokenType::SYM_RPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3015,
				std::format("Opening parenthesis was at ({},{})",
					lparen.line_number,
					lparen.column_number));
			return false;
		}
		// (fn(n: int) -> int)?: the function is optional
		if (in_parens) {
			accept(state, TokenType::SYM_QUESTION, ast::NodeType::UNARY_OPERATOR, *member_type.result);
		}

		if (expect(state, TokenType::OPERATOR_ASSIGN)) {
			return mut_definition_rhs(state, definition);
		}
		return true;
	}

	bool union_body(ParserState* state, ast::Node& parent) {
		while (true) {
			if (is_insert(state)) {
				if (!insert_item(state, parent)) {
					return false;
				}
				continue;
			}
			if (!accept_name(state, parent)) {
				break;
			}
			//NOTE(ches) this is all one entry in the union
			if (expect(state, TokenType::SYM_LPAREN)) {
				// The payload's types are children of the paren group, so the next variant isn't
				// mistaken for one of them
				ast::Node& payload = next_as_node(state, ast::NodeType::PAREN_GROUP, &parent);
				const Token& lparen = payload.value;
				// Each value's type, of any kind: ptr[mut T], runtime.Fiber, fn() -> int, ...
				while (expect(state, TokenType::IDENTIFIER) || expect(state, TokenType::KEYWORD_MUT)
					|| expect(state, TokenType::KEYWORD_FN)) {
					ExprResult value_type = type(state);
					if (!value_type.success) {
						return false;
					}
					payload.children.push_back(value_type.result);
					if (!skip(state, TokenType::SYM_COMMA)) {
						if (!expect(state, TokenType::SYM_RPAREN)) {
							/*
							 * NOTE(ches) if we have something besides comma,
							 * then it had better be the closing parenthesis
							 */
							report_error_on_last_token(state, ErrorCode::E3015,
								std::format("Opening parenthesis was at ({},{})",
									lparen.line_number,
									lparen.column_number));
							return false;
						}
					}
				}
				if (!skip(state, TokenType::SYM_RPAREN)) {
					report_error_on_last_token(state, ErrorCode::E3015,
						std::format("Opening parenthesis was at ({},{})",
							lparen.line_number,
							lparen.column_number));
					return false;
				}
			}
			
			skip(state, TokenType::SYM_COMMA);
		}
		return true;
	}

	bool enum_body(ParserState* state, ast::Node& parent) {
		while (is_name(current_token(state).type) || is_insert(state)) {
			/*
			 * An #insert of members, or of one member's name, like #insert name = 3 in a quote: its value
			 * goes after the operand, and goes to the name it inserts
			 */
			ast::Node* member_node = nullptr;
			if (is_insert(state)) {
				member_node = &next_as_node(state, ast::NodeType::DIRECTIVE, &parent);
				ExprResult operand = insert_operand(state);
				if (!operand.success) {
					return false;
				}
				member_node->children.push_back(operand.result);
			}
			else {
				member_node = &next_as_node(state, ast::NodeType::IDENTIFIER, &parent);
			}
			ast::Node& member = *member_node;

			// An explicit value, like TRACE = 0
			if (expect(state, TokenType::OPERATOR_ASSIGN)) {
				ast::Node& assign = next_as_node(state, ast::NodeType::BINARY_OPERATOR, &member);
				ExprResult value = expression_with_result(state, true);
				if (!value.success) {
					return false;
				}
				assign.children.push_back(value.result);
			}
			skip(state, TokenType::SYM_COMMA);
		}
		return true;
	}

	/*
	 * A list of generic parameters (on a declaration: T, or capacity: usize for a value),
	 * or of generic arguments (where a generic type is used: a type, or a constant value).
	 */
	/*
	 * Whether what follows a generic parameter's colon is a constraint expression that can't be a
	 * type: names combined with && or ||, or one in parentheses, like (Integer || Float) && Ordered.
	 */
	static bool constraint_ahead(ParserState* state) {
		if (TokenType::SYM_LPAREN == current_token(state).type) {
			return TokenType::KEYWORD_FN != next_token(state).type;
		}
		if (TokenType::IDENTIFIER != current_token(state).type) {
			return false;
		}
		size_t at = state->current + 1;
		while (at + 1 < state->tokens.size() && TokenType::SYM_DOT == state->tokens[at].type
			&& TokenType::IDENTIFIER == state->tokens[at + 1].type) {
			at += 2;
		}
		return at < state->tokens.size()
			&& (TokenType::OPERATOR_AND == state->tokens[at].type || TokenType::OPERATOR_OR == state->tokens[at].type);
	}

	/*
	 * A generic's where clause, after its signature or generic list: where and a constraint
	 * expression, like where Convertible(From, To) && AtLeastOne(capacity). where is only a word
	 * here, so it can still name things elsewhere.
	 */
	static bool where_clause(ParserState* state, ast::Node& parent) {
		if (!is_word(state, "where")) {
			return true;
		}
		ast::Node& clause = next_as_node(state, ast::NodeType::WHERE_CLAUSE, &parent);
		ExprResult condition = expression_with_result(state, true);
		if (!condition.success) {
			return false;
		}
		clause.children.push_back(condition.result);
		return true;
	}

	bool generic_tag(ParserState* state, ast::Node& parent, bool is_declaration) {
		ast::Node& node = next_as_node(state, ast::NodeType::GENERIC_TAG, &parent);

		while (!expect(state, TokenType::SYM_RBRACK)) {
			if (expect(state, TokenType::END_OF_FILE)) {
				break;
			}
			if (expect(state, TokenType::SYM_LBRACE)) {
				break;
			}
			const TokenType current = current_token(state).type;
			// A name followed by arithmetic, like CAPACITY * 2, is a value too; a name alone parses as a type
			bool name_into_arithmetic = false;
			if (TokenType::IDENTIFIER == current) {
				size_t at = state->current + 1;
				while (at + 1 < state->tokens.size() && TokenType::SYM_DOT == state->tokens[at].type
					&& TokenType::IDENTIFIER == state->tokens[at + 1].type) {
					at += 2;
				}
				name_into_arithmetic = at < state->tokens.size() && is_arithmetic(state->tokens[at].type);
			}
			// What a pointer points to is always a type, and so is one in parentheses with mut, like (mut u8[])
			const bool pointer_argument = parent.value.value != nullptr && (*parent.value.value == "ptr"
				|| std::string_view(*parent.value.value).starts_with("relptr"));
			const bool parenthesized_type = TokenType::SYM_LPAREN == current && (pointer_argument
				|| TokenType::KEYWORD_MUT == next_token(state).type);
			const bool is_value = !is_declaration && !parenthesized_type
				&& (TokenType::LITERAL_INTEGER == current
					|| TokenType::KEYWORD_TRUE == current
					|| TokenType::KEYWORD_FALSE == current
					|| TokenType::SYM_DOT == current
					|| TokenType::OPERATOR_MINUS == current
					|| TokenType::SYM_LPAREN == current
					|| is_run(current_token(state))
					|| name_into_arithmetic);
			if (is_value) {
				// A constant value, like Ring[u8, 4096]. Named constants parse as types.
				ExprResult value = expression_with_result(state, true);
				if (!value.success) {
					return false;
				}
				node.children.push_back(value.result);
			}
			else if (is_declaration
				&& TokenType::IDENTIFIER == current
				&& TokenType::OPERATOR_ASSIGN == next_token(state).type) {
				// A derived parameter, like E = element_of(C)
				ast::Node& derived = next_as_node(state, ast::NodeType::DERIVED_PARAMETER, &node);
				skip(state, TokenType::OPERATOR_ASSIGN);
				ExprResult expression = expression_with_result(state, true);
				if (!expression.success) {
					return false;
				}
				derived.children.push_back(expression.result);
			}
			else if (is_declaration
				&& TokenType::IDENTIFIER == current
				&& TokenType::SYM_COLON == next_token(state).type) {
				// A value parameter, like capacity: usize
				ast::Node& name = next_as_node(state, ast::NodeType::IDENTIFIER);
				ast::Node& colon = next_as_node(state, ast::NodeType::COLON, &node);
				colon.children.push_back(&name);
				/*
				 * Or a type parameter's constraints, like T: Equatable && Ordered: an expression when
				 * it combines them, and otherwise a name, which the checker tells apart from a type
				 */
				ExprResult value_type = constraint_ahead(state) ? expression_with_result(state, true) : type(state);
				if (!value_type.success) {
					return false;
				}
				colon.children.push_back(value_type.result);
			}
			else {
				ExprResult type_result = type(state);
				if (!type_result.success) {
					return false;
				}
				node.children.push_back(type_result.result);
			}

			if (expect(state, TokenType::SYM_COMMA)) {
				skip(state, TokenType::SYM_COMMA);
			}
		}
		if (!skip(state, TokenType::SYM_RBRACK)) {
			report_error_on_last_token(state, ErrorCode::E3012,
				std::format("Opening bracket was at ({},{})",
					node.value.line_number, node.value.column_number));
			return false;
		}
		return true;
	}

	ExprResult assign_target(ParserState* state, bool ignore_lists) {
		//TODO(ches) add tests for underscores as assignment targets
		if (expect(state, TokenType::SYM_UNDERSCORE)) {
			ast::Node* underscore = &next_as_node(state, ast::NodeType::UNDERSCORE);
			return ExprResult{ true, underscore };
		}
		return expr_lvl_2(state, ignore_lists);
	}

	ExprResult expr_lvl_1(ParserState* state, bool ignore_lists) {
		ExprResult lhs = assign_target(state, ignore_lists);

		if (!lhs.success) {
			return ExprResult{ false };
		}

		ast::Node* list = nullptr;

		while (!ignore_lists && expect(state, TokenType::SYM_COMMA)) {
			if (list == nullptr) {
				list = &next_as_node(state, ast::NodeType::LIST);
				list->children.push_back(lhs.result);
			}
			else {
				skip(state, TokenType::SYM_COMMA);
			}
			ExprResult next_expr = assign_target(state, ignore_lists);

			if (!next_expr.success) {
				delete_node(state->node_alloc, list);
				return ExprResult{ false };
			}
			list->children.push_back(next_expr.result);
		}

		if (list == nullptr) {
			list = lhs.result;
		}

		ast::Node* result = list;

		if (is_assign_operator(current_token(state).type)) {

			result = &next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result->children.push_back(list);

			// Any expression, like a typed literal: result.resume = FiberResumeState.{}
			ExprResult rhs = expression_with_result(state, ignore_lists);
			if (!rhs.success) {
				delete_node(state->node_alloc, result);
				return ExprResult{ false };
			}
			result->children.push_back(rhs.result);
		}

		return ExprResult{ true, result };
	}

	ExprResult expr_lvl_2(ParserState* state, bool ignore_lists) {
		if (expect(state, TokenType::KEYWORD_IF)) {
			return if_expression(state);
		}

		ExprResult lhs = expr_lvl_3(state);

		if (!lhs.success) {
			return ExprResult{ false };
		}

		const TokenType current = current_token(state).type;
		if (TokenType::KEYWORD_IS_NONE == current
			|| TokenType::KEYWORD_IS_SOME == current
			|| TokenType::KEYWORD_OR_BREAK == current
			|| TokenType::KEYWORD_OR_CONTINUE == current
			) {
			ast::Node& result = next_as_node(state, ast::NodeType::UNARY_OPERATOR);
			result.children.push_back(lhs.result);
			return ExprResult{ true, &result };
		}
		if (TokenType::KEYWORD_OR_ELSE == current) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			ExprResult rhs = expression_with_result(state, ignore_lists);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}
		if (TokenType::KEYWORD_OR_RETURN == current) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			// Like return, the value is required, void if the function has no results
			if (TokenType::KEYWORD_VOID == current_token(state).type) {
				next_as_node(state, ast::NodeType::VOID, &result);
			}
			else {
				ExprResult rhs = expression_with_result(state, ignore_lists);
				if (!rhs.success) {
					delete_node(state->node_alloc, &result);
					return ExprResult{ false };
				}
				result.children.push_back(rhs.result);
			}
			return ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_3(ParserState* state) {
		ExprResult lhs = expr_lvl_4(state);

		if (!lhs.success) {
			return { false };
		}

		const TokenType current = current_token(state).type;

		if (TokenType::OPERATOR_RANGE_EXCLUSIVE == current
			|| TokenType::OPERATOR_RANGE_INCLUSIVE == current
			) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);
			
			ExprResult rhs = expr_lvl_4(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_4(ParserState* state) {
		ExprResult lhs = expr_lvl_5(state);

		if (!lhs.success) {
			return { false };
		}

		if (expect(state, TokenType::OPERATOR_OR)) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			ExprResult rhs = expr_lvl_4(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_5(ParserState* state) {
		ExprResult lhs = expr_lvl_6(state);

		if (!lhs.success) {
			return { false };
		}

		if (expect(state, TokenType::OPERATOR_AND)) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			ExprResult rhs = expr_lvl_5(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_6(ParserState* state) {
		ExprResult lhs = expr_lvl_7(state);

		if (!lhs.success) {
			return { false };
		}

		const TokenType current = current_token(state).type;
		if (current == TokenType::OPERATOR_EQUAL
			|| current == TokenType::OPERATOR_NOT_EQUAL
			|| current == TokenType::SYM_LT
			|| current == TokenType::SYM_GT
			|| current == TokenType::OPERATOR_LESS_THAN_OR_EQUAL
			|| current == TokenType::OPERATOR_GREATER_THAN_OR_EQUAL
			) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			ExprResult rhs = expr_lvl_7(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_7(ParserState* state) {
		ExprResult lhs = expr_lvl_8(state);

		if (!lhs.success) {
			return { false };
		}

		// Left to right: a - b - c is (a - b) - c
		while (true) {
			const TokenType current = current_token(state).type;
			if (!(current == TokenType::OPERATOR_PLUS
				|| current == TokenType::OPERATOR_MINUS
				|| current == TokenType::OPERATOR_BITWISE_OR
				|| current == TokenType::OPERATOR_BITWISE_XOR
				)) {
				break;
			}
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			ExprResult rhs = expr_lvl_8(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			lhs = ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_8(ParserState* state) {
		ExprResult lhs = expr_lvl_9(state);

		if (!lhs.success) {
			return { false };
		}

		// Left to right: a - b - c is (a - b) - c
		while (true) {
			const TokenType current = current_token(state).type;
			if (!(current == TokenType::OPERATOR_MULTIPLY
				|| current == TokenType::OPERATOR_DIVIDE
				|| current == TokenType::OPERATOR_MODULUS
				|| current == TokenType::OPERATOR_REMAINDER
				|| current == TokenType::SYM_AMPERSAND
				|| current == TokenType::OPERATOR_LEFT_SHIFT
				|| current == TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC
				|| current == TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL
				)) {
				break;
			}
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			ExprResult rhs = expr_lvl_9(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			lhs = ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_9(ParserState* state) {
		if (expect(state, TokenType::SYM_LPAREN)) {
			ast::Node& result = next_as_node(state, ast::NodeType::PAREN_GROUP);
			
			ExprResult child = expression_with_result(state, true);

			if (!child.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(child.result);

			if (!skip(state, TokenType::SYM_RPAREN)) {
				report_error_on_last_token(state, ErrorCode::E3015,
					std::format("Opening parenthesis was at ({},{})",
						result.value.line_number,
						result.value.column_number));
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			/*
			 * A member, an element or what it points to, like (x or_else y).limit: a cast to nothing, keeping its
			 * value, so the chain after it is handled as after any cast. A call after it isn't, as a line in
			 * parentheses can follow one that ends in them.
			 */
			const bool member = expect(state, TokenType::SYM_DOT) && TokenType::IDENTIFIER == next_token(state).type;
			if (member || expect(state, TokenType::SYM_LBRACK) || expect(state, TokenType::OPERATOR_DEREFERENCE)) {
				result.node_type = ast::NodeType::CAST;
				if (!postfix_operations(state, result)) {
					return ExprResult{ false };
				}
			}
			return ExprResult{ true, &result };
		}
		else {
			return expr_lvl_10(state);
		}
	}

	ExprResult expr_lvl_10(ParserState* state) {
		ast::Node* result = nullptr;

		const TokenType current = current_token(state).type;
		if (current == TokenType::OPERATOR_PLUS
			|| current == TokenType::OPERATOR_MINUS
			|| current == TokenType::OPERATOR_BITWISE_XOR
			|| current == TokenType::OPERATOR_NOT) {
			result = &next_as_node(state, ast::NodeType::UNARY_OPERATOR);
		}

		// A unary operator's operand can be in parentheses, like !(a == b), or another unary, like -~x
		ExprResult expr = result != nullptr ? expr_lvl_9(state) : expr_lvl_11(state);
		
		if (!expr.success) {
			if (result != nullptr) {
				delete_node(state->node_alloc, result);
				result = nullptr;
			}
			return ExprResult{ false };
		}

		if (result == nullptr) {
			result = expr.result;
		}
		else {
			result->children.push_back(expr.result);
		}

		if (expect(state, TokenType::SYM_QUESTION)) {
			ast::Node* unwrap = &next_as_node(state, ast::NodeType::UNARY_OPERATOR);
			unwrap->children.push_back(result);
			result = unwrap;
		}

		return ExprResult{ true, result };
	}

	ExprResult expr_lvl_11(ParserState* state) {
		const TokenType current = current_token(state).type;


		if (current == TokenType::KEYWORD_CAST
			|| current == TokenType::KEYWORD_BIT_CAST
			|| current == TokenType::KEYWORD_AUTO_CAST) {
			return cast_expression(state);
		}
		// .{...}: a struct literal of the type expected there
		if (current == TokenType::SYM_DOT && TokenType::SYM_LBRACE == next_token(state).type) {
			return struct_literal(state);
		}
		if (current == TokenType::SYM_DOT) {
			return enum_shorthand(state);
		}
		// A typed literal as an operand, like the right of a < Words.{2, 2, 2, 2}
		if (is_typed_literal(state, TokenType::SYM_LBRACE)) {
			return struct_literal(state);
		}
		if (is_typed_literal(state, TokenType::SYM_LBRACK)) {
			return array_literal(state);
		}
		// #file_data("path") and #library("name") take their argument in parentheses, like a declaration's directives
		if (current == TokenType::DIRECTIVE && (current_token(state).value->compare("#file_data") == 0
			|| current_token(state).value->compare("#library") == 0)) {
			return directive_with_arguments(state, nullptr);
		}
		if (current == TokenType::DIRECTIVE) {
			ast::Node& result = next_as_node(state, ast::NodeType::DIRECTIVE);
			if (result.value.value->compare("#code") == 0) {
				return code_quote(state, result);
			}
			// #run takes an expression and #insert an operand, others like #caller_location stand alone
			if (result.value.value->compare("#run") == 0 || result.value.value->compare("#insert") == 0) {
				ExprResult expr = result.value.value->compare("#insert") == 0 ? insert_operand(state)
					: expression_with_result(state, true);
				if (!expr.success) {
					delete_node(state->node_alloc, &result);
					return ExprResult{ false };
				}
				result.children.push_back(expr.result);
			}
			return ExprResult{ true , &result };
		}
		
		if (current == TokenType::LITERAL_CHAR
			|| current == TokenType::LITERAL_FLOATING_POINT
			|| current == TokenType::LITERAL_IMAGINARY
			|| current == TokenType::LITERAL_INTEGER
			|| current == TokenType::LITERAL_STRING
			|| current == TokenType::KEYWORD_TRUE
			|| current == TokenType::KEYWORD_FALSE
			|| current == TokenType::KEYWORD_NULL)
		{
			const bool is_multiline = is_multiline_string_line(current_token(state));
			ast::Node& result = next_as_node(state, ast::NodeType::LITERAL);
			// Each line of a multiline string is its own token, the rest become children
			while (is_multiline && is_multiline_string_line(current_token(state))) {
				next_as_node(state, ast::NodeType::LITERAL, &result);
			}
			// A string's member or byte, like "abc".count or "abc"[1]: as after parentheses, a cast to nothing
			const bool member = expect(state, TokenType::SYM_DOT) && TokenType::IDENTIFIER == next_token(state).type;
			if (current == TokenType::LITERAL_STRING && (member || expect(state, TokenType::SYM_LBRACK))) {
				Token around = result.value;
				around.type = TokenType::SYM_LPAREN;
				ast::Node* group = state->node_alloc.new_object<ast::Node>(ast::NodeType::CAST, around);
				group->children.push_back(&result);
				if (!postfix_operations(state, *group)) {
					return ExprResult{ false };
				}
				return ExprResult{ true, group };
			}
			return ExprResult{ true , &result };
		}
		if (current == TokenType::IDENTIFIER || current == TokenType::SYM_AMPERSAND) {

			ExprResult loc = location(state);

			if (!loc.success) {
				return ExprResult{ false };
			}

			ast::Node* current_parent = loc.result;
			while (expect(state, TokenType::OPERATOR_PIPE)) {
				ast::Node& chain = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
				chain.children.push_back(current_parent);

				if (!function_call(state, chain)) {
					delete_node(state->node_alloc, &chain);
					return ExprResult{ false };
				}

				current_parent = &chain;
			}

			return ExprResult{ true , current_parent };
		}

		report_error_on_last_token(state, ErrorCode::E3017);
		return ExprResult{ false };
	}

	/*
	 * What #insert puts in place: an operand, which binds like a prefix operator's, so
	 * #insert a * #insert b multiplies two insertions. Anything more goes in parentheses or a call.
	 */
	ExprResult insert_operand(ParserState* state) {
		return expr_lvl_10(state);
	}

	// Whether an #insert starts here.
	static bool is_insert(ParserState* state) {
		return expect(state, TokenType::DIRECTIVE) && current_token(state).value != nullptr
			&& current_token(state).value->compare("#insert") == 0;
	}

	/*
	 * An #insert among fields, variants, members, patterns or cases (docs/compilation.md, Code Values):
	 * the directive with its operand, as one of parent's items, followed by a comma if there is one.
	 */
	bool insert_item(ParserState* state, ast::Node& parent) {
		ast::Node& directive = next_as_node(state, ast::NodeType::DIRECTIVE, &parent);
		ExprResult operand = insert_operand(state);
		if (!operand.success) {
			return false;
		}
		directive.children.push_back(operand.result);
		skip(state, TokenType::SYM_COMMA);
		return true;
	}

	/*
	 * A definition whose name an #insert puts there, like #insert name :: fn() {...} in a quote: the
	 * #insert, already parsed, is its names.
	 */
	bool inserted_name_definition(ParserState* state, ast::Node& parent, ast::Node& insert) {
		ExprResult definition = definition_after_names(state, parent, insert);
		if (!definition.success) {
			return false;
		}
		if (expect(state, TokenType::SYM_COLON)) {
			return const_definition_rhs(state, *definition.result);
		}
		if (expect(state, TokenType::OPERATOR_ASSIGN)) {
			return mut_definition_rhs(state, *definition.result);
		}
		return true;
	}

	// An #insert where a type goes, given with mut if it was: a MUTABLE after its operand.
	static ExprResult insert_type(ParserState* state, ast::Node* mut) {
		ast::Node& directive = next_as_node(state, ast::NodeType::DIRECTIVE);
		ExprResult operand = insert_operand(state);
		if (!operand.success) {
			return ExprResult{ false };
		}
		directive.children.push_back(operand.result);
		if (mut != nullptr) {
			directive.children.push_back(mut);
		}
		return ExprResult{ true, &directive };
	}

	/*
	 * The #insert directives in a quote's tree, in order, not counting those inside a #code within it,
	 * which belong to that quote.
	 */
	static void find_splices(ast::Node* node, std::vector<ast::Node*>& found) {
		for (ast::Node* child : node->children) {
			if (ast::NodeType::DIRECTIVE == child->node_type && child->value.value != nullptr) {
				if (child->value.value->compare("#insert") == 0) {
					found.push_back(child);
					// What follows its operand, like a member's value, can have its own
					for (size_t index = 1; index < child->children.size(); ++index) {
						find_splices(child->children[index], found);
					}
					continue;
				}
				if (child->value.value->compare("#code") == 0) {
					continue;
				}
			}
			find_splices(child, found);
		}
	}

	/*
	 * #code(expression) or #code { statements } (docs/compilation.md, Code Values): the tree goes in the
	 * quote table (ast::QuoteTable), and what each #insert in it splices becomes the #code node's
	 * children, in order, so passes over the body see only those.
	 */
	ExprResult code_quote(ParserState* state, ast::Node& quote) {
		ast::Node* tree = nullptr;
		/*
		 * What goes inside something else, named by a word: fields of a struct, variants of a union, members
		 * of an enum, patterns of a match and cases of a switch, each parsed as it is there
		 */
		const Token word = current_token(state);
		const bool named = TokenType::IDENTIFIER == word.type && TokenType::SYM_LBRACE == next_token(state).type
			&& word.value != nullptr && (*word.value == "fields" || *word.value == "variants" || *word.value == "members"
				|| *word.value == "patterns" || *word.value == "cases");
		if (named) {
			const std::string_view kind(*word.value);
			const ast::NodeType node_type = kind == "fields" ? ast::NodeType::STRUCT : kind == "variants" ? ast::NodeType::UNION
				: kind == "members" ? ast::NodeType::ENUM : ast::NodeType::LIST;
			tree = &next_as_node(state, node_type);
			const Token lbrace = current_token(state);
			skip(state, TokenType::SYM_LBRACE);
			const bool parsed = kind == "fields" ? struct_body(state, *tree) : kind == "variants" ? union_body(state, *tree)
				: kind == "members" ? enum_body(state, *tree) : kind == "patterns" ? match_arms(state, *tree)
				: switch_cases(state, *tree);
			if (!parsed || !skip(state, TokenType::SYM_RBRACE)) {
				if (parsed) {
					report_error_on_last_token(state, ErrorCode::E3019,
						std::format("Opening brace was at ({},{})", lbrace.line_number, lbrace.column_number));
				}
				delete_node(state->node_alloc, tree);
				delete_node(state->node_alloc, &quote);
				return ExprResult{ false };
			}
		}
		else if (expect(state, TokenType::SYM_LPAREN)) {
			const Token lparen = current_token(state);
			skip(state, TokenType::SYM_LPAREN);
			ExprResult inner = expression_with_result(state, true);
			if (!inner.success) {
				delete_node(state->node_alloc, &quote);
				return ExprResult{ false };
			}
			if (!skip(state, TokenType::SYM_RPAREN)) {
				report_error_on_last_token(state, ErrorCode::E3015,
					std::format("Opening parenthesis was at ({},{})", lparen.line_number, lparen.column_number));
				delete_node(state->node_alloc, &quote);
				return ExprResult{ false };
			}
			tree = inner.result;
		}
		else if (expect(state, TokenType::SYM_LBRACE)) {
			ExprResult inner = block(state);
			if (!inner.success) {
				delete_node(state->node_alloc, &quote);
				return ExprResult{ false };
			}
			tree = inner.result;
		}
		else {
			report_error_on_last_token(state, ErrorCode::E3017, "#code quotes ( an expression ) or { statements }");
			delete_node(state->node_alloc, &quote);
			return ExprResult{ false };
		}
		std::vector<ast::Node*> splices;
		// The quote can be an #insert alone, like #code(#insert x)
		if (ast::NodeType::DIRECTIVE == tree->node_type && tree->value.value != nullptr && tree->value.value->compare("#insert") == 0) {
			splices.push_back(tree);
		}
		else {
			find_splices(tree, splices);
		}
		// Each operand goes to the #code node; what follows it, like a type's mut, stays
		for (ast::Node* splice : splices) {
			if (!splice->children.empty()) {
				quote.children.push_back(splice->children.front());
				splice->children.erase(splice->children.begin());
			}
		}
		if (state->quotes != nullptr) {
			state->quotes->set(&quote, tree, state->file_path);
		}
		return ExprResult{ true, &quote };
	}

	/*
	 * What goes between the brackets when indexing: an expression, a range with an
	 * open start (..<5, ..=5) or end (5..), or for a type used as a value, .. for a
	 * dynamic array or a type argument that isn't an expression, like mut int.
	 */
	ExprResult slice_index(ParserState* state) {
		// ptr[mut int] or Callbacks[fn(int)] used as a value
		if (expect(state, TokenType::KEYWORD_MUT)
			|| expect(state, TokenType::KEYWORD_FN)) {
			return type(state);
		}
		// [..] in a type used as a value, like ptr[u8][..]
		if (expect(state, TokenType::OPERATOR_RANGE_ARRAY)
			&& TokenType::SYM_RBRACK == next_token(state).type) {
			ast::Node& dynamic = next_as_node(state, ast::NodeType::RANGE_ARRAY);
			return ExprResult{ true, &dynamic };
		}
		/*
		 * An open range is a range like start..<end with a RANGE_ARRAY in place of the missing
		 * bound, which the checker and generator read as the start or the count.
		 */
		if (expect(state, TokenType::OPERATOR_RANGE_EXCLUSIVE)
			|| expect(state, TokenType::OPERATOR_RANGE_INCLUSIVE)) {
			Token open_start = current_token(state);
			ast::Node& range = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			ExprResult end = expression_with_result(state, true);
			if (!end.success) {
				delete_node(state->node_alloc, &range);
				return ExprResult{ false };
			}
			open_start.type = TokenType::OPERATOR_RANGE_ARRAY;
			range.children.push_back(state->node_alloc.new_object<ast::Node>(ast::NodeType::RANGE_ARRAY, open_start));
			range.children.push_back(end.result);
			return ExprResult{ true, &range };
		}

		ExprResult index = expression_with_result(state, true);
		if (!index.success) {
			return ExprResult{ false };
		}
		if (expect(state, TokenType::OPERATOR_RANGE_ARRAY)) {
			// start.. is start..<count
			Token open_end = current_token(state);
			state->current += 1;
			Token exclusive = open_end;
			exclusive.type = TokenType::OPERATOR_RANGE_EXCLUSIVE;
			ast::Node* range = state->node_alloc.new_object<ast::Node>(ast::NodeType::BINARY_OPERATOR, exclusive);
			range->children.push_back(index.result);
			range->children.push_back(state->node_alloc.new_object<ast::Node>(ast::NodeType::RANGE_ARRAY, open_end));
			return ExprResult{ true, range };
		}
		return index;
	}

	/*
	 * Indexing, member access, calls and dereferencing after a value, like a[1].b(2)^,
	 * added to target as children in order.
	 */
	bool postfix_operations(ParserState* state, ast::Node& target) {
		while (expect(state, TokenType::SYM_LBRACK)
			|| expect(state, TokenType::SYM_DOT)
			|| expect(state, TokenType::SYM_LPAREN)
			|| expect(state, TokenType::OPERATOR_DEREFERENCE)
			|| (expect(state, TokenType::OPERATOR_NOT) && TokenType::SYM_LPAREN == next_token(state).type)) {

			// name!(arguments): a macro call, a ! before the arguments (docs/compilation.md, Macros)
			if (expect(state, TokenType::OPERATOR_NOT)) {
				accept(state, TokenType::OPERATOR_NOT, ast::NodeType::UNARY_OPERATOR, target);
				continue;
			}

			if (accept(state, TokenType::OPERATOR_DEREFERENCE,
				ast::NodeType::UNARY_OPERATOR, target)) {
				continue;
			}

			if (expect(state, TokenType::SYM_LBRACK)) {
				ast::Node& lbrack = next_as_node(state, 
					ast::NodeType::ARRAY_DIMENSION, &target);
			
				if (!expect(state, TokenType::SYM_RBRACK)) {
					ExprResult index = slice_index(state);
					if (!index.success) {
						return false;
					}
					target.children.push_back(index.result);

					// Several type arguments, like Result[int, string] used as a value
					while (skip(state, TokenType::SYM_COMMA)) {
						ExprResult argument = slice_index(state);
						if (!argument.success) {
							return false;
						}
						target.children.push_back(argument.result);
					}
				}
				if (!skip(state, TokenType::SYM_RBRACK)) {
					report_error_on_last_token(state, ErrorCode::E3012,
						std::format("Opening bracket was at ({},{})",
							lbrack.value.line_number, 
							lbrack.value.column_number));
					return false;
				}
				continue;
			}
			if (accept(state, TokenType::SYM_DOT, ast::NodeType::DOT_ACCESS,
				target)) {
				// A member named by an #insert, like value.#insert name in a quote
				if (is_insert(state)) {
					ast::Node& directive = next_as_node(state, ast::NodeType::DIRECTIVE, &target);
					ExprResult operand = insert_operand(state);
					if (!operand.success) {
						return false;
					}
					directive.children.push_back(operand.result);
					continue;
				}
				if (!accept_name(state, target)) {
					report_error_on_last_token(state, ErrorCode::E3009);
					return false;
				}
				continue;
			}
			if (expect(state, TokenType::SYM_LPAREN)) {

				const Token lparen = current_token(state);
				accept(state, TokenType::SYM_LPAREN,
					ast::NodeType::PAREN_GROUP, target);

				const TokenType next_token = current_token(state).type;

				if (could_be_function_input(next_token)) {
					if (!function_call_input_list(state, target)) {
						return false;
					}
				}

				if (!skip(state, TokenType::SYM_RPAREN)) {
					report_error_on_last_token(state, ErrorCode::E3015,
						std::format("Opening parenthesis was at ({},{})",
							lparen.line_number,
							lparen.column_number));
					return false;
				}
			}
		}
		return true;
	}

	ExprResult location(ParserState* state) {
		// We are relying on nullptr being ignored in next_as_node
		ast::Node* root = nullptr;
		ast::Node* latest = nullptr;

		while (expect(state, TokenType::SYM_AMPERSAND)) {
			latest = &next_as_node(state, ast::NodeType::UNARY_OPERATOR, latest);

			if (root == nullptr) {
				root = latest;
			}
		}

		// The address of a cast's result, or of what follows it, like &cast[ptr[Foo]](data).bar
		const TokenType current = current_token(state).type;
		if (latest != nullptr && (TokenType::KEYWORD_CAST == current || TokenType::KEYWORD_BIT_CAST == current
			|| TokenType::KEYWORD_AUTO_CAST == current)) {
			ExprResult operand = cast_expression(state);
			if (!operand.success) {
				delete_node(state->node_alloc, root);
				return ExprResult{ false };
			}
			latest->children.push_back(operand.result);
			return ExprResult{ true, root };
		}

		ast::Node& identifier = next_as_node(state, ast::NodeType::IDENTIFIER, latest);
		if (root == nullptr) {
			root = &identifier;
		}

		if (!postfix_operations(state, identifier)) {
			delete_node(state->node_alloc, &identifier);
			return ExprResult{ false };
		}
		return ExprResult{ true, root };
	}

	/*
	 * Whether a struct literal (open is a brace) or array literal (a bracket) starts here:
	 * a type name, possibly qualified by package and with generic arguments, then a dot and open.
	 * Like runtime.Context.{...} or Pair[int, string].{...}.
	 */
	bool is_typed_literal(ParserState* state, TokenType open) {
		if (!expect(state, TokenType::IDENTIFIER)) {
			return false;
		}
		size_t i = 1;
		while (TokenType::SYM_DOT == next_token(state, i).type
			&& TokenType::IDENTIFIER == next_token(state, i + 1).type) {
			i += 2;
		}
		if (TokenType::SYM_LBRACK == next_token(state, i).type) {
			size_t depth = 0;
			do {
				const TokenType type = next_token(state, i).type;
				if (TokenType::END_OF_FILE == type) {
					return false;
				}
				if (TokenType::SYM_LBRACK == type) {
					++depth;
				}
				else if (TokenType::SYM_RBRACK == type) {
					--depth;
				}
				++i;
			} while (depth > 0);
		}
		return TokenType::SYM_DOT == next_token(state, i).type
			&& open == next_token(state, i + 1).type;
	}

	// The type of a struct or array literal, after its first name: package qualifiers and generic arguments.
	bool literal_type(ParserState* state, ast::Node& literal) {
		while (expect(state, TokenType::SYM_DOT)
			&& TokenType::IDENTIFIER == next_token(state).type) {
			accept(state, TokenType::SYM_DOT, ast::NodeType::DOT_ACCESS, literal);
			accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER, literal);
		}
		if (expect(state, TokenType::SYM_LBRACK)) {
			return generic_tag(state, literal, false);
		}
		return true;
	}

	ExprResult struct_literal(ParserState* state) {
		//NOTE(ches) assumes we already checked with is_typed_literal
		ast::Node& id = next_as_node(state, ast::NodeType::STRUCT_LITERAL);
		if (!literal_type(state, id)) {
			delete_node(state->node_alloc, &id);
			return ExprResult{ false };
		}
		skip(state, TokenType::SYM_DOT);
		ast::Node& braces = next_as_node(state, ast::NodeType::LIST, &id);

		if (skip(state, TokenType::SYM_RBRACE)) {
			return ExprResult{ true, &id };
		}
		
		if (TokenType::IDENTIFIER == current_token(state).type
			&& TokenType::OPERATOR_ASSIGN == next_token(state).type) {
			//NOTE(ches) named inputs
			while (is_name(current_token(state).type)) {
				ast::Node& target = next_as_node(state, ast::NodeType::IDENTIFIER);

				if (!expect(state, TokenType::OPERATOR_ASSIGN)) {
					report_error_on_last_token(state, ErrorCode::E3024);
					delete_node(state->node_alloc, &id);
					return ExprResult{ false };
				}
				ast::Node& assign = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
				assign.children.push_back(&target);

				ExprResult value = expression_with_result(state, true);
				if (!value.result) {
					delete_node(state->node_alloc, &id);
					return ExprResult{ false };
				}
				assign.children.push_back(value.result);
				braces.children.push_back(&assign);
				if (!skip(state, TokenType::SYM_COMMA) 
					&& !expect(state, TokenType::SYM_RBRACE)) {
					report_error_on_last_token(state, ErrorCode::E3022);
					delete_node(state->node_alloc, &id);
					return ExprResult{ false };
				}
			}
		}
		else {
			//NOTE(ches) positional inputs
			while (!expect(state, TokenType::SYM_RBRACE)) {
				if (expect(state, TokenType::END_OF_FILE)) {
					break;
				}
				ExprResult value = expression_with_result(state, true);
				if (!value.result) {
					delete_node(state->node_alloc, &id);
					return ExprResult{ false };
				}
				braces.children.push_back(value.result);
				if (!skip(state, TokenType::SYM_COMMA)
					&& !expect(state, TokenType::SYM_RBRACE)) {
					report_error_on_last_token(state, ErrorCode::E3022);
					delete_node(state->node_alloc, &id);
					return ExprResult{ false };
				}
			}
		}

		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019,
				std::format("Opening brace was at ({},{})",
					braces.value.line_number,
					braces.value.column_number));
			delete_node(state->node_alloc, &id);
			return ExprResult{ false };
		}

		return ExprResult{ true, &id };
	}

	ExprResult array_literal(ParserState* state) {
		//NOTE(ches) assumes we already checked with is_typed_literal
		ast::Node& element_type = next_as_node(state, ast::NodeType::ARRAY_LITERAL);
		if (!literal_type(state, element_type)) {
			delete_node(state->node_alloc, &element_type);
			return ExprResult{ false };
		}
		skip(state, TokenType::SYM_DOT);
		ast::Node& brackets = next_as_node(state, ast::NodeType::LIST, &element_type);

		while (!expect(state, TokenType::SYM_RBRACK)) {
			if (expect(state, TokenType::END_OF_FILE)) {
				break;
			}
			ExprResult value = expression_with_result(state, true);
			if (!value.result) {
				delete_node(state->node_alloc, &element_type);
				return ExprResult{ false };
			}
			brackets.children.push_back(value.result);
			if (!skip(state, TokenType::SYM_COMMA)
				&& !expect(state, TokenType::SYM_RBRACK)) {
				report_error_on_last_token(state, ErrorCode::E3022);
				delete_node(state->node_alloc, &element_type);
				return ExprResult{ false };
			}
		}

		if (!skip(state, TokenType::SYM_RBRACK)) {
			report_error_on_last_token(state, ErrorCode::E3012,
				std::format("Opening bracket was at ({},{})",
					brackets.value.line_number,
					brackets.value.column_number));
			delete_node(state->node_alloc, &element_type);
			return ExprResult{ false };
		}

		return ExprResult{ true, &element_type };
	}

	bool function_call(ParserState* state, ast::Node& parent) {
		if (!expect(state, TokenType::IDENTIFIER)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			return false;
		}
		
		next_as_node(state, ast::NodeType::IDENTIFIER, &parent);

		if (!expect(state, TokenType::SYM_LPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3014);
			return false;
		}

		ast::Node& parens = next_as_node(state, ast::NodeType::PAREN_GROUP, &parent);

		if (could_be_function_input(current_token(state).type)) {
			if (!function_call_input_list(state, parens)) {
				return false;
			}
		}
		else if (!expect(state, TokenType::SYM_RPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3017);
			return false;
		}

		if (!skip(state, TokenType::SYM_RPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3015,
				std::format("Opening parenthesis was at ({},{})",
					parens.value.line_number,
					parens.value.column_number));
			return false;
		}

		return true;
	}

	bool function_call_input_list(ParserState* state, ast::Node& parent) {
		while (!expect(state, TokenType::SYM_RPAREN)) {
			const TokenType current_token_type = current_token(state).type;

			ast::Node* to_add_to = &parent;

			if (is_name(current_token_type)
				&& TokenType::OPERATOR_ASSIGN == next_token(state).type
				) {
				ast::Node& lhs = next_as_node(state, ast::NodeType::IDENTIFIER);
				ast::Node& assign = next_as_node(state, 
					ast::NodeType::BINARY_OPERATOR, &parent);
				assign.children.push_back(&lhs);
				to_add_to = &assign;
			}

			if (current_token_type == TokenType::SYM_UNDERSCORE) {
				accept(state, current_token_type, ast::NodeType::UNDERSCORE, 
					*to_add_to);
			}
			// mut Config: a type given with mut, like compiler.Mutable(mut Config) (docs/types.md, Mutability in Type Arguments)
			else if (current_token_type == TokenType::KEYWORD_MUT) {
				ExprResult given = simple_type(state);
				if (!given.success) {
					return false;
				}
				to_add_to->children.push_back(given.result);
			}
			else if (current_token_type == TokenType::PIPE_REORDER_IDENTIFIER) {
				accept(state, current_token_type, ast::NodeType::PIPE_REORDER_IDENTIFIER,
					*to_add_to);
			}
			else {
				ExprResult expr = expression_with_result(state, true);

				if (!expr.success) {
					delete_node(state->node_alloc, expr.result);
					return false;
				}
				to_add_to->children.push_back(expr.result);
			}
			
			if (!skip(state, TokenType::SYM_COMMA)) {
				if (!expect(state, TokenType::SYM_RPAREN)) {
					report_error_on_last_token(state, ErrorCode::E3022);
					return false;
				}
				else {
					break;
				}
			}
		}

		return true;
	}
	
	ExprResult cast_expression(ParserState* state) {
		const TokenType current_token_type = current_token(state).type;
		
		ast::Node* root;

		if (current_token_type == TokenType::KEYWORD_CAST
			|| current_token_type == TokenType::KEYWORD_BIT_CAST) {
			root = &next_as_node(state, ast::NodeType::CAST);

			const Token& lbrack = current_token(state);
			if (!skip(state, TokenType::SYM_LBRACK)) {
				report_error_on_last_token(state, ErrorCode::E3011);
				delete_node(state->node_alloc, root);
				return ExprResult{ false };
			}
			ExprResult type_result = type(state);
			if (!type_result.success) {
				delete_node(state->node_alloc, root);
				return ExprResult{ false };
			}
			root->children.push_back(type_result.result);
			
			if (!skip(state, TokenType::SYM_RBRACK)) {
				report_error_on_last_token(state, ErrorCode::E3012,
					std::format("Opening bracket was at ({},{})",
						lbrack.line_number,
						lbrack.column_number));
				delete_node(state->node_alloc, root);
				return ExprResult{ false };
			}
		}
		else {
			if (current_token_type != TokenType::KEYWORD_AUTO_CAST) {
				LOG_ERROR("Invalid state for casts");
				return ExprResult{ false };
			}
			root = &next_as_node(state, ast::NodeType::CAST);
		}
		if (!expect(state, TokenType::SYM_LPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3014);
			delete_node(state->node_alloc, root);
			return ExprResult{ false };
		}

		const Token lparen = current_token(state);
		skip(state, TokenType::SYM_LPAREN);

		ExprResult expr = expression_with_result(state, true);

		if (!expr.success) {
			delete_node(state->node_alloc, root);
			return ExprResult{ false };
		}
		else {
			root->children.push_back(expr.result);
		}

		if (!skip(state, TokenType::SYM_RPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3015,
				std::format("Opening parenthesis was at ({},{})",
					lparen.line_number,
					lparen.column_number));
			delete_node(state->node_alloc, root);
			return ExprResult{ false };
		}
		// Chaining on the result, like cast[ptr[Foo]](data).bar, needs no extra parentheses
		if (!postfix_operations(state, *root)) {
			delete_node(state->node_alloc, root);
			return ExprResult{ false };
		}
		return ExprResult{ true, root };
	}

	ExprResult if_expression(ParserState* state) {
		if (!expect(state, TokenType::KEYWORD_IF)) {
			return ExprResult{ false };
		}
		ast::Node& if_node = next_as_node(state, ast::NodeType::IF);

		ExprResult condition = expression_with_result(state, true);
		if (!condition.success) {
			delete_node(state->node_alloc, &if_node);
			return ExprResult{ false };
		}
		if_node.children.push_back(condition.result);

		ExprResult block_node = block(state);
		if (!block_node.success) {
			delete_node(state->node_alloc, &if_node);
			return ExprResult{ false };
		}
		if_node.children.push_back(block_node.result);

		/*
		 * Each else belongs to the if before it, and an else if is an if inside the else, so
		 * if a {} else if b {} else {} is IF(a, {}, ELSE(IF(b, {}, ELSE({})))).
		 */
		ast::Node* current_if = &if_node;
		while (expect(state, TokenType::KEYWORD_ELSE)) {
			ast::Node& else_node = next_as_node(state, ast::NodeType::ELSE,
				current_if);
			if (expect(state, TokenType::KEYWORD_IF)) {
				ast::Node& else_if_node = next_as_node(state, ast::NodeType::IF, &else_node);

				ExprResult else_condition = expression_with_result(state, true);
				if (!else_condition.success) {
					delete_node(state->node_alloc, &if_node);
					return ExprResult{ false };
				}
				else_if_node.children.push_back(else_condition.result);

				ExprResult else_block_node = block(state);
				if (!else_block_node.success) {
					delete_node(state->node_alloc, &if_node);
					return ExprResult{ false };
				}
				else_if_node.children.push_back(else_block_node.result);
				current_if = &else_if_node;
			}
			else {
				// Final else block
				ExprResult else_block_node = block(state);
				if (!else_block_node.success) {
					delete_node(state->node_alloc, &if_node);
					return ExprResult{ false };
				}
				else_node.children.push_back(else_block_node.result);
				break;
			}
		}
		return ExprResult{ true, &if_node };
	}

	bool for_loop(ParserState* state, ast::Node& parent) {
		ast::Node& for_node = next_as_node(state, ast::NodeType::FOR_LOOP, 
			&parent);

		// for &value in array, to iterate by reference
		ast::Node* value_parent = &for_node;
		if (expect(state, TokenType::SYM_AMPERSAND)) {
			value_parent = &next_as_node(state, ast::NodeType::UNARY_OPERATOR, &for_node);
		}
		if (!accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER,
			*value_parent)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			return false;
		}
		if (skip(state, TokenType::SYM_COMMA)
			&& !accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER,
				for_node)) {
			//NOTE(ches) loop iterator value, if there's a comma
			report_error_on_last_token(state, ErrorCode::E3009);
			return false;
		}

		if (!is_word(state, "in")) {
			report_error_on_last_token(state, ErrorCode::E3025);
			return false;
		}
		next_as_node(state, ast::NodeType::IN, &for_node);

		ExprResult expr = expression_with_result(state, true);
		if (!expr.success) {
			return false;
		}
		for_node.children.push_back(expr.result);

		// Like #reverse
		while (expect(state, TokenType::DIRECTIVE)) {
			next_as_node(state, ast::NodeType::DIRECTIVE, &for_node);
		}

		ExprResult block_node = block(state);
		if (!block_node.success) {
			return false;
		}
		for_node.children.push_back(block_node.result);

		return true;
	}

	bool loop(ParserState* state, ast::Node& parent) {
		ast::Node* with_part = nullptr;

		if (expect(state, TokenType::KEYWORD_WITH)) {
			with_part = &next_as_node(state, ast::NodeType::WITH_CLAUSE);
			if (!expect(state, TokenType::SYM_LBRACE)) {
				report_error_on_last_token(state, ErrorCode::E3018);
				delete_node(state->node_alloc, with_part);
				return false;
			}
			ast::Node& with_block = next_as_node(state, ast::NodeType::LIST, 
				with_part);

			while (expect(state, TokenType::IDENTIFIER)) {
				if (!any_definition(state, with_block)) {
					delete_node(state->node_alloc, with_part);
					return false;
				}
			}
			if (!skip(state, TokenType::SYM_RBRACE)) {
				report_error_on_last_token(state, ErrorCode::E3019,
					std::format("Opening brace was at ({},{})",
						with_block.value.line_number,
						with_block.value.column_number));
				delete_node(state->node_alloc, with_part);
				return false;
			}
		}
		if (!expect(state, TokenType::KEYWORD_LOOP)) {
			report_error_on_last_token(state, ErrorCode::E3026);
			if (with_part != nullptr) {
				delete_node(state->node_alloc, with_part);
			}
			return false;
		}
		ast::Node* loop_node = &next_as_node(state, ast::NodeType::LOOP,
			&parent);

		if (with_part != nullptr) {
			loop_node->children.push_back(with_part);
		}
		
		//NOTE(ches) just grab a directive, or not, don't care
		accept(state, TokenType::DIRECTIVE, ast::NodeType::DIRECTIVE, *loop_node);

		ExprResult block_node = block(state);
		if (!block_node.success) {
			return false;
		}
		loop_node->children.push_back(block_node.result);

		if (expect(state, TokenType::KEYWORD_WHILE)) {
			ast::Node& while_node = next_as_node(state, 
				ast::NodeType::WHILE_CLAUSE, loop_node);
			
			ExprResult expr = expression_with_result(state, true);
			if (!expr.success) {
				return false;
			}
			while_node.children.push_back(expr.result);
			
		}

		return true;
	}

	bool push_context(ParserState* state, ast::Node& parent) {
		ast::Node& push = next_as_node(state, ast::NodeType::PUSH_CONTEXT, 
			&parent);
		if (!expect(state, TokenType::IDENTIFIER)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			return false;
		}
		next_as_node(state, ast::NodeType::IDENTIFIER, &push);

		/*
		 * A whole context, from value. It can't be combined with overrides, since
		 * value (field = x) would read as a call.
		 */
		if (is_word(state, "from")) {
			ast::Node& from = next_as_node(state, ast::NodeType::KEYWORD_FROM, &push);
			ExprResult value = expression_with_result(state, true);
			if (!value.success) {
				return false;
			}
			from.children.push_back(value.result);

			if (!expect(state, TokenType::SYM_LBRACE)) {
				report_error_on_last_token(state, ErrorCode::E3018);
				return false;
			}
			ExprResult from_block = block(state);
			if (!from_block.success) {
				return false;
			}
			push.children.push_back(from_block.result);
			return true;
		}

		// The overrides, (field = value, ...), at least one
		if (!expect(state, TokenType::SYM_LPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3014);
			return false;
		}
		const Token lparen = current_token(state);
		ast::Node& overrides = next_as_node(state, ast::NodeType::LIST, &push);
		do {
			if (expect(state, TokenType::SYM_RPAREN) && !overrides.children.empty()) {
				// Trailing comma
				break;
			}
			if (!is_name(current_token(state).type)) {
				report_error_on_last_token(state, ErrorCode::E3009);
				return false;
			}
			ast::Node& field = next_as_node(state, ast::NodeType::IDENTIFIER);
			if (!expect(state, TokenType::OPERATOR_ASSIGN)) {
				report_error_on_last_token(state, ErrorCode::E3024);
				delete_node(state->node_alloc, &field);
				return false;
			}
			ast::Node& assign = next_as_node(state, ast::NodeType::BINARY_OPERATOR, &overrides);
			assign.children.push_back(&field);

			ExprResult value = expression_with_result(state, true);
			if (!value.success) {
				return false;
			}
			assign.children.push_back(value.result);
		} while (skip(state, TokenType::SYM_COMMA));

		if (!skip(state, TokenType::SYM_RPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3015,
				std::format("Opening parenthesis was at ({},{})",
					lparen.line_number,
					lparen.column_number));
			return false;
		}

		if (!expect(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return false;
		}
		ExprResult block_node = block(state);
		if (!block_node.success) {
			return false;
		}
		push.children.push_back(block_node.result);
		return true;
	}

	ExprResult enum_shorthand(ParserState* state) {
		const Token dot = current_token(state);
		if (!skip(state, TokenType::SYM_DOT)) {
			return ExprResult{ false };
		}
		// A member named by an #insert, like .#insert name in a quote: the #insert first among its children
		if (is_insert(state)) {
			ast::Node* result = state->node_alloc.new_object<ast::Node>(ast::NodeType::ENUM_SHORTHAND, dot);
			ast::Node& directive = next_as_node(state, ast::NodeType::DIRECTIVE, result);
			ExprResult operand = insert_operand(state);
			if (operand.success) {
				directive.children.push_back(operand.result);
			}
			if (!operand.success || !postfix_operations(state, *result)) {
				delete_node(state->node_alloc, result);
				return ExprResult{ false };
			}
			return ExprResult{ true, result };
		}
		if (!is_name(current_token(state).type)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			return ExprResult{ false };
		}

		ast::Node& result = next_as_node(state, ast::NodeType::ENUM_SHORTHAND);

		// A union variant with a value, like .Ok(value)
		if (!postfix_operations(state, result)) {
			delete_node(state->node_alloc, &result);
			return ExprResult{ false };
		}
		return ExprResult{ true, &result };
	}

	bool switch_statement(ParserState* state, ast::Node& parent) {
		ast::Node& switch_node = next_as_node(state, ast::NodeType::SWITCH, 
			&parent);

		// What to switch on, like value or task.state
		if (!expect(state, TokenType::IDENTIFIER)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			return false;
		}
		ExprResult subject = location(state);
		if (!subject.success) {
			return false;
		}
		switch_node.children.push_back(subject.result);

		if (!expect(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return false;
		}
		
		ast::Node& cases = next_as_node(state, ast::NodeType::LIST,
			&switch_node);

		if (!switch_cases(state, cases)) {
			return false;
		}

		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019,
				std::format("Opening brace was at ({},{})",
					cases.value.line_number,
					cases.value.column_number));
			return false;
		}

		return true;
	}

	// A switch's cases, and #inserts of more, up to its closing brace.
	bool switch_cases(ParserState* state, ast::Node& cases) {
		while (expect(state, TokenType::KEYWORD_CASE) || is_insert(state)) {
			if (is_insert(state)) {
				if (!insert_item(state, cases)) {
					return false;
				}
				continue;
			}
			ast::Node& current_case = next_as_node(state, 
				ast::NodeType::SWITCH_CASE, &cases);

			if (!switch_entry(state, current_case)) {
				return false;
			}
			while (expect(state, TokenType::SYM_COMMA)) {
				skip(state, TokenType::SYM_COMMA);
				if (!switch_entry(state, current_case)) {
					return false;
				}
			}

			if (!expect(state, TokenType::SYM_COLON)) {
				report_error_on_last_token(state, ErrorCode::E3027);
				return false;
			}
			skip(state, TokenType::SYM_COLON);

			/*
			 * Like C, a case runs every statement up to the next case, so it doesn't need
			 * braces. There must be at least one. They're kept in a BLOCK after the values.
			 */
			ast::Node* statements = state->node_alloc.new_object<ast::Node>(ast::NodeType::BLOCK,
				current_token(state));
			current_case.children.push_back(statements);
			do {
				if (!statement(state, *statements)) {
					return false;
				}
			} while (!expect(state, TokenType::KEYWORD_CASE)
				&& !expect(state, TokenType::SYM_RBRACE)
				&& !expect(state, TokenType::END_OF_FILE)
				&& !(expect(state, TokenType::DIRECTIVE)
					&& (current_token(state).value->compare("#fall_through") == 0 || is_insert(state))));

			if (expect(state, TokenType::DIRECTIVE) && !is_insert(state)) {
				next_as_node(state, ast::NodeType::DIRECTIVE, &cases);
			}
		}
		return true;
	}

	bool switch_entry(ParserState* state, ast::Node& parent) {
		const TokenType current_token_type = current_token(state).type;

		if (TokenType::OPERATOR_RANGE_EXCLUSIVE == current_token_type
			|| TokenType::OPERATOR_RANGE_INCLUSIVE == current_token_type) {
			report_error_on_last_token(state, ErrorCode::E3028);
			return false;
		}

		if (TokenType::LITERAL_INTEGER == current_token_type
			|| TokenType::LITERAL_CHAR == current_token_type) {

			ast::Node& lhs = next_as_node(state, ast::NodeType::LITERAL);
			const TokenType probably_range = current_token(state).type;
			if (TokenType::OPERATOR_RANGE_EXCLUSIVE == probably_range
				|| TokenType::OPERATOR_RANGE_INCLUSIVE == probably_range) {
				
				const TokenType next_token_type = next_token(state).type;

				if (next_token_type != current_token_type) {
					report_error_on_last_token(state, ErrorCode::E3029);
					parent.children.push_back(&lhs);
					return false;
				}
				//NOTE(ches) it's a range operator, we haven't accepted it yet
				ast::Node& op = next_as_node(state, 
					ast::NodeType::BINARY_OPERATOR, &parent);
				op.children.push_back(&lhs);
				//NOTE(ches) rhs
				next_as_node(state, ast::NodeType::LITERAL, &op);
			}
			else {
				//NOTE(ches) just a plain literal, no range
				parent.children.push_back(&lhs);
			}
			return true;
		}
		if (TokenType::LITERAL_STRING == current_token_type) {
			next_as_node(state, ast::NodeType::LITERAL, &parent);
			return true;
		}
		if (TokenType::IDENTIFIER == current_token_type) {
			ast::Node& lhs = next_as_node(state, ast::NodeType::IDENTIFIER);
			if (!expect(state, TokenType::SYM_DOT)) {
				report_error_on_last_token(state, ErrorCode::E3030);
				return false;
			}
			ast::Node& dot = next_as_node(state, ast::NodeType::DOT_ACCESS, &parent);
			dot.children.push_back(&lhs);
			if (!expect(state, TokenType::IDENTIFIER)) {
				report_error_on_last_token(state, ErrorCode::E3009);
				return false;
			}
			next_as_node(state, ast::NodeType::IDENTIFIER, &dot);
			return true;
		}
		if (TokenType::SYM_DOT == current_token_type) {
			ExprResult shorthand = enum_shorthand(state);
			if (!shorthand.success) {
				return false;
			}
			parent.children.push_back(shorthand.result);
			return true;
		}
		if (TokenType::SYM_UNDERSCORE == current_token_type) {
			next_as_node(state, ast::NodeType::UNDERSCORE, &parent);
			return true;
		}
		
		report_error_on_last_token(state, ErrorCode::E3017);
		return false;
	}

	ExprResult match_expression(ParserState* state) {
		ast::Node& match_node = next_as_node(state, ast::NodeType::MATCH);

		// What to match on, like value or result.state
		if (!expect(state, TokenType::IDENTIFIER)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			delete_node(state->node_alloc, &match_node);
			return ExprResult{ false };
		}
		ExprResult subject = location(state);
		if (!subject.success) {
			delete_node(state->node_alloc, &match_node);
			return ExprResult{ false };
		}
		// A result unwrapped first, like match find(key)? { ... }, as ? unwraps one anywhere else
		if (expect(state, TokenType::SYM_QUESTION)) {
			ast::Node* unwrap = &next_as_node(state, ast::NodeType::UNARY_OPERATOR);
			unwrap->children.push_back(subject.result);
			subject.result = unwrap;
		}
		match_node.children.push_back(subject.result);

		if (!expect(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			delete_node(state->node_alloc, &match_node);
			return ExprResult{ false };
		}

		ast::Node& cases = next_as_node(state, ast::NodeType::LIST,
			&match_node);

		if (!match_arms(state, cases)) {
			delete_node(state->node_alloc, &match_node);
			return ExprResult{ false };
		}

		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019,
				std::format("Opening brace was at ({},{})",
					cases.value.line_number,
					cases.value.column_number));
			delete_node(state->node_alloc, &match_node);
			return ExprResult{ false };
		}

		return ExprResult{ true, &match_node };
	}

	// A match's patterns, each with what it runs, and #inserts of more, up to its closing brace.
	bool match_arms(ParserState* state, ast::Node& cases) {
		while (!expect(state, TokenType::SYM_RBRACE)) {
			if (expect(state, TokenType::END_OF_FILE)) {
				break;
			}
			if (is_insert(state)) {
				if (!insert_item(state, cases)) {
					return false;
				}
				continue;
			}

			// Each arm starts with case, which also ends the previous arm's body
			if (!skip(state, TokenType::KEYWORD_CASE)) {
				report_error_on_last_token(state, ErrorCode::E3032);
				return false;
			}
			TokenType current = current_token(state).type;

			if (TokenType::LITERAL_INTEGER != current
				&& TokenType::LITERAL_CHAR != current
				&& TokenType::LITERAL_STRING != current
				&& TokenType::IDENTIFIER != current
				&& TokenType::SYM_DOT != current
				&& TokenType::KEYWORD_TRUE != current
				&& TokenType::KEYWORD_FALSE != current
				&& TokenType::SYM_UNDERSCORE != current
				&& TokenType::OPERATOR_RANGE_EXCLUSIVE != current
				&& TokenType::OPERATOR_RANGE_INCLUSIVE != current
				) {
				report_error_on_last_token(state, ErrorCode::E3017);
				return false;
			}
			ExprResult entry = match_entry(state);

			MyVector<ast::Node*> entries{};
			if (!entry.success) {
				return false;
			}
			entries.push_back(entry.result);

			while (skip(state, TokenType::SYM_COMMA)) {
				ExprResult next_entry = match_entry(state);

				if (!next_entry.success) {
					for (ast::Node* n : entries) {
						delete_node(state->node_alloc, n);
					}
					return false;
				}
				entries.push_back(next_entry.result);
			}

			if (!expect(state, TokenType::SYM_ARROW_DOUBLE)) {
				report_error_on_last_token(state, ErrorCode::E3031);
				for (ast::Node* n : entries) {
					delete_node(state->node_alloc, n);
				}
				return false;
			}

			ast::Node& current_case = next_as_node(state, 
				ast::NodeType::MATCH_CASE, &cases);

			for (ast::Node* n : entries) {
				current_case.children.push_back(n);
			}

			// An arm's body can also be a statement, like return
			if (!statement(state, current_case)) {
				return false;
			}
		}
		return true;
	}

	ExprResult match_entry(ParserState* state) {
		const TokenType current_token_type = current_token(state).type;

		if (TokenType::OPERATOR_RANGE_EXCLUSIVE == current_token_type
			|| TokenType::OPERATOR_RANGE_INCLUSIVE == current_token_type) {
			report_error_on_last_token(state, ErrorCode::E3028);
			return ExprResult{ false };
		}

		if (TokenType::LITERAL_INTEGER == current_token_type
			|| TokenType::LITERAL_CHAR == current_token_type) {

			ast::Node& lhs = next_as_node(state, ast::NodeType::LITERAL);

			const TokenType probably_range = current_token(state).type;
			if (TokenType::OPERATOR_RANGE_EXCLUSIVE == probably_range
				|| TokenType::OPERATOR_RANGE_INCLUSIVE == probably_range) {

				const TokenType next_token_type = next_token(state).type;

				if (next_token_type != current_token_type) {
					report_error_on_last_token(state, ErrorCode::E3029);
					delete_node(state->node_alloc, &lhs);
					return ExprResult{ false };
				}
				//NOTE(ches) it's a range operator, we haven't accepted it yet
				ast::Node& op = next_as_node(state, 
					ast::NodeType::BINARY_OPERATOR);
				op.children.push_back(&lhs);
				//NOTE(ches) rhs
				next_as_node(state, ast::NodeType::LITERAL, &op);
				return ExprResult{ true, &op };
			}
			else {
				//NOTE(ches) just a plain literal, no range
				return ExprResult{ true, &lhs };
			}
		}
		if (TokenType::LITERAL_STRING == current_token_type
			|| TokenType::KEYWORD_TRUE == current_token_type
			|| TokenType::KEYWORD_FALSE == current_token_type
			) {
			ast::Node& literal = next_as_node(state, ast::NodeType::LITERAL);
			return ExprResult{ true, &literal };
		}
		if (TokenType::IDENTIFIER == current_token_type) {
			ast::Node& identifier = next_as_node(state, 
				ast::NodeType::IDENTIFIER);

			if (expect(state, TokenType::SYM_LPAREN)) {
				ast::Node& type_list = next_as_node(state, 
					ast::NodeType::PAREN_GROUP, &identifier);

				while (!expect(state, TokenType::SYM_RPAREN)) {
					const TokenType next_token_type = current_token(state).type;
					const TokenType after = next_token(state).type;

					// A name for the value, or a pattern it must match too, like .NotFound or Some(x)
					if (TokenType::IDENTIFIER == next_token_type && TokenType::SYM_LPAREN != after && TokenType::SYM_DOT != after) {
						next_as_node(state, ast::NodeType::IDENTIFIER, &type_list);
					}
					else if (TokenType::IDENTIFIER == next_token_type || TokenType::SYM_DOT == next_token_type
						|| TokenType::LITERAL_INTEGER == next_token_type || TokenType::LITERAL_CHAR == next_token_type
						|| TokenType::LITERAL_STRING == next_token_type || TokenType::KEYWORD_TRUE == next_token_type
						|| TokenType::KEYWORD_FALSE == next_token_type) {
						ExprResult nested = match_entry(state);
						if (!nested.success) {
							delete_node(state->node_alloc, &identifier);
							return ExprResult{ false };
						}
						type_list.children.push_back(nested.result);
					}
					else if (TokenType::SYM_UNDERSCORE == next_token_type) {
						next_as_node(state, ast::NodeType::UNDERSCORE,
							&type_list);
					}
					else if (TokenType::SYM_ARROW_DOUBLE == next_token_type) {
						report_error_on_last_token(state, ErrorCode::E3015,
							std::format("Opening parenthesis was at ({},{})",
								type_list.value.line_number,
								type_list.value.column_number));
						delete_node(state->node_alloc, &identifier);
						return ExprResult{ false };
					}
					else {
						report_error_on_last_token(state, ErrorCode::E3017);
						delete_node(state->node_alloc, &identifier);
						return ExprResult{ false };
					}
					skip(state, TokenType::SYM_COMMA);
				}

				if (!skip(state, TokenType::SYM_RPAREN)) {
					report_error_on_last_token(state, ErrorCode::E3015,
						std::format("Opening parenthesis was at ({},{})",
							type_list.value.line_number,
							type_list.value.column_number));
					delete_node(state->node_alloc, &identifier);
					return ExprResult{ false };
				}
				return ExprResult{ true, &identifier };
			}
			//NOTE(ches) plain identifier

			if (!expect(state, TokenType::SYM_DOT)) {
				return ExprResult{ true, &identifier };
			}
			//NOTE(ches) dot syntax

			ast::Node& dot = next_as_node(state, ast::NodeType::DOT_ACCESS);
			dot.children.push_back(&identifier);
			if (!expect(state, TokenType::IDENTIFIER)) {
				report_error_on_last_token(state, ErrorCode::E3009);
				delete_node(state->node_alloc, &identifier);
				return ExprResult{ false };
			}
			next_as_node(state, ast::NodeType::IDENTIFIER, &dot);
			return ExprResult{ true, &dot };
		}
		if (TokenType::SYM_DOT == current_token_type) {
			return enum_shorthand(state);
		}
		if (TokenType::SYM_UNDERSCORE == current_token_type) {
			ast::Node& underscore = next_as_node(state, 
				ast::NodeType::UNDERSCORE);
			return ExprResult{ true, &underscore };
		}

		report_error_on_last_token(state, ErrorCode::E3017);
		return ExprResult{ false };
	}
}
