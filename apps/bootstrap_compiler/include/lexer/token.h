#pragma once

#include <cstdint>

#include "memory/allocator.h"

namespace hemera {

	enum class TokenType : uint16_t {
		ANNOTATION,
		COMMENT_BLOCK,
		COMMENT_LINE,
		DIRECTIVE,
		END_OF_FILE,
		IDENTIFIER,
		INVALID,
		KEYWORD_ALIAS,
		KEYWORD_ALL,
		KEYWORD_AS,
		KEYWORD_AUTO_CAST,
		KEYWORD_BIT_CAST,
		KEYWORD_BREAK,
		KEYWORD_CASE,
		KEYWORD_CAST,
		KEYWORD_CONTINUE,
		KEYWORD_DEFER,
		KEYWORD_DISTINCT,
		KEYWORD_ELSE,
		KEYWORD_ENUM,
		KEYWORD_FALSE,
		KEYWORD_FN,
		KEYWORD_FOR,
		KEYWORD_FROM,
		KEYWORD_IF,
		KEYWORD_IMPORT,
		KEYWORD_IN,
		KEYWORD_IS_NONE,
		KEYWORD_IS_SOME,
		KEYWORD_LOOP,
		KEYWORD_MATCH,
		KEYWORD_MUT,
		KEYWORD_NULL,
		KEYWORD_OR_BREAK,
		KEYWORD_OR_CONTINUE,
		KEYWORD_OR_ELSE,
		KEYWORD_OR_RETURN,
		KEYWORD_PACKAGE,
		KEYWORD_PUSH_CONTEXT,
		KEYWORD_RETURN,
		KEYWORD_STRUCT,
		KEYWORD_SWITCH,
		KEYWORD_TRUE,
		KEYWORD_UNION,
		KEYWORD_USING,
		KEYWORD_VOID,
		KEYWORD_WHILE,
		KEYWORD_WITH,
		LITERAL_CHAR,
		LITERAL_FLOATING_POINT,
		LITERAL_INTEGER,
		LITERAL_STRING,
		OPERATOR_AND,
		OPERATOR_ASSIGN,
		OPERATOR_ASSIGN_ADD,
		OPERATOR_ASSIGN_AND,
		OPERATOR_ASSIGN_BITWISE_AND,
		OPERATOR_ASSIGN_BITWISE_OR,
		OPERATOR_ASSIGN_BITWISE_XOR,
		OPERATOR_ASSIGN_DIV,
		OPERATOR_ASSIGN_LEFT_SHIFT,
		OPERATOR_ASSIGN_MOD,
		OPERATOR_ASSIGN_MUL,
		OPERATOR_ASSIGN_OR,
		OPERATOR_ASSIGN_REMAINDER,
		OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC,
		OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL,
		OPERATOR_ASSIGN_SUB,
		OPERATOR_BITWISE_OR,
		OPERATOR_BITWISE_XOR,
		OPERATOR_DIVIDE,
		OPERATOR_DEREFERENCE,
		OPERATOR_EQUAL,
		OPERATOR_GREATER_THAN_OR_EQUAL,
		OPERATOR_LEFT_SHIFT,
		OPERATOR_LESS_THAN_OR_EQUAL,
		OPERATOR_MINUS,
		OPERATOR_MODULUS,
		OPERATOR_MULTIPLY,
		OPERATOR_NOT,
		OPERATOR_NOT_EQUAL,
		OPERATOR_OR,
		OPERATOR_PIPE,
		OPERATOR_PLUS,
		OPERATOR_RANGE_ARRAY,
		OPERATOR_RANGE_EXCLUSIVE,
		OPERATOR_RANGE_INCLUSIVE,
		OPERATOR_REMAINDER,
		OPERATOR_RIGHT_SHIFT_ARITHMETIC,
		OPERATOR_RIGHT_SHIFT_LOGICAL,
		PIPE_REORDER_IDENTIFIER,
		SYM_AMPERSAND,
		SYM_ARROW_DOUBLE,
		SYM_ARROW_SINGLE,
		SYM_COLON,
		SYM_COMMA,
		SYM_DOT,
		SYM_ELLIPSIS,
		SYM_GT,
		SYM_LBRACE,
		SYM_LBRACK,
		SYM_LPAREN,
		SYM_LT,
		SYM_QUESTION,
		SYM_RBRACE,
		SYM_RBRACK,
		SYM_RPAREN,
		SYM_UNDERSCORE,
		SYM_UNINITIALIZED,
	};

	struct Token {
		TokenType type;
		uint16_t column_number;
		uint32_t line_number;
		InternedString value;

		Token(TokenType type, uint16_t column_number, uint32_t line_number,
			InternedString value = nullptr);
		Token(const Token& other);
		Token(Token&& other) noexcept;
		~Token();
		Token& operator=(const Token&);
		Token& operator=(Token&&);
	};
}