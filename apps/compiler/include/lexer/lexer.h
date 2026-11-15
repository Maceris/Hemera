#pragma once

#include <fstream>
#include <iostream>
#include <string_view>
#include <vector>

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
			// The line just read was longer than a column can count, and was cut short (E2007)
			bool line_too_long;
			/*
			 * Byte offsets in the input (Token::offset): where current_line starts, where the line after it starts, and
			 * just past the last character taken, which is where a token ends
			 */
			uint32_t line_offset = 0;
			uint32_t next_line_offset = 0;
			uint32_t last_end = 0;
			/*
			 * Where the lines read so far, but not yet reported, have bytes that aren't UTF-8 (E2008) or a
			 * bidirectional control (E2009), in the order they're found; the next token reports them
			 */
			struct TextProblem {
				uint32_t line_number;
				uint16_t column_number;
				// The bidirectional control found, or 0 for bytes that aren't UTF-8
				uint32_t bidirectional_control;
			};
			std::vector<TextProblem> text_problems;

			Tokenizer();
			Tokenizer(const Tokenizer&) = delete;
			Tokenizer(Tokenizer&&) = default;
			Tokenizer& operator=(const Tokenizer&) = delete;
			Tokenizer& operator=(Tokenizer&&) = delete;
		};

		void lex_file(const std::string& file_path, MyVector<Token>& output,
			Allocator<> string_alloc, bool include_comments = false);

		void lex(std::istream& input_stream, MyVector<Token>& output,
			Allocator<> string_alloc, std::string_view file_path,
			bool include_comments = false);

		Token next(Tokenizer& tokenizer, std::istream& input_stream,
			Allocator<> string_alloc, std::string_view file_path);
	}
}
