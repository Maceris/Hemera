#pragma once

#include <fstream>
#include <iostream>
#include <string_view>

#include "lexer/token.h"
#include "memory/allocator.h"

namespace hemera {
	namespace lexer {
		enum class State {
			ampersand,
			ampersand_2,
			annotation,
			asterisk,
			backslash,
			block_comment,
			dollar_sign,
			end,
			equal,
			exclamation,
			expect_newline,
			hash,
			identifier,
			integer,
			integer_binary,
			integer_exponent,
			integer_hex,
			integer_octal,
			integer_period,
			invalid,
			l_angle_bracket,
			l_angle_bracket_2,
			line_comment,
			literal_char,
			literal_char_backslash,
			literal_string,
			literal_string_backslash,
			minus,
			multiline_string_line,
			percent,
			percent_2,
			period,
			period_2,
			pipe,
			pipe_2,
			plus,
			r_angle_bracket,
			r_angle_bracket_2,
			r_angle_bracket_3,
			slash,
			start,
			tilde,
		};

		struct Tokenizer {
			MyString current_line;
			uint32_t line_number;
			uint16_t column_number;
			uint8_t comment_depth;
			const char _padding[1] = { 0 };

			Tokenizer()
				: current_line{}
				, line_number{ 1 }
				, column_number{ 0 }
				, comment_depth{ 0 }
			{
			}
			Tokenizer(const Tokenizer&) = delete;
			Tokenizer(Tokenizer&&) = default;
			Tokenizer& operator=(const Tokenizer&) = delete;
			Tokenizer& operator=(Tokenizer&&) = delete;
		};

		void lex_file(const std::string& file_path, MyVector<Token>& output,
			Allocator<> string_alloc);

		void lex(std::istream& input_stream, MyVector<Token>& output,
			Allocator<> string_alloc, std::string_view file_path);

		Token next(Tokenizer& tokenizer, std::istream& input_stream,
			Allocator<> string_alloc, std::string_view file_path);
	}
}