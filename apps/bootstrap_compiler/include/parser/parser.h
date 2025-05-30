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
	bool package_statement(ParserState* state, ast::Node& parent);
	bool imports(ParserState* state, ast::Node& parent);
	bool import(ParserState* state, ast::Node& parent);
	void const_definitions(ParserState* state, ast::Node& parent);
	bool any_definition(ParserState* state, ast::Node& parent);
	bool const_definition_rhs(ParserState* state, ast::Node& parent);
	bool mut_definition_rhs(ParserState* state, ast::Node& parent);
	bool declaration(ParserState* state, ast::Node& parent);
	bool decl_rhs(ParserState* state, ast::Node& parent);
	bool type(ParserState* state, ast::Node& parent);
	bool simple_type(ParserState* state, ast::Node& parent);
	bool complicated_type(ParserState* state, ast::Node& parent);
	bool generic_tag(ParserState* state, ast::Node& parent);
	bool function_signature(ParserState* state, ast::Node& parent);
	bool function_parameter_list(ParserState* state, ast::Node& parent);
	bool default_value(ParserState* state, ast::Node& parent);
	bool function_output_list(ParserState* state, ast::Node& parent);
	bool literal(ParserState* state, ast::Node& parent);
	bool expression_with_result(ParserState* state, ast::Node& parent);
	bool function_decl(ParserState* state, ast::Node& parent);
	bool struct_decl(ParserState* state, ast::Node& parent);
	bool union_decl(ParserState* state, ast::Node& parent);
	bool enum_decl(ParserState* state, ast::Node& parent);
	bool function_body(ParserState* state, ast::Node& parent);
	bool struct_body(ParserState* state, ast::Node& parent);
	bool union_body(ParserState* state, ast::Node& parent);
	bool enum_body(ParserState* state, ast::Node& parent);


}
