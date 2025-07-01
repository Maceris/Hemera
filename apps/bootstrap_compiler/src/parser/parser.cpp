
#include "error/reporting.h"

#include "parser/parser.h"
#include "util/logger.h"

namespace hemera::parser {

	ParserState::ParserState(std::string_view file_path, 
		MyVector<Token>& tokens, Allocator<ast::Node> node_alloc)
		: current{ 0 }
		, tokens{ tokens }
		, node_alloc{ node_alloc }
		, file_path{ file_path }
		, has_errors{ false }
	{}
	ParserState::ParserState(const ParserState&) = default;
	ParserState::~ParserState() = default;


	ExprResult::ExprResult(bool success, ast::Node* result)
		: success{ success }
		, result{ result }
	{}
	ExprResult::ExprResult(const ExprResult&) = default;
	ExprResult::ExprResult(ExprResult&&) = default;
	ExprResult& ExprResult::operator=(const ExprResult&) = default;
	ExprResult& ExprResult::operator=(ExprResult&&) = default;
	ExprResult::~ExprResult() = default;

	static inline size_t clamp_index(size_t index, size_t size) {
		static const size_t ZERO = 0;
		return std::max(ZERO, std::min(size - 1, index));
	}

	static inline Token current_token(ParserState* state) {
		size_t index = clamp_index(state->current, state->tokens.size());
		return state->tokens[index];
	}

	static inline Token next_token(ParserState* state, size_t offset = 1) {
		size_t index = clamp_index(state->current + offset, state->tokens.size());
		return state->tokens[index];
	}

	static inline void report_error_on_last_token(ParserState* state, ErrorCode code) {
		Token token = current_token(state);
		report_error(code, state->file_path, token.line_number, token.column_number);
		state->has_errors = true;
	}

	static void delete_node(Allocator<ast::Node>& node_alloc, ast::Node* node) {
		if (node == nullptr) {
			return;
		}
		for (ast::Node* child : node->children) {
			delete_node(node_alloc, child);
			node->children.clear();
		}
		node_alloc.delete_object<ast::Node>(node);
	}

	void next(ParserState* state, ast::Node& parent) {
		Token current = current_token(state);
		//TODO(ches) get rid of LEAF and use more accurate node types
		ast::Node* child = state->node_alloc.new_object<ast::Node>(ast::NodeType::LEAF, current);
		parent.children.push_back(child);
		state->current += 1;
	}

	ast::Node& next_as_node(ParserState* state, ast::NodeType type, ast::Node* parent) {
		Token current = current_token(state);
		ast::Node* result = state->node_alloc.new_object<ast::Node>(type, current);
		if (parent != nullptr) {
			parent->children.push_back(result);
		}
		state->current += 1;
		return *result;
	}

	bool accept(ParserState* state, TokenType token, ast::Node& parent) {
		if (current_token(state).type == token) {
			next(state, parent);
			return true;
		}
		return false;
	}

	bool expect(ParserState* state, TokenType token) {
		return current_token(state).type == token;
	}

	bool skip(ParserState* state, TokenType token) {
		if (current_token(state).type == token) {
			state->current += 1;
			return true;
		}
		return false;
	}

	bool skip_any(ParserState* state, std::initializer_list<TokenType> tokens) {
		for (auto& token : tokens) {
			if (current_token(state).type == token) {
				state->current += 1;
				return true;
			}
		}

		return false;
	}

	void file(std::string_view file_path, MyVector<Token>& tokens,
		Allocator<ast::Node> node_alloc)
	{
		ParserState state(file_path, tokens, node_alloc);

		Token current(TokenType::END_OF_FILE, 0, 0);//TODO(ches) ???
		ast::Node* node = node_alloc.new_object<ast::Node>(ast::NodeType::FILE, current);

		if (!package_statement(&state, *node)) {
			return;
		}
		if (!imports(&state, *node)) {
			return;
		}
		if (!const_definitions(&state, *node)) {
			return;
		}

		//TODO(ches) flatten tree into array at the end
	}

	bool package_statement(ParserState* state, ast::Node& parent) {
		if (!skip(state, TokenType::KEYWORD_PACKAGE)) {
			report_error_on_last_token(state, ErrorCode::E3001);
			return false;
		}
		ast::Node& node = next_as_node(state, ast::NodeType::PACKAGE, &parent);

		if (!accept(state, TokenType::IDENTIFIER, node)) {
			report_error_on_last_token(state, ErrorCode::E3002);
			return false;
		}
		return true;
	}

	bool imports(ParserState* state, ast::Node& parent) {

		TokenType current_type = current_token(state).type;
		while (current_type == TokenType::KEYWORD_IMPORT 
			|| current_type == TokenType::DIRECTIVE
		) {
			if (current_type == TokenType::DIRECTIVE) {
				ast::Node& directive = next_as_node(state, ast::NodeType::DIRECTIVE, &parent);
				if (!skip(state, TokenType::SYM_LBRACE)) {
					report_error_on_last_token(state, ErrorCode::E3018);
					return false;
				}
				if (!imports(state, directive)) {
					return false;
				}
				if (!skip(state, TokenType::SYM_RBRACE)) {
					report_error_on_last_token(state, ErrorCode::E3019);
					return false;
				}
			}
			else if (!import(state, parent)) {
				return false;
			}
			current_type = current_token(state).type;
		}
		return true;
	}

	bool import(ParserState* state, ast::Node& parent) {
		ast::Node& node = next_as_node(state, ast::NodeType::IMPORT, &parent);

		skip(state, TokenType::KEYWORD_IMPORT);

		if (!accept(state, TokenType::IDENTIFIER, node)) {
			report_error_on_last_token(state, ErrorCode::E3003);
			return false;
		}

		if (expect(state, TokenType::KEYWORD_AS)) {
			accept(state, TokenType::KEYWORD_AS, node);
			if (!accept(state, TokenType::IDENTIFIER, node)) {
				report_error_on_last_token(state, ErrorCode::E3005);
				return false;
			}
		}

		if (expect(state, TokenType::KEYWORD_FROM)) {
			accept(state, TokenType::KEYWORD_FROM, node);
			if (!accept(state, TokenType::LITERAL_STRING, node)) {
				report_error_on_last_token(state, ErrorCode::E3004);
				return false;
			}
		}

		return true;
	}

	bool const_definitions(ParserState* state, ast::Node& parent) {
		while (expect(state, TokenType::IDENTIFIER)) {
			if (!declaration(state, parent)) {
				return false;
			}

			if (!const_definition_rhs(state, parent)) {
				return false;
			}
		}
		return true;
	}

	bool any_definition(ParserState* state, ast::Node& parent) {
		if (!declaration(state, parent)) {
			return false;
		}

		if (expect(state, TokenType::SYM_COLON)) {
			return const_definition_rhs(state, parent);
		}
		else if (expect(state, TokenType::OPERATOR_ASSIGN)) {
			return mut_definition_rhs(state, parent);
		}
		else {
			report_error_on_last_token(state, ErrorCode::E3006);
			return false;
		}
	}

	bool const_definition_rhs(ParserState* state, ast::Node& parent) {
		if (!accept(state, TokenType::SYM_COLON, parent)) {
			report_error_on_last_token(state, ErrorCode::E3007);
			return false;
		}
		return decl_rhs(state, parent);
	}

	bool mut_definition_rhs(ParserState* state, ast::Node& parent) {
		if (!accept(state, TokenType::OPERATOR_ASSIGN, parent)) {
			report_error_on_last_token(state, ErrorCode::E3008);
			return false;
		}
		return decl_rhs(state, parent);
	}

	bool declaration(ParserState* state, ast::Node& parent) {
		if (!accept(state, TokenType::IDENTIFIER, parent)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			return false;
		}
		if (!accept(state, TokenType::SYM_COLON, parent)) {
			report_error_on_last_token(state, ErrorCode::E3010);
			return false;
		}
		return type(state, parent);
	}

	bool decl_rhs(ParserState* state, ast::Node& parent) {
		if (expect(state, TokenType::KEYWORD_FN)) {
			return function_decl(state, parent);
		}
		if (expect(state, TokenType::KEYWORD_STRUCT)) {
			return struct_decl(state, parent);
		}
		if (expect(state, TokenType::KEYWORD_UNION)) {
			return union_decl(state, parent);
		}
		if (expect(state, TokenType::KEYWORD_ENUM)) {
			return enum_decl(state, parent);
		}
		if (expect(state, TokenType::KEYWORD_DISTINCT) 
			|| expect(state, TokenType::KEYWORD_ALIAS)
			|| expect(state, TokenType::IDENTIFIER)
			|| expect(state, TokenType::KEYWORD_FN)
			) {
			// Might or might not find these
			accept(state, TokenType::KEYWORD_DISTINCT, parent);
			accept(state, TokenType::KEYWORD_ALIAS , parent);
			return type(state, parent);
		}
		ExprResult rhs = expression_with_result(state);
		if (!rhs.success) {
			return false;
		}
		parent.children.push_back(rhs.result);
		return true;
	}

	bool function_decl(ParserState* state, ast::Node& parent) {
		if (!function_signature(state, parent)) {
			return false;
		}
		ExprResult result = block(state);
		if (!result.success) {
			return false;
		}
		parent.children.push_back(result.result);
		return true;
	}

	bool struct_decl(ParserState* state, ast::Node& parent) {
		ast::Node& node = next_as_node(state, ast::NodeType::STRUCT, &parent);

		if (expect(state, TokenType::SYM_LBRACK)) {
			if (!generic_tag(state, node)) {
				return false;
			}
		}
		if (!skip(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return false;
		}
		if (!struct_body(state, node)) {
			report_error_on_last_token(state, ErrorCode::E3020);
			return false;
		}
		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019);
			return false;
		}
		return true;
	}

	bool union_decl(ParserState* state, ast::Node& parent) {
		skip(state, TokenType::KEYWORD_UNION);
		ast::Node& node = next_as_node(state, ast::NodeType::UNION, &parent);

		if (expect(state, TokenType::SYM_LBRACK)) {
			if (!generic_tag(state, node)) {
				return false;
			}
		}
		if (!skip(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return false;
		}
		if (!union_body(state, node)) {
			report_error_on_last_token(state, ErrorCode::E3020);
			return false;
		}
		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019);
			return false;
		}
		return true;
	}

	bool enum_decl(ParserState* state, ast::Node& parent) {
		skip(state, TokenType::KEYWORD_ENUM);
		ast::Node& node = next_as_node(state, ast::NodeType::ENUM, &parent);

		if (!skip(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return false;
		}
		if (!enum_body(state, node)) {
			report_error_on_last_token(state, ErrorCode::E3020);
			return false;
		}
		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019);
			return false;
		}
		return true;
	}

	bool type(ParserState* state, ast::Node& parent) {
		
		ast::Node& node = next_as_node(state, ast::NodeType::TYPE, &parent);

		if (expect(state, TokenType::KEYWORD_MUT) || 
			expect(state, TokenType::IDENTIFIER)) {
			return simple_type(state, node);
		}
		else if (expect(state, TokenType::KEYWORD_FN)) {
			return complicated_type(state, node);
		}
		else {
			report_error_on_last_token(state, ErrorCode::E3017);
			return false;
		}
	}

	bool simple_type(ParserState* state, ast::Node& parent) {
		ast::Node* mut = nullptr;

		if (expect(state, TokenType::KEYWORD_MUT)) {
			mut = &next_as_node(state, ast::NodeType::MUTABLE);
		}

		if (!expect(state, TokenType::IDENTIFIER)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			return false;
		}
		ast::Node& type = next_as_node(state, ast::NodeType::TYPE, &parent);
		if (mut != nullptr) {
			type.children.push_back(mut);
		}

		if (expect(state, TokenType::SYM_LBRACK)) {
			const TokenType next = next_token(state).type;
			const bool is_dimension = next == TokenType::LITERAL_INTEGER
				|| next == TokenType::OPERATOR_RANGE_ARRAY
				|| next == TokenType::SYM_RBRACK
				;
			if (!is_dimension && !generic_tag(state, type)) {
				return false;
			}
		}
		while (expect(state, TokenType::SYM_LBRACK)) {
			if (!array_dimension(state, type)) {
				return false;
			}
		}
		return true;
		
	}

	bool complicated_type(ParserState* state, ast::Node& parent) {
		if (expect(state, TokenType::KEYWORD_FN)) {
			return function_signature(state, parent);
		}
		else {
			report_error_on_last_token(state, ErrorCode::E3017);
			return false;
		}
	}

	bool array_dimension(ParserState* state, ast::Node& parent) {
		ast::Node& dims = next_as_node(state, ast::NodeType::ARRAY_DIMENSION, &parent);
		if (expect(state, TokenType::LITERAL_INTEGER)) {
			accept(state, TokenType::LITERAL_INTEGER, dims);
		}
		else if (expect(state, TokenType::OPERATOR_RANGE_ARRAY)) {
			accept(state, TokenType::OPERATOR_RANGE_ARRAY, dims);
		}
		if (!accept(state, TokenType::SYM_RBRACK, dims)) {
			report_error_on_last_token(state, ErrorCode::E3012);
			return false;
		}
		return true;
	}

	bool function_signature(ParserState* state, ast::Node& parent) {
		ast::Node& node = next_as_node(state, ast::NodeType::FUNCTION, &parent);
		if (!accept(state, TokenType::KEYWORD_FN, node)) {
			report_error_on_last_token(state, ErrorCode::E3013);
			return false;
		}
		if (expect(state, TokenType::SYM_LBRACK)) {
			if (!generic_tag(state, node)) {
				return false;
			}
		}
		if (!skip(state, TokenType::SYM_LPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3014);
			return false;
		}
		if (expect(state, TokenType::IDENTIFIER)) {
			if (!function_parameter_list(state, node)) {
				return false;
			}
		}
		if (!skip(state, TokenType::SYM_RPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3015);
			return false;
		}
		if (expect(state, TokenType::SYM_ARROW_SINGLE)) {
			if (!function_output_list(state, node)) {
				return false;
			}
		}
		return true;
	}

	bool function_parameter_list(ParserState* state, ast::Node& parent) {
		ast::Node& node = next_as_node(state, ast::NodeType::LIST, &parent);

		while (accept(state, TokenType::IDENTIFIER, node)) {
			if (!skip(state, TokenType::SYM_COLON)) {
				report_error_on_last_token(state, ErrorCode::E3016);
				return false;
			}
			type(state, node);
			if (expect(state, TokenType::OPERATOR_EQUAL)) {
				skip(state, TokenType::OPERATOR_EQUAL);
				if (!default_value(state, node)) {
					return false;
				}
			}
		}
		return true;
	}

	bool function_output_list(ParserState* state, ast::Node& parent) {
		if (expect(state, TokenType::KEYWORD_VOID)) {
			accept(state, TokenType::KEYWORD_VOID, parent);
			return true;
		}
		if (expect(state, TokenType::IDENTIFIER)) {
			return simple_type(state, parent);
		}
		if (skip(state, TokenType::SYM_LPAREN)) {

			if (expect(state, TokenType::KEYWORD_FN)) {
				if (!function_signature(state, parent)) {
					return false;
				}
				if (!skip(state, TokenType::SYM_RPAREN)) {
					report_error_on_last_token(state, ErrorCode::E3015);
					return false;
				}
			}
			else {
				ast::Node& node = next_as_node(state, ast::NodeType::LIST, &parent);

				while (!expect(state, TokenType::SYM_RPAREN)) {
					if (skip(state, TokenType::SYM_LPAREN)) {
						if (!function_signature(state, node)) {
							return false;
						}
						if (!skip(state, TokenType::SYM_RPAREN)) {
							report_error_on_last_token(state, ErrorCode::E3015);
							return false;
						}
						skip(state, TokenType::SYM_COMMA);
						continue;
					}
					if (expect(state, TokenType::KEYWORD_MUT) 
						|| expect(state, TokenType::IDENTIFIER)) {
						if (!simple_type(state, node)) {
							return false;
						}
					}
					skip(state, TokenType::SYM_COMMA);
					if (accept(state, TokenType::SYM_COLON, node)) {
						if (!accept(state, TokenType::IDENTIFIER, node)) {
							report_error_on_last_token(state, ErrorCode::E3016);
							return false;
						}
						skip(state, TokenType::SYM_COMMA);
					}
				}

				if (!skip(state, TokenType::SYM_RPAREN)) {
					report_error_on_last_token(state, ErrorCode::E3015);
					return false;
				}
			}
		}
		return true;
	}

	bool default_value(ParserState* state, ast::Node& parent) {
		if (expect(state, TokenType::DIRECTIVE)) {
			accept(state, TokenType::DIRECTIVE, parent);
			return true;
		}
		else {
			return literal(state, parent);
		}
	}

	ExprResult block(ParserState* state) {
		if (!expect(state, TokenType::SYM_LBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3018);
			return ExprResult{ false };
		}

		ast::Node& block_node = next_as_node(state, ast::NodeType::BLOCK);

		while (!expect(state, TokenType::SYM_RBRACE)) {
			switch (current_token(state).type) {
			case TokenType::IDENTIFIER:
			case TokenType::KEYWORD_FALSE:
			case TokenType::KEYWORD_FOR:
			case TokenType::KEYWORD_IF:
			case TokenType::KEYWORD_LOOP:
			case TokenType::KEYWORD_TRUE:
			case TokenType::KEYWORD_WHILE:
			case TokenType::KEYWORD_WITH:
			case TokenType::LITERAL_CHAR:
			case TokenType::LITERAL_FLOATING_POINT:
			case TokenType::LITERAL_INTEGER:
			case TokenType::LITERAL_STRING:
			case TokenType::OPERATOR_BITWISE_XOR:
			case TokenType::OPERATOR_MINUS:
			case TokenType::OPERATOR_NOT:
			case TokenType::OPERATOR_PLUS:
			case TokenType::SYM_LBRACE:
			{
				if (!expression(state, block_node)) {
					return ExprResult{ false };
				}
				continue;
			}
			case TokenType::KEYWORD_RETURN:
			{
				ast::Node& ret = next_as_node(state, ast::NodeType::RETURN, &block_node);
				if (expect(state, TokenType::KEYWORD_VOID)) {
					accept(state, TokenType::KEYWORD_VOID, ret);
				}
				else {
					ExprResult expr = expression_with_result(state);
					if (!expr.success) {
						return ExprResult{ false };
					}
					ret.children.push_back(expr.result);
					while (expect(state, TokenType::SYM_COMMA)) {
						accept(state, TokenType::SYM_COMMA, ret);
						ExprResult another_expr = expression_with_result(state);
						if (!another_expr.success) {
							return ExprResult{ false };
						}
						ret.children.push_back(another_expr.result);
					}
				}
				continue;
			}
			case TokenType::KEYWORD_DEFER:
			{
				ast::Node& defer = next_as_node(state, ast::NodeType::DEFER, &block_node);
				if (!expression(state, defer)) {
					return ExprResult{ false };
				}
			}
			case TokenType::KEYWORD_BREAK:
			{
				ast::Node& break_node = next_as_node(state, ast::NodeType::BREAK, &block_node);
				if (expect(state, TokenType::LITERAL_INTEGER)) {
					next_as_node(state, ast::NodeType::LITERAL, &break_node);
				}
				else if (expect(state, TokenType::KEYWORD_ALL)) {
					next_as_node(state, ast::NodeType::KEYWORD_ALL, &break_node);
				}
				continue;
			}
			case TokenType::KEYWORD_CONTINUE:
			{
				next_as_node(state, ast::NodeType::CONTINUE, &block_node);
				continue;
			}
			case TokenType::DIRECTIVE:
			{
				ast::Node& directive = next_as_node(state, ast::NodeType::DIRECTIVE, &block_node);
				ExprResult sub_block = block(state);
				if (!sub_block.result) {
					return ExprResult{ false };
				}
				directive.children.push_back(sub_block.result);
				continue;
			}
			case TokenType::ANNOTATION:
			case TokenType::COMMENT_BLOCK:
			case TokenType::COMMENT_LINE:
			case TokenType::END_OF_FILE:
			case TokenType::INVALID:
			case TokenType::KEYWORD_ALIAS:
			case TokenType::KEYWORD_ALL:
			case TokenType::KEYWORD_AS:
			case TokenType::KEYWORD_AUTO_CAST:
			case TokenType::KEYWORD_BIT_CAST:
			case TokenType::KEYWORD_CASE:
			case TokenType::KEYWORD_CAST:
			case TokenType::KEYWORD_DISTINCT:
			case TokenType::KEYWORD_ELSE:
			case TokenType::KEYWORD_ENUM:
			case TokenType::KEYWORD_FN:
			case TokenType::KEYWORD_FROM:
			case TokenType::KEYWORD_IMPORT:
			case TokenType::KEYWORD_IN:
			case TokenType::KEYWORD_IS_NONE:
			case TokenType::KEYWORD_IS_SOME:
			case TokenType::KEYWORD_MATCH:
			case TokenType::KEYWORD_MUT:
			case TokenType::KEYWORD_NULL:
			case TokenType::KEYWORD_OR_BREAK:
			case TokenType::KEYWORD_OR_CONTINUE:
			case TokenType::KEYWORD_OR_ELSE:
			case TokenType::KEYWORD_OR_RETURN:
			case TokenType::KEYWORD_PACKAGE:
			case TokenType::KEYWORD_PUSH_CONTEXT:
			case TokenType::KEYWORD_STRUCT:
			case TokenType::KEYWORD_SWITCH:
			case TokenType::KEYWORD_UNION:
			case TokenType::KEYWORD_USING:
			case TokenType::KEYWORD_VOID:
			case TokenType::OPERATOR_AND:
			case TokenType::OPERATOR_ASSIGN:
			case TokenType::OPERATOR_ASSIGN_ADD:
			case TokenType::OPERATOR_ASSIGN_AND:
			case TokenType::OPERATOR_ASSIGN_BITWISE_AND:
			case TokenType::OPERATOR_ASSIGN_BITWISE_OR:
			case TokenType::OPERATOR_ASSIGN_BITWISE_XOR:
			case TokenType::OPERATOR_ASSIGN_DIV:
			case TokenType::OPERATOR_ASSIGN_LEFT_SHIFT:
			case TokenType::OPERATOR_ASSIGN_MOD:
			case TokenType::OPERATOR_ASSIGN_MUL:
			case TokenType::OPERATOR_ASSIGN_OR:
			case TokenType::OPERATOR_ASSIGN_REMAINDER:
			case TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC:
			case TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL:
			case TokenType::OPERATOR_ASSIGN_SUB:
			case TokenType::OPERATOR_BITWISE_OR:
			case TokenType::OPERATOR_DIVIDE:
			case TokenType::OPERATOR_DEREFERENCE:
			case TokenType::OPERATOR_EQUAL:
			case TokenType::OPERATOR_GREATER_THAN_OR_EQUAL:
			case TokenType::OPERATOR_LEFT_SHIFT:
			case TokenType::OPERATOR_LESS_THAN_OR_EQUAL:
			case TokenType::OPERATOR_MODULUS:
			case TokenType::OPERATOR_MULTIPLY:
			case TokenType::OPERATOR_NOT_EQUAL:
			case TokenType::OPERATOR_OR:
			case TokenType::OPERATOR_PIPE:
			case TokenType::OPERATOR_RANGE_ARRAY:
			case TokenType::OPERATOR_RANGE_EXCLUSIVE:
			case TokenType::OPERATOR_RANGE_INCLUSIVE:
			case TokenType::OPERATOR_REMAINDER:
			case TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC:
			case TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL:
			case TokenType::PIPE_REORDER_IDENTIFIER:
			case TokenType::SYM_AMPERSAND:
			case TokenType::SYM_ARROW_DOUBLE:
			case TokenType::SYM_ARROW_SINGLE:
			case TokenType::SYM_COLON:
			case TokenType::SYM_COMMA:
			case TokenType::SYM_DOT:
			case TokenType::SYM_ELLIPSIS:
			case TokenType::SYM_GT:
			case TokenType::SYM_LBRACK:
			case TokenType::SYM_LPAREN:
			case TokenType::SYM_LT:
			case TokenType::SYM_QUESTION:
			case TokenType::SYM_RBRACE:
			case TokenType::SYM_RBRACK:
			case TokenType::SYM_RPAREN:
			case TokenType::SYM_UNDERSCORE:
			case TokenType::SYM_UNINITIALIZED:
				report_error_on_last_token(state, ErrorCode::E3017);
				return ExprResult{ false };
			}
		}

		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019);
			return ExprResult{ false };
		}
		return ExprResult{ true, &block_node };
	}

	bool expression(ParserState* state, ast::Node& parent) {

		switch (current_token(state).type) {
		case TokenType::LITERAL_CHAR:
		case TokenType::LITERAL_FLOATING_POINT:
		case TokenType::LITERAL_INTEGER:
		case TokenType::LITERAL_STRING:
		case TokenType::OPERATOR_PLUS:
		case TokenType::OPERATOR_MINUS:
		case TokenType::OPERATOR_BITWISE_XOR:
		case TokenType::KEYWORD_IF:
		case TokenType::OPERATOR_NOT:
		case TokenType::KEYWORD_TRUE:
		case TokenType::KEYWORD_FALSE:
		case TokenType::SYM_LBRACE:
		{
			ExprResult result = expression_with_result(state);
			if (!result.success) {
				return false;
			}
			parent.children.push_back(result.result);
			return true;
		}
		case TokenType::KEYWORD_FOR:
		case TokenType::KEYWORD_WITH:
		case TokenType::KEYWORD_LOOP:
			return expression_without_result(state, parent);
		case TokenType::IDENTIFIER:
			switch (next_token(state).type) {
			//Assignment
			case TokenType::OPERATOR_ASSIGN:
			case TokenType::OPERATOR_ASSIGN_ADD:
			case TokenType::OPERATOR_ASSIGN_AND:
			case TokenType::OPERATOR_ASSIGN_BITWISE_AND:
			case TokenType::OPERATOR_ASSIGN_BITWISE_OR:
			case TokenType::OPERATOR_ASSIGN_BITWISE_XOR:
			case TokenType::OPERATOR_ASSIGN_DIV:
			case TokenType::OPERATOR_ASSIGN_LEFT_SHIFT:
			case TokenType::OPERATOR_ASSIGN_MOD:
			case TokenType::OPERATOR_ASSIGN_MUL:
			case TokenType::OPERATOR_ASSIGN_OR:
			case TokenType::OPERATOR_ASSIGN_REMAINDER:
			case TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC:
			case TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL:
			case TokenType::OPERATOR_ASSIGN_SUB:
			case TokenType::SYM_COMMA:
			case TokenType::SYM_LBRACK:
			// Declaration
			case TokenType::SYM_COLON:
				return expression_without_result(state, parent);
			// Probable followups to an identifier in an expression
			case TokenType::DIRECTIVE:
			case TokenType::KEYWORD_AUTO_CAST:
			case TokenType::KEYWORD_BIT_CAST:
			case TokenType::KEYWORD_CAST:
			case TokenType::KEYWORD_IS_NONE:
			case TokenType::KEYWORD_IS_SOME:
			case TokenType::KEYWORD_OR_BREAK:
			case TokenType::KEYWORD_OR_CONTINUE:
			case TokenType::KEYWORD_OR_ELSE:
			case TokenType::KEYWORD_OR_RETURN:
			case TokenType::OPERATOR_AND:
			case TokenType::OPERATOR_BITWISE_OR:
			case TokenType::OPERATOR_BITWISE_XOR:
			case TokenType::OPERATOR_DIVIDE:
			case TokenType::OPERATOR_DEREFERENCE:
			case TokenType::OPERATOR_EQUAL:
			case TokenType::OPERATOR_GREATER_THAN_OR_EQUAL:
			case TokenType::OPERATOR_LEFT_SHIFT:
			case TokenType::OPERATOR_LESS_THAN_OR_EQUAL:
			case TokenType::OPERATOR_MINUS:
			case TokenType::OPERATOR_MODULUS:
			case TokenType::OPERATOR_MULTIPLY:
			case TokenType::OPERATOR_NOT:
			case TokenType::OPERATOR_NOT_EQUAL:
			case TokenType::OPERATOR_OR:
			case TokenType::OPERATOR_PIPE:
			case TokenType::OPERATOR_PLUS:
			case TokenType::OPERATOR_RANGE_ARRAY:
			case TokenType::OPERATOR_RANGE_EXCLUSIVE:
			case TokenType::OPERATOR_RANGE_INCLUSIVE:
			case TokenType::OPERATOR_REMAINDER:
			case TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC:
			case TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL:
			case TokenType::SYM_DOT:
			case TokenType::SYM_GT:
			case TokenType::SYM_LT:
			case TokenType::SYM_LPAREN:
			{
				ExprResult result = expression_with_result(state);
				if (!result.success) {
					return false;
				}
				parent.children.push_back(result.result);
				return true;
			}
			// Definitely not valid right after an identifier
			case TokenType::ANNOTATION:
			case TokenType::COMMENT_BLOCK:
			case TokenType::COMMENT_LINE:
			case TokenType::END_OF_FILE:
			case TokenType::IDENTIFIER:
			case TokenType::INVALID:
			case TokenType::KEYWORD_ALIAS:
			case TokenType::KEYWORD_ALL:
			case TokenType::KEYWORD_AS:
			case TokenType::KEYWORD_BREAK:
			case TokenType::KEYWORD_CASE:
			case TokenType::KEYWORD_CONTINUE:
			case TokenType::KEYWORD_DEFER:
			case TokenType::KEYWORD_DISTINCT:
			case TokenType::KEYWORD_ELSE:
			case TokenType::KEYWORD_ENUM:
			case TokenType::KEYWORD_FALSE:
			case TokenType::KEYWORD_FN:
			case TokenType::KEYWORD_FOR:
			case TokenType::KEYWORD_FROM:
			case TokenType::KEYWORD_IF:
			case TokenType::KEYWORD_IMPORT:
			case TokenType::KEYWORD_IN:
			case TokenType::KEYWORD_LOOP:
			case TokenType::KEYWORD_MATCH:
			case TokenType::KEYWORD_MUT:
			case TokenType::KEYWORD_NULL:
			case TokenType::KEYWORD_PACKAGE:
			case TokenType::KEYWORD_PUSH_CONTEXT:
			case TokenType::KEYWORD_RETURN:
			case TokenType::KEYWORD_STRUCT:
			case TokenType::KEYWORD_SWITCH:
			case TokenType::KEYWORD_TRUE:
			case TokenType::KEYWORD_UNION:
			case TokenType::KEYWORD_USING:
			case TokenType::KEYWORD_VOID:
			case TokenType::KEYWORD_WHILE:
			case TokenType::KEYWORD_WITH:
			case TokenType::LITERAL_CHAR:
			case TokenType::LITERAL_FLOATING_POINT:
			case TokenType::LITERAL_INTEGER:
			case TokenType::LITERAL_STRING:
			case TokenType::PIPE_REORDER_IDENTIFIER:
			case TokenType::SYM_AMPERSAND:
			case TokenType::SYM_ARROW_DOUBLE:
			case TokenType::SYM_ARROW_SINGLE:
			case TokenType::SYM_ELLIPSIS:
			case TokenType::SYM_LBRACE:
			case TokenType::SYM_QUESTION:
			case TokenType::SYM_RBRACE:
			case TokenType::SYM_RBRACK:
			case TokenType::SYM_RPAREN:
			case TokenType::SYM_UNDERSCORE:
			case TokenType::SYM_UNINITIALIZED:
				report_error_on_last_token(state, ErrorCode::E3017);
				return false;
			}
			break;
		case TokenType::ANNOTATION:
		case TokenType::COMMENT_BLOCK:
		case TokenType::COMMENT_LINE:
		case TokenType::DIRECTIVE:
		case TokenType::END_OF_FILE:
		case TokenType::INVALID:
		case TokenType::KEYWORD_ALIAS:
		case TokenType::KEYWORD_ALL:
		case TokenType::KEYWORD_AS:
		case TokenType::KEYWORD_AUTO_CAST:
		case TokenType::KEYWORD_BIT_CAST:
		case TokenType::KEYWORD_BREAK:
		case TokenType::KEYWORD_CASE:
		case TokenType::KEYWORD_CAST:
		case TokenType::KEYWORD_CONTINUE:
		case TokenType::KEYWORD_DEFER:
		case TokenType::KEYWORD_DISTINCT:
		case TokenType::KEYWORD_ELSE:
		case TokenType::KEYWORD_ENUM:
		case TokenType::KEYWORD_FN:
		case TokenType::KEYWORD_FROM:
		case TokenType::KEYWORD_IMPORT:
		case TokenType::KEYWORD_IN:
		case TokenType::KEYWORD_IS_NONE:
		case TokenType::KEYWORD_IS_SOME:
		case TokenType::KEYWORD_MATCH:
		case TokenType::KEYWORD_MUT:
		case TokenType::KEYWORD_NULL:
		case TokenType::KEYWORD_OR_BREAK:
		case TokenType::KEYWORD_OR_CONTINUE:
		case TokenType::KEYWORD_OR_ELSE:
		case TokenType::KEYWORD_OR_RETURN:
		case TokenType::KEYWORD_PACKAGE:
		case TokenType::KEYWORD_PUSH_CONTEXT:
		case TokenType::KEYWORD_RETURN:
		case TokenType::KEYWORD_STRUCT:
		case TokenType::KEYWORD_SWITCH:
		case TokenType::KEYWORD_UNION:
		case TokenType::KEYWORD_USING:
		case TokenType::KEYWORD_VOID:
		case TokenType::KEYWORD_WHILE:
		case TokenType::OPERATOR_AND:
		case TokenType::OPERATOR_ASSIGN:
		case TokenType::OPERATOR_ASSIGN_ADD:
		case TokenType::OPERATOR_ASSIGN_AND:
		case TokenType::OPERATOR_ASSIGN_BITWISE_AND:
		case TokenType::OPERATOR_ASSIGN_BITWISE_OR:
		case TokenType::OPERATOR_ASSIGN_BITWISE_XOR:
		case TokenType::OPERATOR_ASSIGN_DIV:
		case TokenType::OPERATOR_ASSIGN_LEFT_SHIFT:
		case TokenType::OPERATOR_ASSIGN_MOD:
		case TokenType::OPERATOR_ASSIGN_MUL:
		case TokenType::OPERATOR_ASSIGN_OR:
		case TokenType::OPERATOR_ASSIGN_REMAINDER:
		case TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC:
		case TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL:
		case TokenType::OPERATOR_ASSIGN_SUB:
		case TokenType::OPERATOR_BITWISE_OR:
		case TokenType::OPERATOR_DIVIDE:
		case TokenType::OPERATOR_DEREFERENCE:
		case TokenType::OPERATOR_EQUAL:
		case TokenType::OPERATOR_GREATER_THAN_OR_EQUAL:
		case TokenType::OPERATOR_LEFT_SHIFT:
		case TokenType::OPERATOR_LESS_THAN_OR_EQUAL:
		case TokenType::OPERATOR_MODULUS:
		case TokenType::OPERATOR_MULTIPLY:
		case TokenType::OPERATOR_NOT_EQUAL:
		case TokenType::OPERATOR_OR:
		case TokenType::OPERATOR_PIPE:
		case TokenType::OPERATOR_RANGE_ARRAY:
		case TokenType::OPERATOR_RANGE_EXCLUSIVE:
		case TokenType::OPERATOR_RANGE_INCLUSIVE:
		case TokenType::OPERATOR_REMAINDER:
		case TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC:
		case TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL:
		case TokenType::PIPE_REORDER_IDENTIFIER:
		case TokenType::SYM_AMPERSAND:
		case TokenType::SYM_ARROW_DOUBLE:
		case TokenType::SYM_ARROW_SINGLE:
		case TokenType::SYM_COLON:
		case TokenType::SYM_COMMA:
		case TokenType::SYM_DOT:
		case TokenType::SYM_ELLIPSIS:
		case TokenType::SYM_GT:
		case TokenType::SYM_LBRACK:
		case TokenType::SYM_LPAREN:
		case TokenType::SYM_LT:
		case TokenType::SYM_QUESTION:
		case TokenType::SYM_RBRACE:
		case TokenType::SYM_RBRACK:
		case TokenType::SYM_RPAREN:
		case TokenType::SYM_UNDERSCORE:
		case TokenType::SYM_UNINITIALIZED:
			report_error_on_last_token(state, ErrorCode::E3017);
			return false;
		}
		LOG_ERROR("We should have parsed an expression");
		return false;
	}
	
	ExprResult expression_with_result(ParserState* state) {
		if (expect(state, TokenType::SYM_LBRACE)) {
			return block(state);
		}
		if (expect(state, TokenType::KEYWORD_MATCH)) {
			return match_expression(state);
		}
		if (expect(state, TokenType::IDENTIFIER) &&
			TokenType::SYM_DOT == next_token(state, 1).type
			&& TokenType::SYM_LBRACE == next_token(state, 2).type
			) {
			return struct_literal(state);
		}
		return expr_lvl_1(state);
	}

	bool expression_without_result(ParserState* state, ast::Node& parent) {
		const TokenType current = current_token(state).type;
		if (current == TokenType::KEYWORD_FOR) {
			return for_loop(state, parent);
		}
		if (current == TokenType::KEYWORD_WITH
			|| current == TokenType::KEYWORD_LOOP) {
			return loop(state, parent);
		}
		if (current == TokenType::KEYWORD_PUSH_CONTEXT) {
			return push_context(state, parent);
		}
		if (current == TokenType::KEYWORD_SWITCH) {
			return switch_statement(state, parent);
		}
		if (current == TokenType::IDENTIFIER) {
			const TokenType next_type = next_token(state).type;

			if (next_type == TokenType::SYM_COLON) {
				if (!declaration(state, parent)) {
					return false;
				}
				if (expect(state, TokenType::SYM_COLON)) {
					return const_definition_rhs(state, parent);
				}
				if (expect(state, TokenType::OPERATOR_ASSIGN)) {
					return mut_definition_rhs(state, parent);
				}
			}
			else if (next_type == TokenType::OPERATOR_ASSIGN
				|| next_type == TokenType::OPERATOR_ASSIGN_ADD
				|| next_type == TokenType::OPERATOR_ASSIGN_AND
				|| next_type == TokenType::OPERATOR_ASSIGN_BITWISE_AND
				|| next_type == TokenType::OPERATOR_ASSIGN_BITWISE_OR
				|| next_type == TokenType::OPERATOR_ASSIGN_BITWISE_XOR
				|| next_type == TokenType::OPERATOR_ASSIGN_DIV
				|| next_type == TokenType::OPERATOR_ASSIGN_LEFT_SHIFT
				|| next_type == TokenType::OPERATOR_ASSIGN_MOD
				|| next_type == TokenType::OPERATOR_ASSIGN_MUL
				|| next_type == TokenType::OPERATOR_ASSIGN_OR
				|| next_type == TokenType::OPERATOR_ASSIGN_REMAINDER
				|| next_type == TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC
				|| next_type == TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL
				|| next_type == TokenType::OPERATOR_ASSIGN_SUB
				) {
				return assignment(state, parent);
			}
		}
		return false;
	}

	bool assignment(ParserState* state, ast::Node& parent) {
		ExprResult loc_result = location(state);
		if (!loc_result.success) {
			return false;
		}
		ast::Node* loc = loc_result.result;

		ast::Node& assign = next_as_node(state, ast::NodeType::BINARY_OPERATOR, &parent);

		assign.children.push_back(loc);

		ExprResult expr = expression_with_result(state);
		if (!expr.success) {
			return false;
		}
		assign.children.push_back(expr.result);

		return true;
	}

	bool literal(ParserState* state, ast::Node& parent) {
		const TokenType current = current_token(state).type;
		if (current == TokenType::LITERAL_CHAR
			|| current == TokenType::LITERAL_FLOATING_POINT
			|| current == TokenType::LITERAL_INTEGER
			|| current == TokenType::LITERAL_STRING
			|| current == TokenType::KEYWORD_TRUE
			|| current == TokenType::KEYWORD_FALSE
			|| current == TokenType::KEYWORD_NULL
			) {
			return accept(state, current, parent);
		}
		
		return false;
	}

	bool struct_body(ParserState* state, ast::Node& parent) {
		const TokenType current = current_token(state).type;

		while (current == TokenType::IDENTIFIER
			|| current == TokenType::KEYWORD_USING
			|| current == TokenType::SYM_UNDERSCORE) {
			
			if (current == TokenType::IDENTIFIER) {
				if (!any_definition(state, parent)) {
					return false;
				}

			}
			else if (current == TokenType::KEYWORD_USING) {
				ast::Node& using_node = next_as_node(state, ast::NodeType::USING, &parent);
				if (!expect(state, TokenType::IDENTIFIER)) {
					report_error_on_last_token(state, ErrorCode::E3009);
					return false;
				}
				next_as_node(state, ast::NodeType::IDENTIFIER, &using_node);
			}
			else if (current == TokenType::SYM_UNDERSCORE) {
				// Would just do else, but might need to add more to the loop
				ast::Node& underscore = next_as_node(state, ast::NodeType::IDENTIFIER);

				if (!expect(state, TokenType::SYM_COLON)) {
					report_error_on_last_token(state, ErrorCode::E3010);
					return false;
				}
				ast::Node& colon = next_as_node(state, ast::NodeType::DEFINITION, &parent);
				colon.children.push_back(&underscore);

				if (!expect(state, TokenType::KEYWORD_STRUCT)) {
					report_error_on_last_token(state, ErrorCode::E3023);
					return false;
				}
				if (!struct_decl(state, colon)) {
					return false;
				}
			}

			skip(state, TokenType::SYM_COMMA);
		}
		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019);
			return false;
		}
		return true;
	}

	bool union_body(ParserState* state, ast::Node& parent) {
		while (accept(state, TokenType::IDENTIFIER, parent)) {
			//NOTE(ches) this is all one entry in the union
			if (accept(state, TokenType::SYM_LPAREN, parent)) {
				//NOTE(ches) will simply exit when we hit the rparen
				while (accept(state, TokenType::IDENTIFIER, parent)) {
					if (!accept(state, TokenType::SYM_COMMA, parent)) {
						if (!expect(state, TokenType::SYM_RPAREN)) {
							/*
							 * NOTE(ches) if we have something besides comma,
							 * then it had better be the closing parenthesis
							 */
							report_error_on_last_token(state, ErrorCode::E3009);
							return false;
						}
					}
				}
				if (!accept(state, TokenType::SYM_RPAREN, parent)) {
					report_error_on_last_token(state, ErrorCode::E3015);
					return false;
				}
			}
			
			skip(state, TokenType::SYM_COMMA);
		}
		return true;
	}

	bool enum_body(ParserState* state, ast::Node& parent) {
		while (accept(state, TokenType::IDENTIFIER, parent)) {
			skip(state, TokenType::SYM_COMMA);
		}
		return true;
	}

	bool generic_tag(ParserState* state, ast::Node& parent) {
		ast::Node& node = next_as_node(state, ast::NodeType::GENERIC_TAG, &parent);
		if (!skip(state, TokenType::SYM_LBRACK)) {
			report_error_on_last_token(state, ErrorCode::E3011);
			return false;
		}

		while (!expect(state, TokenType::SYM_RBRACK)) {
			if (!type(state, node)) {
				return false;
			}
			if (expect(state, TokenType::SYM_COMMA)) {
				skip(state, TokenType::SYM_COMMA);
			}
		}
		if (!skip(state, TokenType::SYM_RBRACK)) {
			report_error_on_last_token(state, ErrorCode::E3012);
			return false;
		}
		return true;
	}

	ExprResult expr_lvl_1(ParserState* state) {
		if (expect(state, TokenType::KEYWORD_IF)) {
			return if_expression(state);
		}

		ExprResult lhs = expr_lvl_2(state);

		if (!lhs.success) {
			return ExprResult{ false };
		}

		if (expect(state, TokenType::KEYWORD_IS_NONE)) {
			ast::Node& result = next_as_node(state, ast::NodeType::UNARY_OPERATOR);
			result.children.push_back(lhs.result);
			accept(state, TokenType::KEYWORD_IS_NONE, result);
			return ExprResult{ true, &result };
		}
		else if (expect(state, TokenType::KEYWORD_IS_SOME)) {
			ast::Node& result = next_as_node(state, ast::NodeType::UNARY_OPERATOR);
			result.children.push_back(lhs.result);
			accept(state, TokenType::KEYWORD_IS_SOME, result);
			return ExprResult{ true, &result };
		}
		else if (expect(state, TokenType::KEYWORD_OR_BREAK)) {
			ast::Node& result = next_as_node(state, ast::NodeType::UNARY_OPERATOR);
			result.children.push_back(lhs.result);
			accept(state, TokenType::KEYWORD_OR_BREAK, result);
			return ExprResult{ true, &result };
		}
		else if (expect(state, TokenType::KEYWORD_OR_CONTINUE)) {
			ast::Node& result = next_as_node(state, ast::NodeType::UNARY_OPERATOR);
			result.children.push_back(lhs.result);
			accept(state, TokenType::KEYWORD_OR_CONTINUE, result);
			return ExprResult{ true, &result };
		}
		else if (expect(state, TokenType::KEYWORD_OR_ELSE)) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			accept(state, TokenType::KEYWORD_OR_ELSE, result);

			ExprResult rhs = expression_with_result(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}
		else if (expect(state, TokenType::KEYWORD_OR_RETURN)) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			accept(state, TokenType::KEYWORD_OR_RETURN, result);

			ExprResult rhs = expression_with_result(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_2(ParserState* state) {
		ExprResult lhs = expr_lvl_3(state);

		if (!lhs.success) {
			return { false };
		}

		if (expect(state, TokenType::OPERATOR_RANGE_EXCLUSIVE)) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);
			
			accept(state, TokenType::OPERATOR_RANGE_EXCLUSIVE, result);

			ExprResult rhs = expr_lvl_3(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}
		else if (expect(state, TokenType::OPERATOR_RANGE_INCLUSIVE)) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			accept(state, TokenType::OPERATOR_RANGE_INCLUSIVE, result);

			ExprResult rhs = expr_lvl_3(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_3(ParserState* state) {
		ExprResult lhs = expr_lvl_4(state);

		if (!lhs.success) {
			return { false };
		}

		if (expect(state, TokenType::OPERATOR_OR)) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			accept(state, TokenType::OPERATOR_OR, result);

			ExprResult rhs = expr_lvl_3(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_4(ParserState* state) {
		ExprResult lhs = expr_lvl_5(state);

		if (!lhs.success) {
			return { false };
		}

		if (expect(state, TokenType::OPERATOR_AND)) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			accept(state, TokenType::OPERATOR_AND, result);

			ExprResult rhs = expr_lvl_4(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_5(ParserState* state) {
		ExprResult lhs = expr_lvl_6(state);

		if (!lhs.success) {
			return { false };
		}

		const TokenType current = current_token(state).type;
		if (current == TokenType::OPERATOR_EQUAL
			|| current == TokenType::OPERATOR_NOT_EQUAL
			|| current == TokenType::SYM_LT
			|| current == TokenType::SYM_GT
			|| current == TokenType::OPERATOR_LESS_THAN_OR_EQUAL
			|| current == TokenType::OPERATOR_GREATER_THAN_OR_EQUAL
			) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			ExprResult rhs = expr_lvl_6(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_6(ParserState* state) {
		ExprResult lhs = expr_lvl_7(state);

		if (!lhs.success) {
			return { false };
		}

		const TokenType current = current_token(state).type;
		if (current == TokenType::OPERATOR_PLUS
			|| current == TokenType::OPERATOR_MINUS
			|| current == TokenType::OPERATOR_BITWISE_OR
			|| current == TokenType::OPERATOR_BITWISE_XOR
			) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			ExprResult rhs = expr_lvl_6(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_7(ParserState* state) {
		ExprResult lhs = expr_lvl_8(state);

		if (!lhs.success) {
			return { false };
		}

		const TokenType current = current_token(state).type;
		if (current == TokenType::OPERATOR_MULTIPLY
			|| current == TokenType::OPERATOR_DIVIDE
			|| current == TokenType::OPERATOR_MODULUS
			|| current == TokenType::OPERATOR_REMAINDER
			|| current == TokenType::SYM_AMPERSAND
			|| current == TokenType::OPERATOR_LEFT_SHIFT
			|| current == TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC
			|| current == TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL
			) {
			ast::Node& result = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
			result.children.push_back(lhs.result);

			ExprResult rhs = expr_lvl_7(state);
			if (!rhs.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(rhs.result);
			return ExprResult{ true, &result };
		}

		return lhs;
	}

	ExprResult expr_lvl_8(ParserState* state) {
		if (expect(state, TokenType::SYM_LPAREN)) {
			ast::Node& result = next_as_node(state, ast::NodeType::PAREN_GROUP);
			
			ExprResult child = expression_with_result(state);

			if (!child.success) {
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			result.children.push_back(child.result);

			if (!skip(state, TokenType::SYM_RPAREN)) {
				report_error_on_last_token(state, ErrorCode::E3015);
				delete_node(state->node_alloc, &result);
				return ExprResult{ false };
			}
			return ExprResult{ true, &result };
		}
		else {
			return expr_lvl_9(state);
		}
	}

	ExprResult expr_lvl_9(ParserState* state) {
		ast::Node* result = nullptr;

		const TokenType current = current_token(state).type;
		if (current == TokenType::OPERATOR_PLUS
			|| current == TokenType::OPERATOR_MINUS
			|| current == TokenType::OPERATOR_BITWISE_XOR
			|| current == TokenType::OPERATOR_NOT) {
			result = &next_as_node(state, ast::NodeType::UNARY_OPERATOR);
		}
		
		ExprResult expr = expr_lvl_10(state);
		
		if (!expr.success) {

			if (result != nullptr) {
				delete_node(state->node_alloc, result);
				result = nullptr;
			}
			return ExprResult{ false };
		}

		if (result == nullptr) {
			result = expr.result;
		}
		else {
			result->children.push_back(expr.result);
		}
		return ExprResult{ true, result };
	}

	ExprResult expr_lvl_10(ParserState* state) {
		const TokenType current = current_token(state).type;

		if (current == TokenType::KEYWORD_CAST
			|| current == TokenType::KEYWORD_BIT_CAST
			|| current == TokenType::KEYWORD_AUTO_CAST) {
			return cast_expression(state);
		}
		if (current == TokenType::SYM_DOT) {
			return enum_shorthand(state);
		}
		if (current == TokenType::DIRECTIVE) {
			ast::Node& result = next_as_node(state, ast::NodeType::LEAF);
			return ExprResult{ true , &result };
		}
		
		if (current == TokenType::LITERAL_CHAR
			|| current == TokenType::LITERAL_FLOATING_POINT
			|| current == TokenType::LITERAL_INTEGER
			|| current == TokenType::LITERAL_STRING
			|| current == TokenType::KEYWORD_TRUE
			|| current == TokenType::KEYWORD_FALSE
			|| current == TokenType::KEYWORD_NULL)
		{
			ast::Node& result = next_as_node(state, ast::NodeType::LEAF);
			return ExprResult{ true , &result };
		}
		if (current == TokenType::IDENTIFIER || current == TokenType::SYM_AMPERSAND) {

			ExprResult loc = location(state);

			if (!loc.success) {
				return ExprResult{ false };
			}

			ast::Node* current_parent = loc.result;
			while (expect(state, TokenType::OPERATOR_PIPE)) {
				ast::Node& chain = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
				chain.children.push_back(current_parent);

				if (!function_call(state, chain)) {
					report_error_on_last_token(state, ErrorCode::E3009);
					delete_node(state->node_alloc, &chain);
					return ExprResult{ false };
				}

				current_parent = &chain;
			}

			return ExprResult{ true , current_parent };
		}

		return ExprResult{ false };
	}

	ExprResult location(ParserState* state) {
		// We are relying on nullptr being ignored in next_as_node
		ast::Node* root = nullptr;
		ast::Node* latest = nullptr;

		while (expect(state, TokenType::SYM_AMPERSAND)) {
			latest = &next_as_node(state, ast::NodeType::UNARY_OPERATOR, latest);

			if (root == nullptr) {
				root = latest;
			}
		}

		ast::Node& identifier = next_as_node(state, ast::NodeType::IDENTIFIER, latest);
		if (root == nullptr) {
			root = &identifier;
		}

		while (expect(state, TokenType::SYM_LBRACK)
			|| expect(state, TokenType::SYM_DOT)
			|| expect(state, TokenType::SYM_LPAREN)) {

			if (accept(state, TokenType::SYM_LBRACK, identifier)) {

				if (!expect(state, TokenType::SYM_RBRACK)) {
					ExprResult index = expression_with_result(state);
					if (!index.success) {
						delete_node(state->node_alloc, &identifier);
						return ExprResult{ false };
					}
					identifier.children.push_back(index.result);
				}
				if (!accept(state, TokenType::SYM_RBRACK, identifier)) {
					report_error_on_last_token(state, ErrorCode::E3021);
					delete_node(state->node_alloc, &identifier);
					return ExprResult{ false };
				}
				continue;
			}
			if (accept(state, TokenType::SYM_DOT, identifier)) {
				if (!accept(state, TokenType::IDENTIFIER, identifier)) {
					report_error_on_last_token(state, ErrorCode::E3009);
					delete_node(state->node_alloc, &identifier);
					return ExprResult{ false };
				}
				continue;
			}
			if (accept(state, TokenType::SYM_LPAREN, identifier)) {
				if (!expect(state, TokenType::IDENTIFIER)) {
					if (!function_call_input_list(state, identifier)) {
						report_error_on_last_token(state, ErrorCode::E3021);
						delete_node(state->node_alloc, &identifier);
						return ExprResult{ false };
					}
				}
				if (!accept(state, TokenType::SYM_RPAREN, identifier)) {
					report_error_on_last_token(state, ErrorCode::E3021);
					delete_node(state->node_alloc, &identifier);
					return ExprResult{ false };
				}
			}
		}
		return ExprResult{ true, root };
	}

	ExprResult struct_literal(ParserState* state) {
		//NOTE(ches) assumes we already checked for identifier, dot, lbrace
		ast::Node& id = next_as_node(state, ast::NodeType::STRUCT_LITERAL);
		skip(state, TokenType::SYM_DOT);
		ast::Node& braces = next_as_node(state, ast::NodeType::LIST, &id);

		if (skip(state, TokenType::SYM_RBRACE)) {
			return ExprResult{ true, &id };
		}
		
		if (TokenType::IDENTIFIER == current_token(state).type
			&& TokenType::OPERATOR_ASSIGN == next_token(state).type) {
			//NOTE(ches) named inputs	
			while (expect(state, TokenType::IDENTIFIER)) {
				ast::Node& target = next_as_node(state, ast::NodeType::IDENTIFIER);

				if (!expect(state, TokenType::OPERATOR_ASSIGN)) {
					report_error_on_last_token(state, ErrorCode::E3024);
					delete_node(state->node_alloc, &id);
					return ExprResult{ false };
				}
				ast::Node& assign = next_as_node(state, ast::NodeType::BINARY_OPERATOR);
				assign.children.push_back(&target);

				ExprResult value = expression_with_result(state);
				if (!value.result) {
					delete_node(state->node_alloc, &id);
					return ExprResult{ false };
				}
				assign.children.push_back(value.result);
				braces.children.push_back(&assign);
				if (!skip(state, TokenType::SYM_COMMA) 
					&& !expect(state, TokenType::SYM_RBRACE)) {
					report_error_on_last_token(state, ErrorCode::E3022);
					delete_node(state->node_alloc, &id);
					return ExprResult{ false };
				}
			}
		}
		else {
			//NOTE(ches) positional inputs
			while (!expect(state, TokenType::SYM_RBRACE)) {
				ExprResult value = expression_with_result(state);
				if (!value.result) {
					delete_node(state->node_alloc, &id);
					return ExprResult{ false };
				}
				braces.children.push_back(value.result);
				if (!skip(state, TokenType::SYM_COMMA)
					&& !expect(state, TokenType::SYM_RBRACE)) {
					report_error_on_last_token(state, ErrorCode::E3022);
					delete_node(state->node_alloc, &id);
					return ExprResult{ false };
				}
			}
		}

		if (!skip(state, TokenType::SYM_RBRACE)) {
			report_error_on_last_token(state, ErrorCode::E3019);
			delete_node(state->node_alloc, &id);
			return ExprResult{ false };
		}

		return ExprResult{ true, &id };
	}

	bool function_call(ParserState* state, ast::Node& parent) {
		if (!expect(state, TokenType::IDENTIFIER)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			return false;
		}
		
		next_as_node(state, ast::NodeType::IDENTIFIER, &parent);

		if (!expect(state, TokenType::SYM_LPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3014);
			return false;
		}

		ast::Node& parens = next_as_node(state, ast::NodeType::PAREN_GROUP, &parent);

		if (!function_call_input_list(state, parens)) {
			return false;
		}

		if (!skip(state, TokenType::SYM_RPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3015);
			return false;
		}

		return true;
	}

	bool function_call_input_list(ParserState* state, ast::Node& parent) {
		while (!expect(state, TokenType::SYM_RPAREN)) {
			const TokenType current_token_type = current_token(state).type;

			if (current_token_type == TokenType::IDENTIFIER) {
				const TokenType next_token_type = next_token(state).type;

				if (next_token_type == TokenType::OPERATOR_ASSIGN) {
					accept(state, TokenType::IDENTIFIER, parent);
					accept(state, TokenType::OPERATOR_ASSIGN, parent);
				}
			}

			if (current_token_type == TokenType::SYM_UNDERSCORE
				|| current_token_type == TokenType::PIPE_REORDER_IDENTIFIER
				|| current_token_type == TokenType::DIRECTIVE
				) {
				accept(state, current_token_type, parent);
			}
			else {
				ExprResult expr = expression_with_result(state);

				if (!expr.success) {
					delete_node(state->node_alloc, expr.result);
					return false;
				}
				parent.children.push_back(expr.result);
			}
			
			if (!accept(state, TokenType::SYM_COMMA, parent)) {
				if (!expect(state, TokenType::SYM_RPAREN)) {
					report_error_on_last_token(state, ErrorCode::E3022);
					return false;
				}
			}
		}

		return true;
	}
	
	ExprResult cast_expression(ParserState* state) {
		const TokenType current_token_type = current_token(state).type;
		
		ast::Node* root;

		if (current_token_type == TokenType::KEYWORD_CAST
			|| current_token_type == TokenType::KEYWORD_BIT_CAST) {
			root = &next_as_node(state, ast::NodeType::CAST);

			if (!skip(state, TokenType::SYM_LBRACK)) {
				report_error_on_last_token(state, ErrorCode::E3011);
				delete_node(state->node_alloc, root);
				return ExprResult{ false };
			}
			if (!type(state, *root)) {
				delete_node(state->node_alloc, root);
				return ExprResult{ false };
			}
			if (!skip(state, TokenType::SYM_RBRACK)) {
				report_error_on_last_token(state, ErrorCode::E3012);
				delete_node(state->node_alloc, root);
				return ExprResult{ false };
			}
		}
		else {
			if (current_token_type != TokenType::KEYWORD_AUTO_CAST) {
				LOG_ERROR("Invalid state for casts");
				return ExprResult{ false };
			}
			root = &next_as_node(state, ast::NodeType::CAST);
		}
		if (!skip(state, TokenType::SYM_LPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3014);
			delete_node(state->node_alloc, root);
			return ExprResult{ false };
		}

		ExprResult expr = expression_with_result(state);

		if (!expr.success) {
			delete_node(state->node_alloc, root);
			return ExprResult{ false };
		}
		else {
			root->children.push_back(expr.result);
		}

		if (!skip(state, TokenType::SYM_RPAREN)) {
			report_error_on_last_token(state, ErrorCode::E3015);
			delete_node(state->node_alloc, root);
			return ExprResult{ false };
		}
		return ExprResult{ true, root };
	}

	ExprResult if_expression(ParserState* state) {
		if (!expect(state, TokenType::KEYWORD_IF)) {
			return ExprResult{ false };
		}
		ast::Node& if_node = next_as_node(state, ast::NodeType::IF);

		ExprResult condition = expression_with_result(state);
		if (!condition.success) {
			delete_node(state->node_alloc, &if_node);
			return ExprResult{ false };
		}
		if_node.children.push_back(condition.result);

		ExprResult block_node = block(state);
		if (!block_node.success) {
			delete_node(state->node_alloc, &if_node);
			return ExprResult{ false };
		}
		if_node.children.push_back(block_node.result);

		while (expect(state, TokenType::KEYWORD_ELSE)) {
			ast::Node& else_node = next_as_node(state, ast::NodeType::ELSE, &if_node);
			if (expect(state, TokenType::KEYWORD_IF)) {
				next_as_node(state, ast::NodeType::IF, &else_node);

				ExprResult else_block_node = block(state);
				if (!else_block_node.success) {
					delete_node(state->node_alloc, &if_node);
					return ExprResult{ false };
				}
				else_node.children.push_back(else_block_node.result);
			}
			else {
				// Final else block
				ExprResult else_block_node = block(state);
				if (!else_block_node.success) {
					delete_node(state->node_alloc, &if_node);
					return ExprResult{ false };
				}
				else_node.children.push_back(else_block_node.result);
				break;
			}
		}
		return ExprResult{ true, &if_node };
	}

	bool for_loop(ParserState* state, ast::Node& parent) {
		ast::Node& for_node = next_as_node(state, ast::NodeType::FOR_LOOP, &parent);

		if (!accept(state, TokenType::IDENTIFIER, for_node)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			return false;
		}
		if (skip(state, TokenType::SYM_COMMA)
			&& !accept(state, TokenType::IDENTIFIER, for_node)) {
			//NOTE(ches) loop iterator value, if there's a comma
			report_error_on_last_token(state, ErrorCode::E3009);
			return false;
		}

		if (!accept(state, TokenType::KEYWORD_IN, for_node)) {
			report_error_on_last_token(state, ErrorCode::E3025);
			return false;
		}

		ExprResult expr = expression_with_result(state);
		if (!expr.success) {
			return false;
		}
		for_node.children.push_back(expr.result);

		ExprResult block_node = block(state);
		if (!block_node.success) {
			return false;
		}
		for_node.children.push_back(block_node.result);

		return true;
	}

	bool loop(ParserState* state, ast::Node& parent) {
		
		ast::Node* with_part = nullptr;

		if (expect(state, TokenType::KEYWORD_WITH)) {
			with_part = &next_as_node(state, ast::NodeType::WITH_CLAUSE);
			if (!expect(state, TokenType::SYM_LBRACE)) {
				report_error_on_last_token(state, ErrorCode::E3018);
				delete_node(state->node_alloc, with_part);
				return false;
			}
			ast::Node& with_block = next_as_node(state, ast::NodeType::LIST, with_part);

			while (expect(state, TokenType::IDENTIFIER)) {
				if (!any_definition(state, with_block)) {
					delete_node(state->node_alloc, with_part);
					return false;
				}
			}
			if (!skip(state, TokenType::SYM_RBRACE)) {
				report_error_on_last_token(state, ErrorCode::E3019);
				delete_node(state->node_alloc, with_part);
				return false;
			}
		}
		if (!expect(state, TokenType::KEYWORD_LOOP)) {
			report_error_on_last_token(state, ErrorCode::E3026);
			if (with_part != nullptr) {
				delete_node(state->node_alloc, with_part);
			}
			return false;
		}
		ast::Node* loop_node = &next_as_node(state, ast::NodeType::LOOP, &parent);

		if (with_part != nullptr) {
			loop_node->children.push_back(with_part);
		}
		
		//NOTE(ches) just grab a directive, or not, don't care
		accept(state, TokenType::DIRECTIVE, *loop_node);

		ExprResult block_node = block(state);
		if (!block_node.success) {
			return false;
		}
		loop_node->children.push_back(block_node.result);

		if (expect(state, TokenType::KEYWORD_WHILE)) {
			ast::Node& while_node = next_as_node(state, ast::NodeType::WHILE_CLAUSE, loop_node);
			if (!skip(state, TokenType::SYM_LPAREN)) {
				report_error_on_last_token(state, ErrorCode::E3014);
				return false;
			}
			ExprResult expr = expression_with_result(state);
			if (!expr.success) {
				return false;
			}
			while_node.children.push_back(expr.result);
			if (!skip(state, TokenType::SYM_RPAREN)) {
				report_error_on_last_token(state, ErrorCode::E3015);
				return false;
			}
		}

		return true;
	}

	bool push_context(ParserState* state, ast::Node& parent) {
		if (state == nullptr) { parent.type; } //TODO(ches) remove this
		return true;
	}

	ExprResult enum_shorthand(ParserState* state) {
		if (state == nullptr) { } //TODO(ches) remove this
		return ExprResult{ true, nullptr };
	}

	bool switch_statement(ParserState* state, ast::Node& parent) {
		if (state == nullptr) { parent.type; } //TODO(ches) remove this
		return true;
	}

	bool switch_entry(ParserState* state, ast::Node& parent) {
		if (state == nullptr) { parent.type; } //TODO(ches) remove this
		return true;
	}

	ExprResult match_expression(ParserState* state) {
		if (state == nullptr) { } //TODO(ches) remove this
		return ExprResult{ true, nullptr };
	}

	bool match_entry(ParserState* state, ast::Node& parent) {
		if (state == nullptr) { parent.type; } //TODO(ches) remove this
		return true;
	}
}