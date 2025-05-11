
#include "error/reporting.h"

#include "parser/parser.h"
#include "util/logger.h"

namespace hemera::parser {

	static inline size_t clamp_index(size_t index, size_t size) {
		static const size_t ZERO = 0;
		return std::max(ZERO, std::min(size - 1, index));
	}

	static inline Token current_token(ParserState* state) {
		size_t index = clamp_index(state->current, state->tokens.size());
		return state->tokens[index];
	}

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

	void file(MyVector<Token>& tokens, MyVector<ast::Node>& output) {
		ParserState state(tokens, output);

		package_statement(&state);
	}

	void package_statement(ParserState* state) {
		if (!accept(state, TokenType::KEYWORD_PACKAGE)) {
			//TODO(ches) log error
			return;
		}
	}

}