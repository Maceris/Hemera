
#include "lexer/token.h"

namespace hemera {
	Token::Token(TokenType type, uint16_t column_number, uint32_t line_number,
		MyString* value)
		: type{ type }
		, column_number{ column_number }
		, line_number{ line_number }
		, value{ value }
	{}
	Token::Token(const Token& other)
		: type{ other.type }
		, column_number{ other.column_number }
		, line_number{ other.line_number }
		, value{ other.value }
	{};
	Token::Token(Token&& other) noexcept
		: type{ std::move(other.type) }
		, column_number{ std::move(other.column_number) }
		, line_number{ std::move(other.line_number) }
		, value{ std::move(other.value) }
	{};
	Token::~Token() = default;
	Token& Token::operator=(const Token&) = default;
	Token& Token::operator=(Token&&) = default;
}