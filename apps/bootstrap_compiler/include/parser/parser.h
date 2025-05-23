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

	void next(ParserState* state, ast::Node& parent);
	ast::Node& next_as_node(ParserState* state, ast::NodeType type, ast::Node& parent);
	bool accept(ParserState* state, TokenType token, ast::Node& parent);
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
	void comments(ParserState* state, ast::Node& parent);
	void package_statement(ParserState* state, ast::Node& parent);
	void imports(ParserState* state, ast::Node& parent);
	void import(ParserState* state, ast::Node& parent);
	void const_definitions(ParserState* state, ast::Node& parent);
	void any_definition(ParserState* state, ast::Node& parent);
	void const_definition_rhs(ParserState* state, ast::Node& parent);
	void mut_definition_rhs(ParserState* state, ast::Node& parent);
	void declaration(ParserState* state, ast::Node& parent);
	void decl_rhs(ParserState* state, ast::Node& parent);
	void type(ParserState* state, ast::Node& parent);
	void simple_type(ParserState* state, ast::Node& parent);
	void complicated_type(ParserState* state, ast::Node& parent);
	void generic_tag(ParserState* state, ast::Node& parent);
	void function_signature(ParserState* state, ast::Node& parent);
	void function_parameter_list(ParserState* state, ast::Node& parent);
	void default_value(ParserState* state, ast::Node& parent);
	void function_output_list(ParserState* state, ast::Node& parent);
}
