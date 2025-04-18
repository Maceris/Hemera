#pragma once

#include <cstdint>

#include "memory/allocator.h"

namespace hemera {

	enum class TokenType : uint16_t {
		ANNOTATION,
		END_OF_FILE,
		IDENTIFIER,
		INVALID,
		KEYWORD_ALIAS,
		KEYWORD_ALL,
		KEYWORD_AS,
		KEYWORD_BREAK,
		KEYWORD_CASE,
		KEYWORD_CONTEXT,
		KEYWORD_CONTINUE,
		KEYWORD_DEFER,
		KEYWORD_DISTINCT,
		KEYWORD_DO,
		KEYWORD_ELSE,
		KEYWORD_ENUM,
		KEYWORD_FALSE,
		KEYWORD_FN,
		KEYWORD_FOR,
		KEYWORD_IF,
		KEYWORD_IMPORT,
		KEYWORD_IN,
		KEYWORD_LOOP,
		KEYWORD_MATCH,
		KEYWORD_MUT,
		KEYWORD_NULL,
		KEYWORD_PACKAGE,
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
		OPERATOR_BITWISE_AND,
		OPERATOR_BITWISE_OR,
		OPERATOR_BITWISE_XOR,
		OPERATOR_DIVIDE,
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
		OPERATOR_QUESTION,
		OPERATOR_REMAINDER,
		OPERATOR_RIGHT_SHIFT_ARITHMETIC,
		OPERATOR_RIGHT_SHIFT_LOGICAL,
		SYM_ARROW,
		SYM_COLON,
		SYM_COMMA,
		SYM_DOT,
		SYM_EQ,
		SYM_GT,
		SYM_LBRACE,
		SYM_LBRACK,
		SYM_LPAREN,
		SYM_LT,
		SYM_QUOTE,
		SYM_RBRACE,
		SYM_RBRACK,
		SYM_RPAREN,
		SYM_SINGLE_QUOTE,
		SYM_UNDERSCORE,
	};

	struct Token {
		TokenType type;
		uint16_t column_number;
		uint32_t line_number;
		MyString* value;

		Token(TokenType type, uint16_t column_number, uint32_t line_number,
			MyString* value = nullptr)
			: type{ type }
			, column_number{ column_number }
			, line_number{ line_number }
			, value{ value }
		{}
		Token(const Token& other)
			: type{ other.type }
			, column_number{ other.column_number }
			, line_number{ other.line_number }
			, value{ other.value }
		{};
		Token(Token&& other) noexcept
			: type{ std::move(other.type) }
			, column_number{ std::move(other.column_number) }
			, line_number{ std::move(other.line_number) }
			, value{ std::move(other.value) }
		{};
		~Token() = default;
		Token& operator=(const Token&) = default;
		Token& operator=(Token&&) = default;
	};
}