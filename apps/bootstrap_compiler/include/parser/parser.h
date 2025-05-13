#pragma once

#include <initializer_list>
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
	/// <summary>
	/// Skip a token if present.
	/// </summary>
	/// <param name="state">The token state.</param>
	/// <param name="tokens">The tokens we want to skip.</param>
	/// <returns>true if the token was skipped, false if there is a different
	/// token.</returns>
	bool skip(ParserState* state, std::initializer_list<TokenType> tokens);

	void file(std::string_view file_path, MyVector<Token>& tokens, MyVector<ast::Node>& output);
	void package_statement(ParserState* state);
}
