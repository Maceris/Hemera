#pragma once

#include <initializer_list>
#include <string_view>

#include "lexer/token.h"
#include "parser/ast_types.h"

namespace hemera::parser {

	struct ParserState {
		size_t current = 0;
		MyVector<Token>& tokens;
		Allocator<ast::Node> node_alloc;
		std::string_view file_path;
		bool has_errors;
		const char _padding[7] = { 0 };

		ParserState(std::string_view file_path, MyVector<Token>& tokens,
			Allocator<ast::Node> node_alloc);
		ParserState(const ParserState&);
		ParserState(ParserState&&) = delete;
		ParserState& operator=(const ParserState&) = delete;
		ParserState& operator=(ParserState&&) = delete;
		~ParserState();
	};

	struct ExprResult {
		bool success;
		char _padding[7] = { 0 };
		ast::Node* result;

		ExprResult(bool success = true, ast::Node* result = nullptr);
		ExprResult(const ExprResult&);
		ExprResult(ExprResult&&);
		ExprResult& operator=(const ExprResult&);
		ExprResult& operator=(ExprResult&&);
		~ExprResult();
	};

	ast::Node& next_as_node(ParserState* state, ast::NodeType type, ast::Node* parent = nullptr);
	bool accept(ParserState* state, TokenType token, ast::NodeType type, ast::Node& parent);
	bool expect(ParserState* state, TokenType token);
	
	bool skip(ParserState* state, TokenType token);

	ast::Node* file(std::string_view file_path, MyVector<Token>& tokens, Allocator<ast::Node> node_alloc);
	bool package_statement(ParserState* state, ast::Node& parent);
	bool imports(ParserState* state, ast::Node& parent);
	bool import(ParserState* state, ast::Node& parent);
	bool const_definitions(ParserState* state, ast::Node& parent);
	bool any_definition(ParserState* state, ast::Node& parent);
	bool const_definition_rhs(ParserState* state, ast::Node& parent);
	bool mut_definition_rhs(ParserState* state, ast::Node& parent);
	ExprResult declaration(ParserState* state, ast::Node& parent);
	bool decl_rhs(ParserState* state, ast::Node& parent);
	bool function_decl(ParserState* state, ast::Node& parent);
	bool struct_decl(ParserState* state, ast::Node& parent);
	bool union_decl(ParserState* state, ast::Node& parent);
	bool enum_decl(ParserState* state, ast::Node& parent);
	ExprResult type(ParserState* state);
	ExprResult simple_type(ParserState* state);
	ExprResult complicated_type(ParserState* state);
	bool array_dimension(ParserState* state, ast::Node& parent);
	ExprResult function_signature(ParserState* state);
	bool function_parameter_list(ParserState* state, ast::Node& parent);
	bool function_output_list(ParserState* state, ast::Node& parent);
	bool default_value(ParserState* state, ast::Node& parent);
	ExprResult block(ParserState* state);
	bool expression(ParserState* state, ast::Node& parent);
	ExprResult expression_with_result(ParserState* state);
	bool expression_without_result(ParserState* state, ast::Node& parent);
	bool literal(ParserState* state, ast::Node& parent);
	bool struct_body(ParserState* state, ast::Node& parent);
	bool union_body(ParserState* state, ast::Node& parent);
	bool enum_body(ParserState* state, ast::Node& parent);
	bool generic_tag(ParserState* state, ast::Node& parent);
	ExprResult expr_lvl_1(ParserState* state);
	ExprResult expr_lvl_2(ParserState* state);
	ExprResult expr_lvl_3(ParserState* state);
	ExprResult expr_lvl_4(ParserState* state);
	ExprResult expr_lvl_5(ParserState* state);
	ExprResult expr_lvl_6(ParserState* state);
	ExprResult expr_lvl_7(ParserState* state);
	ExprResult expr_lvl_8(ParserState* state);
	ExprResult expr_lvl_9(ParserState* state);
	ExprResult expr_lvl_10(ParserState* state);
	ExprResult expr_lvl_11(ParserState* state);
	ExprResult location(ParserState* state);
	ExprResult struct_literal(ParserState* state);
	bool function_call(ParserState* state, ast::Node& parent);
	bool function_call_input_list(ParserState* state, ast::Node& parent);
	ExprResult cast_expression(ParserState* state);
	ExprResult if_expression(ParserState* state);
	bool for_loop(ParserState* state, ast::Node& parent);
	bool loop(ParserState* state, ast::Node& parent);
	bool push_context(ParserState* state, ast::Node& parent);
	ExprResult enum_shorthand(ParserState* state);
	bool switch_statement(ParserState* state, ast::Node& parent);
	bool switch_entry(ParserState* state, ast::Node& parent);
	ExprResult match_expression(ParserState* state);
	ExprResult match_entry(ParserState* state);

}
