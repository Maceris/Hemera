
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

	/*
	 * Presumes 
	 * 1. the child is the last node added to the vector
	 * 2. we add nodes in pre-order traversal order
	 * 3. the state's current position hasn't been updated (thus is 
	 *    at size - 1 for the vector, where our child node is)
	 */
	static inline void add_child(ParserState* state, ast::Node& parent,
		ast::Node& child) {
		size_t child_position = state->current;
		ast::offset to_child = parent.total_children + 1;
		ast::offset to_parent = -to_child;

		child.parent = to_parent;

		ast::Node* next_parent = &parent;

		while (to_parent != 0) {
			next_parent->total_children += 1;
			// Recurse up the parents, updating child counts
			child_position += to_parent; // becomes its parents, to_parent is negative
			to_parent = next_parent->parent;
			next_parent = &state->output[child_position];
		}
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

	void next(ParserState* state, ast::Node& parent) {
		Token current = current_token(state);
		ast::Node& child = state->output.emplace_back(ast::NodeType::LEAF, current);
		add_child(state, parent, child);
		state->current += 1;
	}

	ast::Node& next_as_node(ParserState* state, ast::NodeType type, ast::Node& parent) {
		Token current = current_token(state);
		ast::Node& result = state->output.emplace_back(type, current);
		add_child(state, parent, result);
		state->current += 1;
		return result;
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
		MyVector<ast::Node>& output)
	{
		ParserState state(file_path, tokens, output);

		Token current(TokenType::END_OF_FILE, 0, 0);//TODO(ches) ???
		ast::Node& node = state.output.emplace_back(ast::NodeType::FILE, current);

		package_statement(&state, node);
		imports(&state, node);
		const_definitions(&state, node);
	}

	void comments(ParserState* state, ast::Node& parent) {
		while (accept(state, TokenType::COMMENT_BLOCK, parent) 
			|| accept(state, TokenType::COMMENT_LINE, parent)) {}
	}

	void package_statement(ParserState* state, ast::Node& parent) {
		comments(state, parent);

		if (!skip(state, TokenType::KEYWORD_PACKAGE)) {
			report_error_on_last_token(state, ErrorCode::E3001);
			return;
		}
		ast::Node& node = next_as_node(state, ast::NodeType::PACKAGE, parent);

		if (!accept(state, TokenType::IDENTIFIER, node)) {
			report_error_on_last_token(state, ErrorCode::E3002);
			return;
		}
	}

	void imports(ParserState* state, ast::Node& parent) {
		comments(state, parent);
		while (expect(state, TokenType::KEYWORD_IMPORT)) {
			import(state, parent);
			comments(state, parent);
		}
	}

	void import(ParserState* state, ast::Node& parent) {
		ast::Node& node = next_as_node(state, ast::NodeType::IMPORT, parent);

		skip(state, TokenType::KEYWORD_IMPORT);

		if (!accept(state, TokenType::IDENTIFIER, node)) {
			report_error_on_last_token(state, ErrorCode::E3003);
			return;
		}


		if (expect(state, TokenType::KEYWORD_AS)) {
			accept(state, TokenType::KEYWORD_AS, node);
			if (!accept(state, TokenType::IDENTIFIER, node)) {
				report_error_on_last_token(state, ErrorCode::E3005);
				return;
			}
		}

		if (expect(state, TokenType::KEYWORD_FROM)) {
			accept(state, TokenType::KEYWORD_FROM, node);
			if (!accept(state, TokenType::LITERAL_STRING, node)) {
				report_error_on_last_token(state, ErrorCode::E3004);
				return;
			}
		}
	}

	void const_definitions(ParserState* state, ast::Node& parent) {
		comments(state, parent);
		while (expect(state, TokenType::IDENTIFIER)) {
			declaration(state, parent);
			const_definition_rhs(state, parent);
			comments(state, parent);
		}
	}

	void any_definition(ParserState* state, ast::Node& parent) {
		declaration(state, parent);

		if (expect(state, TokenType::SYM_COLON)) {
			const_definition_rhs(state, parent);
		}
		else if (expect(state, TokenType::OPERATOR_ASSIGN)) {
			mut_definition_rhs(state, parent);
		}
		else {
			report_error_on_last_token(state, ErrorCode::E3006);
		}
	}

	void const_definition_rhs(ParserState* state, ast::Node& parent) {
		if (!accept(state, TokenType::SYM_COLON, parent)) {
			report_error_on_last_token(state, ErrorCode::E3007);
			return;
		}
		decl_rhs(state, parent);
	}

	void mut_definition_rhs(ParserState* state, ast::Node& parent) {
		if (!accept(state, TokenType::OPERATOR_ASSIGN, parent)) {
			report_error_on_last_token(state, ErrorCode::E3008);
			return;
		}
		decl_rhs(state, parent);
	}

	void declaration(ParserState* state, ast::Node& parent) {
		if (!accept(state, TokenType::IDENTIFIER, parent)) {
			report_error_on_last_token(state, ErrorCode::E3009);
			return;
		}
		if (!accept(state, TokenType::SYM_COLON, parent)) {
			report_error_on_last_token(state, ErrorCode::E3010);
			return;
		}
		comments(state, parent);
		//TODO(ches) type
	}

	void decl_rhs(ParserState* state, ast::Node& parent) {
		//TODO(ches) decls
		if (state == nullptr) { parent.type; } //TODO(ches) remove this
	}

}