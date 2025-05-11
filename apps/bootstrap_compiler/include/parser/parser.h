#pragma once

#include "lexer/token.h"
#include "parser/ast_types.h"

namespace hemera::parser {

	struct ParserState {
		size_t current = 0;
		MyVector<Token>& tokens;
		MyVector<ast::Node>& output;

		ParserState(MyVector<Token>& tokens, MyVector<ast::Node>& output)
			: current{ 0 }
			, tokens{ tokens }
			, output{ output }
		{}
		ParserState(const ParserState&) = default;
		ParserState(ParserState&&) = delete;
		ParserState& operator=(const ParserState&) = delete;
		ParserState& operator=(ParserState&&) = delete;
		~ParserState() = default;
	};

	void next(ParserState* state);
	bool accept(ParserState* state, TokenType token);
	bool expect(ParserState* state, TokenType token);

	void file(MyVector<Token>& tokens, MyVector<ast::Node>& output);
	void package_statement(ParserState* state);
}
