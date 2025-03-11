#pragma once

#include <cstdint>

#include "memory/allocator.h"

namespace hemera {

	enum TokenType : uint16_t {

	};

	struct Token {
		TokenType type;
		uint16_t column_number;
		uint32_t line_number;
		MyString value;

		Token() = default;
		Token(const Token&) = default;
		Token(Token&&) = default;
		~Token() = default;
		Token& operator=(const Token&) = default;
		Token& operator=(Token&&) = default;
	};
}