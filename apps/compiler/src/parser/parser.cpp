#include <format>

#include "error/reporting.h"

#include "parser/parser.h"
#include "util/logger.h"

namespace hemera::parser {

	ParserState::ParserState(std::string_view file_path, 
		MyVector<Token>& tokens, Allocator<ast::Node> node_alloc)
		: current{ 0 }
		, tokens{ tokens }
		, node_alloc{ node_alloc }
		, file_path{ file_path }
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
			|| TokenType::SYM_AMPERSAND == type
			|| TokenType::SYM_UNDERSCORE == type
			|| TokenType::PIPE_REORDER_IDENTIFIER == type
			|| TokenType::DIRECTIVE == type
			|| TokenType::KEYWORD_MATCH == type
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
		Allocator<ast::Node> node_alloc)
	{
		ParserState state(file_path, tokens, node_alloc);

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

	bool package_statement(ParserState* state, ast::Node& parent) {
		if (!expect(state, TokenType::KEYWORD_PACKAGE)) {
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
		while (current_type == TokenType::KEYWORD_IMPORT 
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

				// #run and #assert take an expression
				if (directive.value.value->compare("#run") == 0
					|| directive.value.value->compare("#assert") == 0) {
					ExprResult expr = expression_with_result(state, true);
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
			if (expect(state, TokenType::KEYWORD_IMPORT)) {
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
		ast::Node& node = next_as_node(state, ast::NodeType::IMPORT, &parent);

		skip(state, TokenType::KEYWORD_IMPORT);

		if (!accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER,
			node)) {
			report_error_on_last_token(state, ErrorCode::E3003);
			return false;
		}

		if (expect(state, TokenType::KEYWORD_AS)) {
			accept(state, TokenType::KEYWORD_AS, ast::NodeType::KEYWORD_AS,
				node);
			if (!accept(state, TokenType::IDENTIFIER,
				ast::NodeType::IDENTIFIER, node)) {
				report_error_on_last_token(state, ErrorCode::E3005);
				return false;
			}
		}

		if (expect(state, TokenType::KEYWORD_FROM)) {
			accept(state, TokenType::KEYWORD_FROM, ast::NodeType::KEYWORD_FROM,
				node);
			if (!accept(state, TokenType::LITERAL_STRING, 
				ast::NodeType::LITERAL, node)) {
				report_error_on_last_token(state, ErrorCode::E3004);
				return false;
			}
		}

		return true;
	}

	bool const_definitions(ParserState* state, ast::Node& parent) {
		while (expect(state, TokenType::IDENTIFIER) 
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

				// #run and #assert take an expression
				if (directive.value.value->compare("#run") == 0
					|| directive.value.value->compare("#assert") == 0) {
					ExprResult expr = expression_with_result(state, true);
					if (!expr.success) {
						return false;
					}
					directive.children.push_back(expr.result);
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
				|| directive.value.value->compare("#never_returns") == 0
				|| directive.value.value->compare("#externally_initialized") == 0
				|| directive.value.value->compare("#section") == 0) {
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
		if (TokenType::KEYWORD_DISTINCT == current_type
			|| TokenType::KEYWORD_ALIAS == current_type
			) {
			if (accept(state, TokenType::KEYWORD_DISTINCT, ast::NodeType::KEYWORD_DISTINCT, parent)
				&& !expect(state, TokenType::KEYWORD_ALIAS)) {
				report_error_on_last_token(state, ErrorCode::E3033);
				return false;
			}
			accept(state, TokenType::KEYWORD_ALIAS, ast::NodeType::KEYWORD_ALIAS, parent);
			
			ExprResult rhs = type(state);
			if (!rhs.success) {
				return false;
			}
			parent.children.push_back(rhs.result);
			return true;
		}
		ExprResult rhs = expression_with_result(state, true);
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

	ExprResult type(ParserState* state) {

		if (expect(state, TokenType::KEYWORD_MUT) || 
			expect(state, TokenType::IDENTIFIER)) {
			return simple_type(state);
		}
		else if (expect(state, TokenType::KEYWORD_FN)) {
			ExprResult result = complicated_type(state);
			if (result.success) {
				accept(state, TokenType::SYM_QUESTION, ast::NodeType::UNARY_OPERATOR,
					*result.result);
			}
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

	bool array_dimension(ParserState* state, ast::Node& parent) {
		ast::Node& dims = next_as_node(state, ast::NodeType::ARRAY_DIMENSION,
			&parent);
		if (expect(state, TokenType::LITERAL_INTEGER)) {
			accept(state, TokenType::LITERAL_INTEGER, ast::NodeType::LITERAL,
				dims);
		}
		else if (expect(state, TokenType::OPERATOR_RANGE_ARRAY)) {
			accept(state, TokenType::OPERATOR_RANGE_ARRAY, 
				ast::NodeType::RANGE_ARRAY, dims);
		}
		else if (expect(state, TokenType::IDENTIFIER)) {
			// A named constant, possibly from another package, like [QUEUE_SIZE]
			accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER, dims);
			while (expect(state, TokenType::SYM_DOT)
				&& TokenType::IDENTIFIER == next_token(state).type) {
				accept(state, TokenType::SYM_DOT, ast::NodeType::DOT_ACCESS, dims);
				accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER, dims);
			}
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
		 * #never_returns is part of the function's type. Only it continues a signature, since
		 * line breaks mean nothing, and the next statement may start with a directive (#if).
		 */
		if (expect(state, TokenType::DIRECTIVE)
			&& current_token(state).value->compare("#never_returns") == 0) {
			next_as_node(state, ast::NodeType::DIRECTIVE, &node);
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
			) {

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

	bool function_output_list(ParserState* state, ast::Node& parent) {
		if (expect(state, TokenType::KEYWORD_VOID)) {
			accept(state, TokenType::KEYWORD_VOID, ast::NodeType::VOID, parent);
			return true;
		}
		if (expect(state, TokenType::IDENTIFIER)) {
			ExprResult id = simple_type(state);
			if (!id.success) {
				return false;
			}
			parent.children.push_back(id.result);
			return true;
		}
		if (expect(state, TokenType::SYM_LPAREN)) {
			const Token& lparen = current_token(state);
			if (TokenType::KEYWORD_FN == next_token(state).type) {
				skip(state, TokenType::SYM_LPAREN);
				ExprResult fn = function_signature(state);
				if (!fn.success) {
					return false;
				}
				parent.children.push_back(fn.result);
			}
			else {
				ast::Node& node = next_as_node(state, ast::NodeType::LIST, &parent);

				while (expect(state, TokenType::SYM_LPAREN)
					|| expect(state, TokenType::KEYWORD_MUT)
					|| expect(state, TokenType::IDENTIFIER)
					) {
					
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
					}
					skip(state, TokenType::SYM_COMMA);
					if (accept(state, TokenType::SYM_COLON,
						ast::NodeType::COLON, node)) {
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
			else if (expect(state, TokenType::KEYWORD_ALL)) {
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

			// #run and #assert take an expression: what to run, or the condition to check
			if (directive.value.value->compare("#run") == 0
				|| directive.value.value->compare("#assert") == 0) {
				ExprResult expr = expression_with_result(state, true);
				if (!expr.success) {
					return false;
				}
				directive.children.push_back(expr.result);
			}
			return true;
		}
		case TokenType::ANNOTATION:
		case TokenType::COMMENT_BLOCK:
		case TokenType::COMMENT_LINE:
		case TokenType::INVALID:
		case TokenType::KEYWORD_ALIAS:
		case TokenType::KEYWORD_ALL:
		case TokenType::KEYWORD_AS:
		case TokenType::KEYWORD_CASE:
		case TokenType::KEYWORD_DISTINCT:
		case TokenType::KEYWORD_ELSE:
		case TokenType::KEYWORD_ENUM:
		case TokenType::KEYWORD_FN:
		case TokenType::KEYWORD_FROM:
		case TokenType::KEYWORD_IMPORT:
		case TokenType::KEYWORD_IN:
		case TokenType::KEYWORD_IS_NONE:
		case TokenType::KEYWORD_IS_SOME:
		case TokenType::KEYWORD_MUT:
		case TokenType::KEYWORD_OR_BREAK:
		case TokenType::KEYWORD_OR_CONTINUE:
		case TokenType::KEYWORD_OR_ELSE:
		case TokenType::KEYWORD_OR_RETURN:
		case TokenType::KEYWORD_PACKAGE:
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
		if (is_typed_literal(state, TokenType::SYM_LBRACE)) {
			return struct_literal(state);
		}
		if (is_typed_literal(state, TokenType::SYM_LBRACK)) {
			return array_literal(state);
		}
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

	bool struct_body(ParserState* state, ast::Node& parent) {
		while (expect(state, TokenType::IDENTIFIER)
			|| expect(state, TokenType::KEYWORD_USING)
			|| expect(state, TokenType::SYM_UNDERSCORE)) {

			if (expect(state, TokenType::KEYWORD_USING)) {
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
			if (!accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER, *names)) {
				report_error_on_last_token(state, ErrorCode::E3009);
				delete_node(state->node_alloc, names);
				return false;
			}
		}

		if (!expect(state, TokenType::SYM_COLON)) {
			report_error_on_last_token(state, ErrorCode::E3010);
			delete_node(state->node_alloc, names);
			return false;
		}
		ast::Node& definition = next_as_node(state, ast::NodeType::DEFINITION, &parent);
		definition.children.push_back(names);

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

		if (expect(state, TokenType::OPERATOR_ASSIGN)) {
			return mut_definition_rhs(state, definition);
		}
		return true;
	}

	bool union_body(ParserState* state, ast::Node& parent) {
		while (accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER, parent)) {
			//NOTE(ches) this is all one entry in the union
			if (expect(state, TokenType::SYM_LPAREN)) {
				// The payload's types are children of the paren group, so the next variant isn't
				// mistaken for one of them
				ast::Node& payload = next_as_node(state, ast::NodeType::PAREN_GROUP, &parent);
				const Token& lparen = payload.value;
				//NOTE(ches) will simply exit when we hit the rparen
				while (accept(state, TokenType::IDENTIFIER, ast::NodeType::IDENTIFIER, payload)) {
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
		while (expect(state, TokenType::IDENTIFIER)) {
			ast::Node& member = next_as_node(state, ast::NodeType::IDENTIFIER, &parent);

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
			const bool is_value = !is_declaration
				&& (TokenType::LITERAL_INTEGER == current
					|| TokenType::KEYWORD_TRUE == current
					|| TokenType::KEYWORD_FALSE == current
					|| TokenType::SYM_DOT == current
					|| TokenType::OPERATOR_MINUS == current);
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
				&& TokenType::SYM_COLON == next_token(state).type) {
				// A value parameter, like capacity: usize
				ast::Node& name = next_as_node(state, ast::NodeType::IDENTIFIER);
				ast::Node& colon = next_as_node(state, ast::NodeType::COLON, &node);
				colon.children.push_back(&name);
				ExprResult value_type = type(state);
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
			return ExprResult(std::move(underscore));
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

		const TokenType current = current_token(state).type;
		if (current == TokenType::OPERATOR_ASSIGN
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
			|| current == TokenType::OPERATOR_ASSIGN_SUB
			) {

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
		if (current == TokenType::SYM_DOT) {
			return enum_shorthand(state);
		}
		if (current == TokenType::DIRECTIVE) {
			ast::Node& result = next_as_node(state, ast::NodeType::DIRECTIVE);
			// Only #run takes an expression, others like #caller_location stand alone
			if (result.value.value->compare("#run") == 0) {
				ExprResult expr = expression_with_result(state, true);
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
		if (expect(state, TokenType::OPERATOR_RANGE_EXCLUSIVE)
			|| expect(state, TokenType::OPERATOR_RANGE_INCLUSIVE)) {
			ast::Node& range = next_as_node(state, ast::NodeType::UNARY_OPERATOR);
			ExprResult end = expression_with_result(state, true);
			if (!end.success) {
				delete_node(state->node_alloc, &range);
				return ExprResult{ false };
			}
			range.children.push_back(end.result);
			return ExprResult{ true, &range };
		}

		ExprResult index = expression_with_result(state, true);
		if (!index.success) {
			return ExprResult{ false };
		}
		if (expect(state, TokenType::OPERATOR_RANGE_ARRAY)) {
			ast::Node& range = next_as_node(state, ast::NodeType::UNARY_OPERATOR);
			range.children.push_back(index.result);
			return ExprResult{ true, &range };
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
			|| expect(state, TokenType::OPERATOR_DEREFERENCE)) {


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
				if (!accept(state, TokenType::IDENTIFIER,
					ast::NodeType::IDENTIFIER, target)) {
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
			while (expect(state, TokenType::IDENTIFIER)) {
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

			if (current_token_type == TokenType::IDENTIFIER 
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

		while (expect(state, TokenType::KEYWORD_ELSE)) {
			ast::Node& else_node = next_as_node(state, ast::NodeType::ELSE, 
				&if_node);
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
				else_node.children.push_back(else_block_node.result);
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

		if (!accept(state, TokenType::KEYWORD_IN, ast::NodeType::IN, for_node)) {
			report_error_on_last_token(state, ErrorCode::E3025);
			return false;
		}

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
		if (expect(state, TokenType::KEYWORD_FROM)) {
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
			if (!expect(state, TokenType::IDENTIFIER)) {
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
		if (!skip(state, TokenType::SYM_DOT)) {
			return ExprResult{ false };
		}
		if (!expect(state, TokenType::IDENTIFIER)) {
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

		while (expect(state, TokenType::KEYWORD_CASE)) {
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
					&& current_token(state).value->compare("#fall_through") == 0));

			if (expect(state, TokenType::DIRECTIVE)) {
				next_as_node(state, ast::NodeType::DIRECTIVE, &cases);
			}
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
		match_node.children.push_back(subject.result);

		if (!expect(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			delete_node(state->node_alloc, &match_node);
			return ExprResult{ false };
		}

		ast::Node& cases = next_as_node(state, ast::NodeType::LIST,
			&match_node);

		while (!expect(state, TokenType::SYM_RBRACE)) {
			if (expect(state, TokenType::END_OF_FILE)) {
				break;
			}

			// Each arm starts with case, which also ends the previous arm's body
			if (!skip(state, TokenType::KEYWORD_CASE)) {
				report_error_on_last_token(state, ErrorCode::E3032);
				delete_node(state->node_alloc, &match_node);
				return ExprResult{ false };
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
				delete_node(state->node_alloc, &match_node);
				return ExprResult{ false };
			}
			ExprResult entry = match_entry(state);

			MyVector<ast::Node*> entries{};
			if (!entry.success) {
				delete_node(state->node_alloc, &match_node);
				return ExprResult{ false };
			}
			entries.push_back(entry.result);

			while (skip(state, TokenType::SYM_COMMA)) {
				ExprResult next_entry = match_entry(state);

				if (!next_entry.success) {
					delete_node(state->node_alloc, &match_node);
					for (ast::Node* n : entries) {
						delete_node(state->node_alloc, n);
					}
					return ExprResult{ false };
				}
				entries.push_back(next_entry.result);
			}

			if (!expect(state, TokenType::SYM_ARROW_DOUBLE)) {
				report_error_on_last_token(state, ErrorCode::E3031);
				delete_node(state->node_alloc, &match_node);
				for (ast::Node* n : entries) {
					delete_node(state->node_alloc, n);
				}
				return ExprResult{ false };
			}

			ast::Node& current_case = next_as_node(state, 
				ast::NodeType::MATCH_CASE, &cases);

			for (ast::Node* n : entries) {
				current_case.children.push_back(n);
			}

			// An arm's body can also be a statement, like return
			if (!statement(state, current_case)) {
				delete_node(state->node_alloc, &match_node);
				return ExprResult{ false };
			}
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

					if (TokenType::IDENTIFIER == next_token_type) {
						next_as_node(state, ast::NodeType::IDENTIFIER, 
							&type_list);
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
