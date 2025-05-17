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
	ast::Node& next_non_terminal(ParserState* state, ast::NodeType type);
	bool accept(ParserState* state, TokenType token);
	/// <summary>
	/// Accept the token just before the previous token, if it matches the
	/// specified token type. Otherwise does nothing.
	/// </summary>
	/// <param name="state">The parser state.</param>
	/// <param name="tokens">The types of token we want to accept.</param>
	void accept_backtracked(ParserState* state, std::initializer_list<TokenType> tokens);
	bool expect(ParserState* state, TokenType token);
	
	bool skip(ParserState* state, TokenType token);

	/// <summary>
	/// Skip a token if present.
	/// </summary>
	/// <param name="state">The parser state.</param>
	/// <param name="tokens">The tokens we want to skip.</param>
	/// <returns>true if the token was skipped, false if there is a different
	/// token.</returns>
	bool skip_any(ParserState* state, std::initializer_list<TokenType> tokens);

	void file(std::string_view file_path, MyVector<Token>& tokens, MyVector<ast::Node>& output);
	void comments(ParserState* state);
	void package_statement(ParserState* state);
	void imports(ParserState* state);
	void import(ParserState* state);
	void const_definitions(ParserState* state);
	void any_definition(ParserState* state);
	void const_definition_rhs(ParserState* state);
	void mut_definition_rhs(ParserState* state);
	void declaration(ParserState* state);
	void decl_rhs(ParserState* state);
}
