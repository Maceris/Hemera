
#include "error/reporting.h"

#include "parser/parser.h"
#include "util/logger.h"

namespace hemera::parser {

	ParserState::ParserState(std::string_view file_path, 
		MyVector<Token>& tokens, MyVector<ast::Node>& output)
		: current{ 0 }
		, tokens{ tokens }
		, output{ output }
		, file_path{ file_path }
		, has_errors{ false }
	{}
	ParserState::ParserState(const ParserState&) = default;
	ParserState::~ParserState() = default;

	static inline size_t clamp_index(size_t index, size_t size) {
		static const size_t ZERO = 0;
		return std::max(ZERO, std::min(size - 1, index));
	}

	static inline Token current_token(ParserState* state) {
		size_t index = clamp_index(state->current, state->tokens.size());
		return state->tokens[index];
	}

	/*
	 * Presumes 
	 * 1. the child is the last node added to the vector
	 * 2. we add nodes in pre-order traversal order
	 * 3. the state's current position hasn't been updated (thus is 
	 *    at size - 1 for the vector, where our child node is)
	 */
	static inline void add_child(ParserState* state, ast::Node& parent,
		ast::Node& child) {
		size_t child_position = state->current;
		ast::offset to_child = parent.total_children + 1;
		ast::offset to_parent = -to_child;

		child.parent = to_parent;

		ast::Node* next_parent = &parent;

		//TODO(ches) instead of this, aggregate and update the parent once
		while (to_parent != 0) {
			next_parent->total_children += 1;
			// Recurse up the parents, updating child counts
			child_position += to_parent; // becomes its parents, to_parent is negative
			to_parent = next_parent->parent;
			next_parent = &state->output[child_position];
		}
	}

	static inline void report_error_on_last_token(ParserState* state, ErrorCode code) {
		Token token = current_token(state);
		report_error(code, state->file_path, token.line_number, token.column_number);
		state->has_errors = true;
		//TODO(ches) opportunity for showing the line, or printing the token, other text
	}

	//static inline void report_warning_on_last_token(ParserState* state, WarningCode code) {
	//	Token token = current_token(state);
	//	report_warning(code, state->file_path, token.line_number, token.column_number);
	//	//TODO(ches) opportunity for showing the line, or printing the token, other text
	//}

	void next(ParserState* state, ast::Node& parent) {
		Token current = current_token(state);
		ast::Node& child = state->output.emplace_back(ast::NodeType::LEAF, current);
		add_child(state, parent, child);
		state->current += 1;
	}

	ast::Node& next_as_node(ParserState* state, ast::NodeType type, ast::Node& parent) {
		Token current = current_token(state);
		ast::Node& result = state->output.emplace_back(type, current);
		add_child(state, parent, result);
		state->current += 1;
		return result;
	}

	bool accept(ParserState* state, TokenType token, ast::Node& parent) {
		if (current_token(state).type == token) {
			next(state, parent);
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

	bool skip_any(ParserState* state, std::initializer_list<TokenType> tokens) {
		for (auto& token : tokens) {
			if (current_token(state).type == token) {
				state->current += 1;
				return true;
			}
		}

		return false;
	}

	bool could_be_expression(ParserState* state) {
		return could_be_expression_with_result(state) 
			|| could_be_expression_without_result(state);
	}

	bool could_be_expression_with_result(ParserState* state) {
		if (expect(state, TokenType::LITERAL_CHAR)) {
			return true;
		}
		if (expect(state, TokenType::LITERAL_FLOATING_POINT)) {
			return true;
		}
		if (expect(state, TokenType::LITERAL_INTEGER)) {
			return true;
		}
		if (expect(state, TokenType::LITERAL_STRING)) {
			return true;
		}
		if (expect(state, TokenType::IDENTIFIER)) {
			return true;
		}
		if (expect(state, TokenType::OPERATOR_PLUS)) {
			return true;
		}
		if (expect(state, TokenType::OPERATOR_MINUS)) {
			return true;
		}
		if (expect(state, TokenType::OPERATOR_BITWISE_XOR)) {
			return true;
		}
		if (expect(state, TokenType::KEYWORD_IF)) {
			return true;
		}
		if (expect(state, TokenType::OPERATOR_NOT)) {
			return true;
		}
		if (expect(state, TokenType::KEYWORD_TRUE)) {
			return true;
		}
		if (expect(state, TokenType::KEYWORD_FALSE)) {
			return true;
		}
		if (expect(state, TokenType::SYM_LBRACE)) {
			return true;
		}
		return false;
	}

	bool could_be_expression_without_result(ParserState* state) {
		if (expect(state, TokenType::KEYWORD_FOR)) {
			return true;
		}
		if (expect(state, TokenType::KEYWORD_WITH)) {
			return true;
		}
		if (expect(state, TokenType::KEYWORD_LOOP)) {
			return true;
		}
		return false;
	}

	void file(std::string_view file_path, MyVector<Token>& tokens,
		MyVector<ast::Node>& output)
	{
		ParserState state(file_path, tokens, output);

		Token current(TokenType::END_OF_FILE, 0, 0);//TODO(ches) ???
		ast::Node& node = state.output.emplace_back(ast::NodeType::FILE, current);

		if (!package_statement(&state, node)) {
			//TODO(ches) log this?
			return;
		}
		if (!imports(&state, node)) {
			//TODO(ches) log this?
			return;
		}
		const_definitions(&state, node);
	}

	bool package_statement(ParserState* state, ast::Node& parent) {
		if (!skip(state, TokenType::KEYWORD_PACKAGE)) {
			report_error_on_last_token(state, ErrorCode::E3001);
			return false;
		}
		ast::Node& node = next_as_node(state, ast::NodeType::PACKAGE, parent);

		if (!accept(state, TokenType::IDENTIFIER, node)) {
			report_error_on_last_token(state, ErrorCode::E3002);
			return false;
		}
		return true;
	}

	bool imports(ParserState* state, ast::Node& parent) {
		while (expect(state, TokenType::KEYWORD_IMPORT)) {
			if (!import(state, parent)) {
				//TODO(ches) log this?
				return false;
			}
		}
		return true;
	}

	bool import(ParserState* state, ast::Node& parent) {
		ast::Node& node = next_as_node(state, ast::NodeType::IMPORT, parent);

		skip(state, TokenType::KEYWORD_IMPORT);

		if (!accept(state, TokenType::IDENTIFIER, node)) {
			report_error_on_last_token(state, ErrorCode::E3003);
			return false;
		}

		if (expect(state, TokenType::KEYWORD_AS)) {
			accept(state, TokenType::KEYWORD_AS, node);
			if (!accept(state, TokenType::IDENTIFIER, node)) {
				report_error_on_last_token(state, ErrorCode::E3005);
				return false;
			}
		}

		if (expect(state, TokenType::KEYWORD_FROM)) {
			accept(state, TokenType::KEYWORD_FROM, node);
			if (!accept(state, TokenType::LITERAL_STRING, node)) {
				report_error_on_last_token(state, ErrorCode::E3004);
				return false;
			}
		}

		return true;
	}

	void const_definitions(ParserState* state, ast::Node& parent) {
		while (expect(state, TokenType::IDENTIFIER)) {
			if (!declaration(state, parent)) {
				//TODO(ches) log this?
				return;
			}

			if (!const_definition_rhs(state, parent)) {
				//TODO(ches) log this?
				return;
			}
		}
	}

	bool any_definition(ParserState* state, ast::Node& parent) {
		if (!declaration(state, parent)) {
			return false;
		}

		if (expect(state, TokenType::SYM_COLON)) {
			return const_definition_rhs(state, parent);
		}
		else if (expect(state, TokenType::OPERATOR_ASSIGN)) {
			return mut_definition_rhs(state, parent);
		}
		else {
			report_error_on_last_token(state, ErrorCode::E3006);
			return false;
		}
	}

	bool const_definition_rhs(ParserState* state, ast::Node& parent) {
		if (!accept(state, TokenType::SYM_COLON, parent)) {
			report_error_on_last_token(state, ErrorCode::E3007);
			return false;
		}
		return decl_rhs(state, parent);
	}

	bool mut_definition_rhs(ParserState* state, ast::Node& parent) {
		if (!accept(state, TokenType::OPERATOR_ASSIGN, parent)) {
			report_error_on_last_token(state, ErrorCode::E3008);
			return false;
		}
		return decl_rhs(state, parent);
	}

	bool declaration(ParserState* state, ast::Node& parent) {
		if (!accept(state, TokenType::IDENTIFIER, parent)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			return false;
		}
		if (!accept(state, TokenType::SYM_COLON, parent)) {
			report_error_on_last_token(state, ErrorCode::E3010);
			return false;
		}
		return type(state, parent);
	}

	bool decl_rhs(ParserState* state, ast::Node& parent) {
		if (expect(state, TokenType::KEYWORD_FN)) {
			return function_decl(state, parent);
		}
		if (expect(state, TokenType::KEYWORD_STRUCT)) {
			return struct_decl(state, parent);
		}
		if (expect(state, TokenType::KEYWORD_UNION)) {
			return union_decl(state, parent);
		}
		if (expect(state, TokenType::KEYWORD_ENUM)) {
			return enum_decl(state, parent);
		}
		if (expect(state, TokenType::KEYWORD_DISTINCT) 
			|| expect(state, TokenType::KEYWORD_ALIAS)
			|| expect(state, TokenType::IDENTIFIER)
			|| expect(state, TokenType::KEYWORD_FN)
			) {
			// Might or might not find these
			accept(state, TokenType::KEYWORD_DISTINCT, parent);
			accept(state, TokenType::KEYWORD_ALIAS , parent);
			return type(state, parent);
		}
		return expression_with_result(state, parent);
	}

	bool type(ParserState* state, ast::Node& parent) {
		ast::Node& node = next_as_node(state, ast::NodeType::TYPE, parent);
		if (expect(state, TokenType::IDENTIFIER)) {
			return simple_type(state, node);
		}
		else if (expect(state, TokenType::KEYWORD_FN)) {
			return complicated_type(state, node);
		}
		else {
			report_error_on_last_token(state, ErrorCode::E3017);
			return false;
		}
	}

	bool simple_type(ParserState* state, ast::Node& parent) {
		if (expect(state, TokenType::IDENTIFIER)) {
			accept(state, TokenType::IDENTIFIER, parent);
			if (expect(state, TokenType::SYM_LBRACK)) {
				if (!generic_tag(state, parent)) {
					return false;
				}
			}
			//TODO(ches) array indices
			return true;
		}
		else {
			report_error_on_last_token(state, ErrorCode::E3017);
			return false;
		}
	}

	bool complicated_type(ParserState* state, ast::Node& parent) {
		if (expect(state, TokenType::KEYWORD_FN)) {
			return function_signature(state, parent);
		}
		else {
			report_error_on_last_token(state, ErrorCode::E3017);
			return false;
		}
	}

	bool generic_tag(ParserState* state, ast::Node& parent) {
		ast::Node& node = next_as_node(state, ast::NodeType::GENERIC_TAG, parent);
		if (!skip(state, TokenType::SYM_LBRACK)) {
			report_error_on_last_token(state, ErrorCode::E3011);
			return false;
		}

		while (!expect(state, TokenType::SYM_RBRACK)) {
			if (!type(state, node)) {
				return false;
			}
			if (expect(state, TokenType::SYM_COMMA)) {
				skip(state, TokenType::SYM_COMMA);
			}
		}
		if (!skip(state, TokenType::SYM_RBRACK)) {
			report_error_on_last_token(state, ErrorCode::E3012);
			return false;
		}
		return true;
	}

	bool function_signature(ParserState* state, ast::Node& parent) {
		ast::Node& node = next_as_node(state, ast::NodeType::FUNCTION, parent);
		if (!accept(state, TokenType::KEYWORD_FN, node)) {
			report_error_on_last_token(state, ErrorCode::E3013);
			return false;
		}
		if (expect(state, TokenType::SYM_LBRACK)) {
			if (!generic_tag(state, node)) {
				return false;
			}
		}
		if (!skip(state, TokenType::SYM_LPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3014);
			return false;
		}
		if (expect(state, TokenType::IDENTIFIER)) {
			if (!function_parameter_list(state, node)) {
				return false;
			}
		}
		if (!skip(state, TokenType::SYM_RPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3015);
			return false;
		}
		if (expect(state, TokenType::SYM_ARROW_SINGLE)) {
			if (!function_output_list(state, node)) {
				return false;
			}
		}
		return true;
	}

	bool function_parameter_list(ParserState* state, ast::Node& parent) {
		ast::Node& node = next_as_node(state, ast::NodeType::LIST, parent);

		while (accept(state, TokenType::IDENTIFIER, node)) {
			if (!skip(state, TokenType::SYM_COLON)) {
				report_error_on_last_token(state, ErrorCode::E3016);
				return false;
			}
			type(state, node);
			if (expect(state, TokenType::OPERATOR_EQUAL)) {
				skip(state, TokenType::OPERATOR_EQUAL);
				if (!default_value(state, node)) {
					return false;
				}
			}
		}
		return true;
	}

	bool default_value(ParserState* state, ast::Node& parent) {
		if (expect(state, TokenType::DIRECTIVE)) {
			accept(state, TokenType::DIRECTIVE, parent);
			return true;
		}
		else {
			return literal(state, parent);
		}
	}

	bool function_output_list(ParserState* state, ast::Node& parent) {
		if (expect(state, TokenType::KEYWORD_VOID)) {
			accept(state, TokenType::KEYWORD_VOID, parent);
			return true;
		}
		if (expect(state, TokenType::IDENTIFIER)) {
			return simple_type(state, parent);
		}
		if (skip(state, TokenType::SYM_LPAREN)) {

			if (expect(state, TokenType::KEYWORD_FN)) {
				if (!function_signature(state, parent)) {
					return false;
				}
				if (!skip(state, TokenType::SYM_RPAREN)) {
					report_error_on_last_token(state, ErrorCode::E3015);
					return false;
				}
			}
			else {
				ast::Node& node = next_as_node(state, ast::NodeType::LIST, parent);

				while (!expect(state, TokenType::SYM_RPAREN)) {
					if (skip(state, TokenType::SYM_LPAREN)) {
						if (!function_signature(state, node)) {
							return false;
						}
						if (!skip(state, TokenType::SYM_RPAREN)) {
							report_error_on_last_token(state, ErrorCode::E3015);
							return false;
						}
						skip(state, TokenType::SYM_COMMA);
						continue;
					}
					if (expect(state, TokenType::IDENTIFIER)) {
						if (!simple_type(state, node)) {
							return false;
						}
					}
					skip(state, TokenType::SYM_COMMA);
					if (accept(state, TokenType::SYM_COLON, node)) {
						if (!accept(state, TokenType::IDENTIFIER, node)) {
							report_error_on_last_token(state, ErrorCode::E3016);
							return false;
						}
						skip(state, TokenType::SYM_COMMA);
					}
				}

				if (!skip(state, TokenType::SYM_RPAREN)) {
					report_error_on_last_token(state, ErrorCode::E3015);
					return false;
				}
			}
		}
		return true;
	}

	bool literal(ParserState* state, ast::Node& parent) {
		if (expect(state, TokenType::LITERAL_CHAR)) {
			accept(state, TokenType::LITERAL_CHAR, parent);
			return true;
		}
		if (expect(state, TokenType::LITERAL_FLOATING_POINT)) {
			accept(state, TokenType::LITERAL_FLOATING_POINT, parent);
			return true;
		}
		if (expect(state, TokenType::LITERAL_INTEGER)) {
			accept(state, TokenType::LITERAL_INTEGER, parent);
			return true;
		}
		if (expect(state, TokenType::LITERAL_STRING)) {
			accept(state, TokenType::LITERAL_STRING, parent);
			return true;
		}
		return type(state, parent);
	}

	bool expression(ParserState* state, ast::Node& parent) {
		if (could_be_expression_with_result(state)) {
			if (!expression_with_result(state, parent)) {
				return false;
			}
			return expression_continuation(state, parent);
		}
		if (!could_be_expression_without_result(state)) {
			LOG_ERROR("Trying to parse an expression at an invalid time");
			return false;
		}
		return expression_with_result(state, parent);
	}
	
	bool expression_continuation(ParserState* state, ast::Node& parent) {
		if (expect(state, TokenType::KEYWORD_OR_BREAK)) {
			return accept(state, TokenType::KEYWORD_OR_BREAK, parent);
		}
		if (expect(state, TokenType::KEYWORD_OR_CONTINUE)) {
			return accept(state, TokenType::KEYWORD_OR_CONTINUE, parent);
		}
		if (expect(state, TokenType::KEYWORD_OR_ELSE)) {
			accept(state, TokenType::KEYWORD_OR_ELSE, parent);
			return expression(state, parent);
		}
		if (expect(state, TokenType::KEYWORD_OR_RETURN)) {
			accept(state, TokenType::KEYWORD_OR_RETURN, parent);
			if (could_be_expression_with_result(state)) {
				if (!expression_with_result(state, parent)) {
					return false;
				}
				//NOTE(ches) we can keep chaining these
				return expression_continuation(state, parent);
			}
		}
		//NOTE(ches) indicates nothing broke, not that we found a continuation
		return true;
	}

	bool expression_with_result(ParserState* state, ast::Node& parent) {
		if (state == nullptr) { parent.type; } //TODO(ches) remove this
		return true;
	}

	bool expression_with_result_before_continuation(ParserState* state, ast::Node& parent) {
		if (state == nullptr) { parent.type; } //TODO(ches) remove this
		return true;
	}

	bool expression_without_result(ParserState* state, ast::Node& parent) {
		if (state == nullptr) { parent.type; } //TODO(ches) remove this
		return true;
	}

	bool function_decl(ParserState* state, ast::Node& parent) {
		if (!function_signature(state, parent)) {
			return false;
		}
		return function_body(state, parent);
	}

	bool struct_decl(ParserState* state, ast::Node& parent) {
		skip(state, TokenType::KEYWORD_STRUCT);
		ast::Node& node = next_as_node(state, ast::NodeType::STRUCT, parent);
		
		if (expect(state, TokenType::SYM_LBRACK)) {
			if (!generic_tag(state, node)) {
				return false;
			}
		}
		if (!skip(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return false;
		}
		if (!struct_body(state, node)) {
			report_error_on_last_token(state, ErrorCode::E3020);
			return false;
		}
		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019);
			return false;
		}
		return true;
	}

	bool union_decl(ParserState* state, ast::Node& parent) {
		skip(state, TokenType::KEYWORD_UNION);
		ast::Node& node = next_as_node(state, ast::NodeType::UNION, parent);
		
		if (expect(state, TokenType::SYM_LBRACK)) {
			if (!generic_tag(state, node)) {
				return false;
			}
		}
		if (!skip(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return false;
		}
		if (!union_body(state, node)) {
			report_error_on_last_token(state, ErrorCode::E3020);
			return false;
		}
		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019);
			return false;
		}
		return true;
	}

	bool enum_decl(ParserState* state, ast::Node& parent) {
		skip(state, TokenType::KEYWORD_ENUM);
		ast::Node& node = next_as_node(state, ast::NodeType::ENUM, parent);
		
		if (!skip(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return false;
		}
		if (!enum_body(state, node)) {
			report_error_on_last_token(state, ErrorCode::E3020);
			return false;
		}
		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019);
			return false;
		}
		return true;
	}

	bool function_body(ParserState* state, ast::Node& parent) {
		if (!skip(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return false;
		}

		while (could_be_expression(state)) {
			expression(state, parent);
		}

		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019);
			return false;
		}
		return true;
	}

	bool struct_body(ParserState* state, ast::Node& parent) {
		while (expect(state, TokenType::IDENTIFIER)) {
			any_definition(state, parent);
		}
		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019);
			return false;
		}
		return true;
	}

	bool union_body(ParserState* state, ast::Node& parent) {
		while (accept(state, TokenType::IDENTIFIER, parent)) {
			//NOTE(ches) this is all one entry in the union
			if (accept(state, TokenType::SYM_LPAREN, parent)) {
				//NOTE(ches) will simply exit when we hit the rparen
				while (accept(state, TokenType::IDENTIFIER, parent)) {
					//TODO(ches) do we need generics syntax here?
					if (!accept(state, TokenType::SYM_COMMA, parent)) {
						if (!expect(state, TokenType::SYM_RPAREN)) {
							/*
							 * NOTE(ches) if we have something besides comma,
							 * then it had better be the closing parenthesis
							 */
							report_error_on_last_token(state, ErrorCode::E3009);
							return false;
						}
					}
				}
				if (!accept(state, TokenType::SYM_RPAREN, parent)) {
					report_error_on_last_token(state, ErrorCode::E3015);
					return false;
				}
			}
			
			skip(state, TokenType::SYM_COMMA);
		}
		return true;
	}

	bool enum_body(ParserState* state, ast::Node& parent) {
		while (accept(state, TokenType::IDENTIFIER, parent)) {
			skip(state, TokenType::SYM_COMMA);
		}
		return true;
	}
}