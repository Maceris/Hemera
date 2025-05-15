
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

	void next(ParserState* state) {
		Token current = current_token(state);
		state->output.emplace_back(ast::NodeType::LEAF, current);
		state->current += 1;
	}

	bool accept(ParserState* state, TokenType token) {
		if (current_token(state).type == token) {
			next(state);
			return true;
		}
		return false;
	}

	bool expect(ParserState* state, TokenType token) {
		return current_token(state).type == token;
	}

	bool skip(ParserState* state, std::initializer_list<TokenType> tokens) {
		Token current = current_token(state);

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

		// File comments, legal statements
		while (skip(&state, { TokenType::COMMENT_BLOCK, TokenType::COMMENT_LINE })) {}

		package_statement(&state);
		imports(&state);
	}

	void package_statement(ParserState* state) {
		if (!accept(state, TokenType::KEYWORD_PACKAGE)) {
			report_error_on_last_token(state, ErrorCode::E3001);
			return;
		}

		if (!accept(state, TokenType::IDENTIFIER)) {
			report_error_on_last_token(state, ErrorCode::E3002);
			return;
		}
	}

	void imports(ParserState* state) {
		while (expect(state, TokenType::KEYWORD_IMPORT)) {
			import(state);
		}
	}

	void import(ParserState* state) {
		accept(state, TokenType::KEYWORD_IMPORT);

		if (!accept(state, TokenType::IDENTIFIER)) {
			report_error_on_last_token(state, ErrorCode::E3003);
		}

		if (expect(state, TokenType::KEYWORD_AS)) {
			accept(state, TokenType::KEYWORD_AS);
			if (!accept(state, TokenType::IDENTIFIER)) {
				report_error_on_last_token(state, ErrorCode::E3005);
			}
		}

		if (expect(state, TokenType::KEYWORD_FROM)) {
			accept(state, TokenType::KEYWORD_FROM);
			if (!accept(state, TokenType::LITERAL_STRING)) {
				report_error_on_last_token(state, ErrorCode::E3004);
			}
		}
		
	}

}