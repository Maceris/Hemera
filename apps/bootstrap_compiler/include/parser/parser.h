#pragma once

#include <string_view>

#include "lexer/token.h"
#include "parser/ast_types.h"

namespace hemera::parser {

	struct ParserState {
		size_t current = 0;
		MyVector<Token>& tokens;
		MyVector<ast::Node>& output;
		std::string_view file_path;
		bool has_errors;
		const char _padding[7] = { 0 };

		ParserState(std::string_view file_path, MyVector<Token>& tokens,
			MyVector<ast::Node>& output);
		ParserState(const ParserState&);
		ParserState(ParserState&&) = delete;
		ParserState& operator=(const ParserState&) = delete;
		ParserState& operator=(ParserState&&) = delete;
		~ParserState();
	};

	void next(ParserState* state);
	bool accept(ParserState* state, TokenType token);
	bool expect(ParserState* state, TokenType token);

	void file(std::string_view file_path, MyVector<Token>& tokens, MyVector<ast::Node>& output);
	void package_statement(ParserState* state);
}
