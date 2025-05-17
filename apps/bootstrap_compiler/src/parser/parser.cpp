
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

	static void skip_comments(ParserState* state) {
		TokenType current = current_token(state).type;
		while (current == TokenType::COMMENT_BLOCK || current == TokenType::COMMENT_LINE) {
			state->current += 1;
			current = current_token(state).type;
		}
	}

	void next(ParserState* state) {
		Token current = current_token(state);
		state->output.emplace_back(ast::NodeType::LEAF, current);
		state->current += 1;
	}

	ast::Node& next_non_terminal(ParserState* state, ast::NodeType type) {
		Token current = current_token(state);
		ast::Node& result = state->output.emplace_back(type, current);
		state->current += 1;
		return result;
	}

	bool accept(ParserState* state, TokenType token) {
		skip_comments(state);
		if (current_token(state).type == token) {
			next(state);
			return true;
		}
		return false;
	}

	void accept_backtracked(ParserState* state, std::initializer_list<TokenType> tokens) {
		size_t index = clamp_index(state->current - 1, state->tokens.size());
		Token token = state->tokens[index];
		for (auto& expected : tokens) {
			if (token.type == expected) {
				state->output.emplace_back(ast::NodeType::LEAF, token);
				return;
			}
		}
	}

	bool expect(ParserState* state, TokenType token) {
		skip_comments(state);
		return current_token(state).type == token;
	}

	bool skip(ParserState* state, TokenType token) {
		skip_comments(state);
		if (current_token(state).type == token) {
			state->current += 1;
			return true;
		}
		return false;
	}

	bool skip_any(ParserState* state, std::initializer_list<TokenType> tokens) {
		skip_comments(state);
		for (auto& token : tokens) {
			if (current_token(state).type == token) {
				state->current += 1;
				return true;
			}
		}

		return false;
	}

	void file(std::string_view file_path, MyVector<Token>& tokens,
		MyVector<ast::Node>& output)
	{
		ParserState state(file_path, tokens, output);

		package_statement(&state);
		imports(&state);
		const_definitions(&state);
	}

	void comments(ParserState* state) {
		while (accept(state, TokenType::COMMENT_BLOCK) 
			|| accept(state, TokenType::COMMENT_LINE)) {}
	}

	void package_statement(ParserState* state) {
		if (!skip(state, TokenType::KEYWORD_PACKAGE)) {
			report_error_on_last_token(state, ErrorCode::E3001);
			return;
		}
		ast::Node& node = next_non_terminal(state, ast::NodeType::PACKAGE);

		if (!accept(state, TokenType::IDENTIFIER)) {
			report_error_on_last_token(state, ErrorCode::E3002);
			return;
		}
		node.children.push_back(1);
	}

	void imports(ParserState* state) {
		while (expect(state, TokenType::KEYWORD_IMPORT)) {
			import(state);
		}
	}

	void import(ParserState* state) {
		ast::Node& node = next_non_terminal(state, ast::NodeType::IMPORT);

		skip(state, TokenType::KEYWORD_IMPORT);

		if (!accept(state, TokenType::IDENTIFIER)) {
			report_error_on_last_token(state, ErrorCode::E3003);
			return;
		}

		ast::offset children = 1;
		node.children.push_back(children);//NOTE(ches) identifier

		if (expect(state, TokenType::KEYWORD_AS)) {
			accept(state, TokenType::KEYWORD_AS);
			if (!accept(state, TokenType::IDENTIFIER)) {
				report_error_on_last_token(state, ErrorCode::E3005);
				return;
			}
			//NOTE(ches) as, so we know it's an alias
			children += 1;
			node.children.push_back(children);
			children += 1;
			node.children.push_back(children);//NOTE(ches) alias
		}

		if (expect(state, TokenType::KEYWORD_FROM)) {
			accept(state, TokenType::KEYWORD_FROM);
			if (!accept(state, TokenType::LITERAL_STRING)) {
				report_error_on_last_token(state, ErrorCode::E3004);
				return;
			}
			//NOTE(ches) from, so we know it's not an alias
			children += 1;
			node.children.push_back(children);
			children += 1;
			node.children.push_back(children);//NOTE(ches) source of import
		}
	}

	void const_definitions(ParserState* state) {
		while (expect(state, TokenType::IDENTIFIER)) {
			declaration(state);
			const_definition_rhs(state);
		}
	}

	void any_definition(ParserState* state) {
		declaration(state);

		if (expect(state, TokenType::SYM_COLON)) {
			const_definition_rhs(state);
		}
		else if (expect(state, TokenType::OPERATOR_ASSIGN)) {
			mut_definition_rhs(state);
		}
		else {
			//TODO(ches) error
		}
	}

	void const_definition_rhs(ParserState* state) {
		if (!accept(state, TokenType::SYM_COLON)) {
			//TODO(ches) error
			return;
		}
		decl_rhs(state);
	}

	void mut_definition_rhs(ParserState* state) {
		if (!accept(state, TokenType::OPERATOR_ASSIGN)) {
			//TODO(ches) error
			return;
		}
		decl_rhs(state);
	}

	void declaration(ParserState* state) {
		accept_backtracked(state, { TokenType::COMMENT_BLOCK, TokenType::COMMENT_LINE });
		if (!accept(state, TokenType::IDENTIFIER)) {
			//TODO(ches) error
			return;
		}
		if (!accept(state, TokenType::SYM_COLON)) {
			//TODO(ches) error
			return;
		}
		//TODO(ches) type
	}

	void decl_rhs(ParserState* state) {
		//TODO(ches) decls
		if (state == nullptr) {} //TODO(ches) remove this
	}

}