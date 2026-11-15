#include "lexer/token.h"

namespace hemera {
	Token::Token(TokenType type, uint16_t column_number, uint32_t line_number,
		InternedString value, uint32_t offset, uint32_t length)
		: type{ type }
		, column_number{ column_number }
		, line_number{ line_number }
		, offset{ offset }
		, length{ length }
		, value{ value }
	{}
	Token::Token(const Token& other)
		: type{ other.type }
		, column_number{ other.column_number }
		, line_number{ other.line_number }
		, offset{ other.offset }
		, length{ other.length }
		, value{ other.value }
	{};
	Token::Token(Token&& other) noexcept
		: type{ std::move(other.type) }
		, column_number{ std::move(other.column_number) }
		, line_number{ std::move(other.line_number) }
		, offset{ other.offset }
		, length{ other.length }
		, value{ std::move(other.value) }
	{};
	Token::~Token() = default;
	Token& Token::operator=(const Token&) = default;
	Token& Token::operator=(Token&&) = default;
}
