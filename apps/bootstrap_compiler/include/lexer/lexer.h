#pragma once

#include <string_view>

#include "lexer/token.h"
#include "memory/allocator.h"

namespace hemera {
	namespace lexer {
		void lex(const std::string& file_path, MyVector<Token> output,
			Allocator<> string_alloc);
	}
}