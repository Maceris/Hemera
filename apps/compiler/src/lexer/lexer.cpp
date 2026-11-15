#include <algorithm>
#include <cctype>
#include <concepts>
#include <format>
#include <limits>
#include <optional>

#include "error/reporting.h"
#include "lexer/identifiers.h"
#include "lexer/lexer.h"
#include "util/logger.h"
#include "util/utf8.h"

namespace hemera::lexer {

	Tokenizer::Tokenizer()
		: current_line{}
		, line_number{ 1 }
		, column_number{ 0 }
		, comment_depth{ 0 }
		, line_too_long{ false }
	{}

	/*
	 * A line can have at most MAX_LINE_LENGTH characters, as many as a token's column counts; a longer
	 * one is cut short there, and reported by the next token (E2007).
	 */
	constexpr size_t MAX_LINE_LENGTH = 0xffff;

	/*
	 * Checks a line just read, before it's lexed: that it's UTF-8 and has no bidirectional controls, noting where
	 * it isn't or has for the next token to report (E2008, E2009), and that it isn't too long. Only the first bytes
	 * that aren't UTF-8 are noted, so one stray byte doesn't make a report per byte after it.
	 */
	static void check_line(Tokenizer& tokenizer, MyString& line) {
		const std::string_view text(line.data(), std::min(line.size(), MAX_LINE_LENGTH));
		bool reported_invalid = false;
		for (size_t at = 0; at < text.size();) {
			uint32_t code_point = 0;
			const size_t length = utf8::decode(text, at, code_point);
			if (length == 0) {
				if (!reported_invalid) {
					tokenizer.text_problems.push_back({ tokenizer.line_number, static_cast<uint16_t>(at), 0 });
					reported_invalid = true;
				}
				at += 1;
				continue;
			}
			if (utf8::is_bidirectional_control(code_point)) {
				tokenizer.text_problems.push_back({ tokenizer.line_number, static_cast<uint16_t>(at), code_point });
			}
			at += length;
		}
		if (line.size() > MAX_LINE_LENGTH) {
			line.resize(MAX_LINE_LENGTH);
			tokenizer.line_too_long = true;
		}
	}

	static void report_text_problems(Tokenizer& tokenizer, std::string_view file_path) {
		for (const Tokenizer::TextProblem& problem : tokenizer.text_problems) {
			if (problem.bidirectional_control == 0) {
				report_error(ErrorCode::E2008, file_path, problem.line_number, problem.column_number,
					"source files are UTF-8");
			}
			else {
				report_error(ErrorCode::E2009, file_path, problem.line_number, problem.column_number,
					std::format("U+{:04X} can make code display in an order other than it's read; in a string, write it "
						"as \\u{{{:X}}}", problem.bidirectional_control, problem.bidirectional_control));
			}
		}
		tokenizer.text_problems.clear();
	}

	/*
	 * Reads the next line, without its line ending. Sources are read as they are on disk, so a line ending in CRLF
	 * comes with its CR, which goes with the LF as the line's ending. A CR with no LF after it, inside a line or at the
	 * end of the file, stays in the line, an error where it's lexed (E2002).
	 */
	static bool read_line(std::istream& input_stream, MyString& line) {
		if (!std::getline(input_stream, line)) {
			return false;
		}
		// getline stopped at an LF unless it reached the end of the input
		if (!input_stream.eof() && !line.empty() && line.back() == '\r') {
			line.pop_back();
		}
		return true;
	}

	static bool next_line(Tokenizer& tokenizer, std::istream& input_stream) {
		/*
		 * getline empties the string it's given even when there's no line left, so read into
		 * another one: a token that runs to the end of the last line, like a trailing comment,
		 * still needs the current line to copy its text from.
		 */
		MyString line;
		if (!read_line(input_stream, line)) {
			return false;
		}
		tokenizer.line_number += 1;
		check_line(tokenizer, line);
		tokenizer.current_line = line;
		tokenizer.column_number = 0;
		return true;
	}

	static char peek_char(Tokenizer& tokenizer, int extra_ahead = 0) {
		size_t next_index = static_cast<size_t>(tokenizer.column_number + extra_ahead);
		if (next_index >= tokenizer.current_line.length()) {
			return 0;
		}
		return tokenizer.current_line[next_index];
	}

	/// <summary>
	/// Fetches the current character, and then increments the column number.
	/// If we ran off the end of a line, returns a newline and resets the
	/// column number.
	/// </summary>
	/// <param name="tokenizer">The tokenizer state.</param>
	/// <param name="input_stream">The stream to read characters from.</param>
	/// <param name="start_column">The starting column, only passed for
	/// things that might be multi-line</param>
	/// <param name="token_contents">The string to append a line to if we 
	/// have to read a new line, only passed for things that might be
	/// multi-line.</param>
	/// <returns></returns>
	static char next_char(Tokenizer& tokenizer, std::istream& input_stream, 
		uint32_t start_line = 0, uint16_t start_column = 0,
		MyString* token_contents = nullptr) {
		if (tokenizer.column_number >= tokenizer.current_line.length()) {
			if (token_contents) {
				size_t first_position = 0;
				if (start_line == tokenizer.line_number) {
					first_position = start_column;
				}
				*token_contents += tokenizer.current_line.substr(first_position);
				*token_contents += '\n';
			}

			if (!next_line(tokenizer, input_stream)) {
				return 0;
			}
			else {
				return '\n';
			}
		}
		if (tokenizer.column_number >= tokenizer.current_line.length()) {
			return 0;
		}
		char result = tokenizer.current_line[tokenizer.column_number];
		tokenizer.column_number += 1;
		return result;
	}

	/*
	 * Takes the rest of a \u{...} escape in a quoted string, just after its u: braces around 1 to 6 hex digits, naming
	 * a code point up to U+10FFFF that isn't a surrogate (U+D800 to U+DFFF). Reports one that isn't (E2010) at its u,
	 * taking as much as looked like it, but never the string's closing quote or the end of the line.
	 */
	static void unicode_escape(Tokenizer& tokenizer, std::istream& input_stream, std::string_view file_path) {
		const uint32_t line = tokenizer.line_number;
		const uint16_t column = static_cast<uint16_t>(tokenizer.column_number - 1);
		bool valid = peek_char(tokenizer) == '{';
		uint32_t value = 0;
		size_t digits = 0;
		if (valid) {
			next_char(tokenizer, input_stream);
			while (std::isxdigit(static_cast<unsigned char>(peek_char(tokenizer)))) {
				const char digit = next_char(tokenizer, input_stream);
				if (digits < 7) {
					value = value * 16 + static_cast<uint32_t>(std::isdigit(static_cast<unsigned char>(digit))
						? digit - '0' : std::tolower(static_cast<unsigned char>(digit)) - 'a' + 10);
				}
				digits += 1;
			}
			valid = peek_char(tokenizer) == '}';
			if (valid) {
				next_char(tokenizer, input_stream);
			}
		}
		if (!valid || digits == 0 || digits > 6) {
			report_error(ErrorCode::E2010, file_path, line, column, "it's written \\u{...}, with 1 to 6 hex digits");
		}
		else if (value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) {
			report_error(ErrorCode::E2010, file_path, line, column,
				std::format("U+{:X} isn't a Unicode scalar value: it's past U+10FFFF or a surrogate", value));
		}
	}

	Token next(Tokenizer& tokenizer, std::istream& input_stream,
		Allocator<> string_alloc, std::string_view file_path) {

		if (tokenizer.line_too_long) {
			tokenizer.line_too_long = false;
			report_error(ErrorCode::E2007, file_path, tokenizer.line_number, 0,
				std::format("a line can have at most {} characters", MAX_LINE_LENGTH));
		}
		report_text_problems(tokenizer, file_path);
		uint32_t start_line = tokenizer.line_number;
		uint16_t start_column = tokenizer.column_number;
		TokenType result_type = TokenType::END_OF_FILE;
		MyString* token_contents = string_alloc.new_object<MyString>();

		State state = State::start;

		switch_start:
		switch (state) {
		case State::ampersand:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_BITWISE_AND;
				next_char(tokenizer, input_stream);
				break;
			case '&':
				state = State::ampersand_2;
				next_char(tokenizer, input_stream);
				goto switch_start;
			default:
				result_type = TokenType::SYM_AMPERSAND;
				break;
			}
			break;
		case State::ampersand_2:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_AND;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::OPERATOR_AND;
				break;
			}
			break;
		case State::asterisk:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_MUL;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::OPERATOR_MULTIPLY;
				break;
			}
			break;
		case State::annotation:
			switch (peek_char(tokenizer)) {
			case 'a': case 'b': case 'c': case 'd': case 'e':
			case 'f': case 'g': case 'h': case 'i': case 'j':
			case 'k': case 'l': case 'm': case 'n': case 'o':
			case 'p': case 'q': case 'r': case 's': case 't':
			case 'u': case 'v': case 'w': case 'x': case 'y':
			case 'z':
			case 'A': case 'B': case 'C': case 'D': case 'E':
			case 'F': case 'G': case 'H': case 'I': case 'J':
			case 'K': case 'L': case 'M': case 'N': case 'O':
			case 'P': case 'Q': case 'R': case 'S': case 'T':
			case 'U': case 'V': case 'W': case 'X': case 'Y':
			case 'Z':
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
			case '_':
				next_char(tokenizer, input_stream);
				goto switch_start;
			default:
				break;
			}
			break;
		case State::backslash:
			switch (peek_char(tokenizer)) {
			case '\\':
				state = State::multiline_string_line;
				// One token per line, the parser joins consecutive lines
				result_type = TokenType::LITERAL_STRING;
				next_char(tokenizer, input_stream, start_line, start_column, token_contents);
				goto switch_start;
			case 0:
			case '\n':
			default:
				state = State::invalid;
				report_error(ErrorCode::E2001, file_path, tokenizer.line_number, tokenizer.column_number);
				goto switch_start;
			}
		case State::block_comment:
			switch (next_char(tokenizer, input_stream, start_line, start_column, token_contents)) {
			case '*':
				if (peek_char(tokenizer) == '/') {
					next_char(tokenizer, input_stream, start_line, start_column, token_contents);
					tokenizer.comment_depth -= 1;
				}
				if (tokenizer.comment_depth > 0) {
					goto switch_start;
				}
				break;
			case '/':
				if (peek_char(tokenizer) == '*') {
					next_char(tokenizer, input_stream, start_line, start_column, token_contents);
					tokenizer.comment_depth += 1;
				}
				goto switch_start;
			default:
				goto switch_start;
			}
			break;
		case State::dollar_sign:
			switch (peek_char(tokenizer)) {
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
				next_char(tokenizer, input_stream);
				goto switch_start;
			default:
				break;
			}
			break;
		case State::end:
			result_type = TokenType::END_OF_FILE;
			break;
		case State::equal:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_EQUAL;
				next_char(tokenizer, input_stream);
				break;
			case '>':
				result_type = TokenType::SYM_ARROW_DOUBLE;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::OPERATOR_ASSIGN;
				break;
			}
			break;
		case State::exclamation:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_NOT_EQUAL;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::OPERATOR_NOT;
				break;
			}
			break;
		case State::expect_newline:
			switch (peek_char(tokenizer)) {
			case '\n':
				next_char(tokenizer, input_stream);
				break;
			case 0:
			default:
				state = State::invalid;
				report_error(ErrorCode::E2002, file_path, tokenizer.line_number, tokenizer.column_number);
				goto switch_start;
			}
			break;
		case State::hash:
			switch (peek_char(tokenizer)) {
			case 'a': case 'b': case 'c': case 'd': case 'e':
			case 'f': case 'g': case 'h': case 'i': case 'j':
			case 'k': case 'l': case 'm': case 'n': case 'o':
			case 'p': case 'q': case 'r': case 's': case 't':
			case 'u': case 'v': case 'w': case 'x': case 'y':
			case 'z':
			case 'A': case 'B': case 'C': case 'D': case 'E':
			case 'F': case 'G': case 'H': case 'I': case 'J':
			case 'K': case 'L': case 'M': case 'N': case 'O':
			case 'P': case 'Q': case 'R': case 'S': case 'T':
			case 'U': case 'V': case 'W': case 'X': case 'Y':
			case 'Z':
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
			case '_':
				next_char(tokenizer, input_stream);
				goto switch_start;
			default:
				break;
			}
			break;
		case State::identifier:
			switch (peek_char(tokenizer)) {
			case 'a': case 'b': case 'c': case 'd': case 'e':
			case 'f': case 'g': case 'h': case 'i': case 'j':
			case 'k': case 'l': case 'm': case 'n': case 'o':
			case 'p': case 'q': case 'r': case 's': case 't':
			case 'u': case 'v': case 'w': case 'x': case 'y':
			case 'z':
			case 'A': case 'B': case 'C': case 'D': case 'E':
			case 'F': case 'G': case 'H': case 'I': case 'J':
			case 'K': case 'L': case 'M': case 'N': case 'O':
			case 'P': case 'Q': case 'R': case 'S': case 'T':
			case 'U': case 'V': case 'W': case 'X': case 'Y':
			case 'Z':
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
			case '_':
				next_char(tokenizer, input_stream);
				goto switch_start;
			default:
				// A letter, digit or mark outside ASCII, all its bytes
				if (const size_t length = identifier_character(tokenizer.current_line, tokenizer.column_number, false); length > 0) {
					for (size_t i = 0; i < length; ++i) {
						next_char(tokenizer, input_stream);
					}
					goto switch_start;
				}
				break;
			}
			break;
		case State::integer:
			switch (peek_char(tokenizer)) {
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '_':
				//NOTE(ches) just pretend underscore isn't there
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '.':
				if (peek_char(tokenizer, 1) == '.') {
					break;
				}
				state = State::integer_period;
				result_type = TokenType::LITERAL_FLOATING_POINT;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case 'e':
			case 'E':
				state = State::integer_exponent;
				result_type = TokenType::LITERAL_FLOATING_POINT;
				next_char(tokenizer, input_stream);
				if (peek_char(tokenizer) == '-') {
					next_char(tokenizer, input_stream);
				}
				goto switch_start;
			case 'i': case 'j': case 'k':
				// An imaginary literal, unless the letter starts a name
				if (identifier_character(tokenizer.current_line, tokenizer.column_number + 1u, false) == 0) {
					result_type = TokenType::LITERAL_IMAGINARY;
					next_char(tokenizer, input_stream);
				}
				break;
			default:
				break;
			}
			break;
		case State::integer_binary:
			switch (peek_char(tokenizer)) {
			case '0': case '1':
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '_':
				//NOTE(ches) just pretend underscore isn't there
				next_char(tokenizer, input_stream);
				goto switch_start;
			default:
				break;
			}
			break;
		case State::integer_exponent:
			switch (peek_char(tokenizer)) {
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '_':
				//NOTE(ches) just pretend underscore isn't there
				next_char(tokenizer, input_stream);
				goto switch_start;
			case 'i': case 'j': case 'k':
				// An imaginary literal, unless the letter starts a name
				if (identifier_character(tokenizer.current_line, tokenizer.column_number + 1u, false) == 0) {
					result_type = TokenType::LITERAL_IMAGINARY;
					next_char(tokenizer, input_stream);
				}
				break;
			default:
				break;
			}
			break;
		case State::integer_hex:
			switch (peek_char(tokenizer)) {
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
			case 'a': case 'A': case 'b': case 'B':
			case 'c': case 'C': case 'd': case 'D':
			case 'e': case 'E': case 'f': case 'F':
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '_':
				//NOTE(ches) just pretend underscore isn't there
				next_char(tokenizer, input_stream);
				goto switch_start;
			default:
				break;
			}
			break;
		case State::integer_octal:
			switch (peek_char(tokenizer)) {
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7':
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '_':
				//NOTE(ches) just pretend underscore isn't there
				next_char(tokenizer, input_stream);
				goto switch_start;
			default:
				break;
			}
			break;
		case State::integer_period:
			switch (peek_char(tokenizer)) {
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '_':
				//NOTE(ches) just pretend underscore isn't there
				next_char(tokenizer, input_stream);
				goto switch_start;
			case 'e':
			case 'E':
				state = State::integer_exponent;
				LOG_ASSERT(result_type == TokenType::LITERAL_FLOATING_POINT);
				next_char(tokenizer, input_stream);
				if (peek_char(tokenizer) == '-') {
					next_char(tokenizer, input_stream);
				}
				goto switch_start;
			case 'i': case 'j': case 'k':
				// An imaginary literal, unless the letter starts a name
				if (identifier_character(tokenizer.current_line, tokenizer.column_number + 1u, false) == 0) {
					result_type = TokenType::LITERAL_IMAGINARY;
					next_char(tokenizer, input_stream);
				}
				break;
			default:
				break;
			}
			break;
		case State::invalid:
			result_type = TokenType::INVALID;
			break;
		case State::l_angle_bracket:
			switch (peek_char(tokenizer)) {
			case '<':
				state = State::l_angle_bracket_2;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '=':
				result_type = TokenType::OPERATOR_LESS_THAN_OR_EQUAL;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::SYM_LT;
				break;
			}
			break;
		case State::l_angle_bracket_2:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_LEFT_SHIFT;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::OPERATOR_LEFT_SHIFT;
				break;
			}
			break;
		case State::line_comment:
			switch (next_char(tokenizer, input_stream, start_line, start_column, token_contents)) {
			case 0:
			case '\n':
				break;
			case '\r':
				state = State::expect_newline;
				goto switch_start;
			default:
				goto switch_start;
			} 
			break;
		case State::literal_char:
			switch (next_char(tokenizer, input_stream)) {
			case '\'':
				break;
			case '\\':
				state = State::literal_char_backslash;
				goto switch_start;
			case 0:
			case '\n':
			case 0x01: case 0x02: case 0x03: case 0x04: case 0x05:
			case 0x06: case 0x07: case 0x08: case 0x09: case 0x0b:
			case 0x0c: case 0x0d: case 0x0e: case 0x0f: case 0x10:
			case 0x11: case 0x12: case 0x13: case 0x14: case 0x15:
			case 0x16: case 0x17: case 0x18: case 0x19: case 0x1a:
			case 0x1b: case 0x1c: case 0x1d: case 0x1e: case 0x1f:
			case 0x7f:
				state = State::invalid;
				report_error(ErrorCode::E2003, file_path, tokenizer.line_number, tokenizer.column_number);
				goto switch_start;
			default:
				goto switch_start;
			}
			break;
		case State::literal_char_backslash:
			switch (next_char(tokenizer, input_stream)) {
			case 0:
			case '\n':
			case 0x01: case 0x02: case 0x03: case 0x04: case 0x05:
			case 0x06: case 0x07: case 0x08: case 0x09: case 0x0b:
			case 0x0c: case 0x0d: case 0x0e: case 0x0f: case 0x10:
			case 0x11: case 0x12: case 0x13: case 0x14: case 0x15:
			case 0x16: case 0x17: case 0x18: case 0x19: case 0x1a:
			case 0x1b: case 0x1c: case 0x1d: case 0x1e: case 0x1f:
			case 0x7f:
				state = State::invalid;
				report_error(ErrorCode::E2003, file_path, tokenizer.line_number, tokenizer.column_number);
				goto switch_start;
			default:
				state = State::literal_char;
				goto switch_start;
			}
		case State::literal_string:
			switch (next_char(tokenizer, input_stream)) {
			case '"':
				break;
			case '\\':
				state = State::literal_string_backslash;
				goto switch_start;
			case 0:
			case '\n':
			case 0x01: case 0x02: case 0x03: case 0x04: case 0x05:
			case 0x06: case 0x07: case 0x08: case 0x09: case 0x0b:
			case 0x0c: case 0x0d: case 0x0e: case 0x0f: case 0x10:
			case 0x11: case 0x12: case 0x13: case 0x14: case 0x15:
			case 0x16: case 0x17: case 0x18: case 0x19: case 0x1a:
			case 0x1b: case 0x1c: case 0x1d: case 0x1e: case 0x1f:
			case 0x7f:
				state = State::invalid;
				report_error(ErrorCode::E2004, file_path, tokenizer.line_number, tokenizer.column_number);
				goto switch_start;
			default:
				goto switch_start;
			}
			break;
		case State::literal_string_backslash:
			switch (next_char(tokenizer, input_stream)) {
			case 0:
			case '\n':
			case 0x01: case 0x02: case 0x03: case 0x04: case 0x05:
			case 0x06: case 0x07: case 0x08: case 0x09: case 0x0b:
			case 0x0c: case 0x0d: case 0x0e: case 0x0f: case 0x10:
			case 0x11: case 0x12: case 0x13: case 0x14: case 0x15:
			case 0x16: case 0x17: case 0x18: case 0x19: case 0x1a:
			case 0x1b: case 0x1c: case 0x1d: case 0x1e: case 0x1f:
			case 0x7f:
				state = State::invalid;
				report_error(ErrorCode::E2004, file_path, tokenizer.line_number, tokenizer.column_number);
				goto switch_start;
			case 'u':
				unicode_escape(tokenizer, input_stream, file_path);
				state = State::literal_string;
				goto switch_start;
			default:
				state = State::literal_string;
				goto switch_start;
			}
		case State::minus:
			switch (peek_char(tokenizer)) {
			case '>':
				result_type = TokenType::SYM_ARROW_SINGLE;
				next_char(tokenizer, input_stream);
				break;
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_SUB;
				next_char(tokenizer, input_stream);
				break;
			case '-':
				if (peek_char(tokenizer, 1) == '-') {
					result_type = TokenType::SYM_UNINITIALIZED;
					next_char(tokenizer, input_stream);
					next_char(tokenizer, input_stream);
				}
				else {
					result_type = TokenType::OPERATOR_MINUS;
				}
				break;
			default:
				result_type = TokenType::OPERATOR_MINUS;
				break;
			}
			break;
		case State::multiline_string_line:
			switch (next_char(tokenizer, input_stream, start_line, start_column, token_contents)) {
			case 0:
				state = State::invalid;
				report_error(ErrorCode::E2005, file_path, tokenizer.line_number, tokenizer.column_number);
				goto switch_start;
			case '\n':
				break;
			case '\r':
				if (peek_char(tokenizer) != '\n') {
					state = State::invalid;
					report_error(ErrorCode::E2002, file_path, tokenizer.line_number, tokenizer.column_number);
					goto switch_start;
				}
				goto switch_start;
			case 0x01: case 0x02: case 0x03: case 0x04: case 0x05:
			case 0x06: case 0x07: case 0x08: case 0x09: case 0x0b:
			case 0x0c: case 0x0e: case 0x0f: case 0x10: case 0x11:
			case 0x12: case 0x13: case 0x14: case 0x15: case 0x16:
			case 0x17: case 0x18: case 0x19: case 0x1a: case 0x1b:
			case 0x1c: case 0x1d: case 0x1e: case 0x1f: case 0x7f:
				state = State::invalid;
				report_error(ErrorCode::E2004, file_path, tokenizer.line_number, tokenizer.column_number);
				goto switch_start;
			default:
				goto switch_start;
			}
			break;
		case State::percent:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_MOD;
				next_char(tokenizer, input_stream);
				break;
			case '%':
				state = State::percent_2;
				next_char(tokenizer, input_stream);
				goto switch_start;
			default:
				result_type = TokenType::OPERATOR_MODULUS;
				break;
			}
			break;
		case State::percent_2:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_REMAINDER;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::OPERATOR_REMAINDER;
				break;
			}
			break;
		case State::period:
			switch (peek_char(tokenizer)) {
			case '.':
				state = State::period_2;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
				state = State::integer_period;
				result_type = TokenType::LITERAL_FLOATING_POINT;
				next_char(tokenizer, input_stream);
				goto switch_start;
			default:
				result_type = TokenType::SYM_DOT;
				break;
			}
			break;
		case State::period_2:
			switch (peek_char(tokenizer)) {
			case '.':
				result_type = TokenType::SYM_ELLIPSIS;
				next_char(tokenizer, input_stream);
				break;
			case '<':
				result_type = TokenType::OPERATOR_RANGE_EXCLUSIVE;
				next_char(tokenizer, input_stream);
				break;
			case '=':
				result_type = TokenType::OPERATOR_RANGE_INCLUSIVE;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::OPERATOR_RANGE_ARRAY;
				break;
			}
			break;
		case State::pipe:
			switch (peek_char(tokenizer)) {
			case '|':
				state = State::pipe_2;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_BITWISE_OR;
				next_char(tokenizer, input_stream);
				break;
			case '>':
				result_type = TokenType::OPERATOR_PIPE;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::OPERATOR_BITWISE_OR;
				break;
			}
			break;
		case State::pipe_2:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_OR;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::OPERATOR_OR;
				break;
			}
			break;
		case State::plus:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_ADD;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::OPERATOR_PLUS;
				break;
			}
			break;
		case State::r_angle_bracket:
			switch (peek_char(tokenizer)) {
			case '>':
				state = State::r_angle_bracket_2;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '=':
				result_type = TokenType::OPERATOR_GREATER_THAN_OR_EQUAL;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::SYM_GT;
				break;
			}
			break;
		case State::r_angle_bracket_2:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC;
				next_char(tokenizer, input_stream);
				break;
			case '>':
				state = State::r_angle_bracket_3;
				next_char(tokenizer, input_stream);
				goto switch_start;
			default:
				result_type = TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC;
				break;
			}
			break;
		case State::r_angle_bracket_3:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL;
				break;
			}
			break;
		case State::slash:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_DIV;
				next_char(tokenizer, input_stream);
				break;
			case '*':
				state = State::block_comment;
				result_type = TokenType::COMMENT_BLOCK;
				tokenizer.comment_depth += 1;
				next_char(tokenizer, input_stream, start_line, start_column, token_contents);
				goto switch_start;
			case '/':
				state = State::line_comment;
				result_type = TokenType::COMMENT_LINE;
				next_char(tokenizer, input_stream, start_line, start_column, token_contents);
				goto switch_start;
			default:
				result_type = TokenType::OPERATOR_DIVIDE;
				break;
			}
			break;
		case State::start:
			switch (peek_char(tokenizer)) {
			case 0:
				if (next_line(tokenizer, input_stream)) {
					start_line += 1;
					start_column = 0;
					goto switch_start;
				}
				state = State::end;
				goto switch_start;
			case ' ':
			case '\n':
			case '\t':
				next_char(tokenizer, input_stream);
				start_column += 1;
				goto switch_start;
			case '\r':
				next_char(tokenizer, input_stream);
				state = State::expect_newline;
				goto switch_start;
			case 'a': case 'b': case 'c': case 'd': case 'e':
			case 'f': case 'g': case 'h': case 'i': case 'j':
			case 'k': case 'l': case 'm': case 'n': case 'o':
			case 'p': case 'q': case 'r': case 's': case 't':
			case 'u': case 'v': case 'w': case 'x': case 'y':
			case 'z':
			case 'A': case 'B': case 'C': case 'D': case 'E':
			case 'F': case 'G': case 'H': case 'I': case 'J':
			case 'K': case 'L': case 'M': case 'N': case 'O':
			case 'P': case 'Q': case 'R': case 'S': case 'T':
			case 'U': case 'V': case 'W': case 'X': case 'Y':
			case 'Z':
				state = State::identifier;
				result_type = TokenType::IDENTIFIER;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '1': case '2': case '3': case '4': case '5':
			case '6': case '7': case '8': case '9':
				result_type = TokenType::LITERAL_INTEGER;
				state = State::integer;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '0':
				result_type = TokenType::LITERAL_INTEGER;
				state = State::integer;
				next_char(tokenizer, input_stream);
				switch (peek_char(tokenizer)) {
				case 'x':
					state = State::integer_hex;
					next_char(tokenizer, input_stream);
					break;
				case 'o':
					state = State::integer_octal;
					next_char(tokenizer, input_stream);
					break;
				case 'b':
					state = State::integer_binary;
					next_char(tokenizer, input_stream);
					break;
				}
				goto switch_start;
			case '_':
				result_type = TokenType::SYM_UNDERSCORE;
				next_char(tokenizer, input_stream);
				break;
			case '"':
				state = State::literal_string;
				result_type = TokenType::LITERAL_STRING;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '\'':
				state = State::literal_char;
				result_type = TokenType::LITERAL_CHAR;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '@':
				state = State::annotation;
				result_type = TokenType::ANNOTATION;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '=':
				state = State::equal;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '!':
				state = State::exclamation;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '|':
				state = State::pipe;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '%':
				state = State::percent;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '*':
				state = State::asterisk;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '+':
				state = State::plus;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '<':
				state = State::l_angle_bracket;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '>':
				state = State::r_angle_bracket;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '~':
				state = State::tilde;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '.':
				state = State::period;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '-':
				state = State::minus;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '/':
				state = State::slash;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '&':
				state = State::ampersand;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '\\':
				state = State::backslash;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '$':
				state = State::dollar_sign;
				result_type = TokenType::PIPE_REORDER_IDENTIFIER;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '#':
				state = State::hash;
				result_type = TokenType::DIRECTIVE;
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '^':
				result_type = TokenType::OPERATOR_DEREFERENCE;
				next_char(tokenizer, input_stream);
				break;
			case '(':
				result_type = TokenType::SYM_LPAREN;
				next_char(tokenizer, input_stream);
				break;
			case ')':
				result_type = TokenType::SYM_RPAREN;
				next_char(tokenizer, input_stream);
				break;
			case '[':
				result_type = TokenType::SYM_LBRACK;
				next_char(tokenizer, input_stream);
				break;
			case ']':
				result_type = TokenType::SYM_RBRACK;
				next_char(tokenizer, input_stream);
				break;
			case '{':
				result_type = TokenType::SYM_LBRACE;
				next_char(tokenizer, input_stream);
				break;
			case '}':
				result_type = TokenType::SYM_RBRACE;
				next_char(tokenizer, input_stream);
				break;
			case '?':
				result_type = TokenType::SYM_QUESTION;
				next_char(tokenizer, input_stream);
				break;
			case ',':
				result_type = TokenType::SYM_COMMA;
				next_char(tokenizer, input_stream);
				break;
			case ':':
				result_type = TokenType::SYM_COLON;
				next_char(tokenizer, input_stream);
				break;
			default: {
				// A name can start with a letter outside ASCII
				uint32_t code_point = 0;
				const size_t length = identifier_character(tokenizer.current_line, tokenizer.column_number, true, &code_point);
				if (length > 0) {
					state = State::identifier;
					result_type = TokenType::IDENTIFIER;
					for (size_t i = 0; i < length; ++i) {
						next_char(tokenizer, input_stream);
					}
					goto switch_start;
				}
				/*
				 * Anything else: a character outside ASCII is taken whole, so it's reported once, saying what it is;
				 * bytes that aren't UTF-8, already reported (E2008), one at a time
				 */
				const size_t bytes = std::max<size_t>(utf8::decode(tokenizer.current_line, tokenizer.column_number, code_point), 1);
				const uint16_t column = tokenizer.column_number;
				state = State::invalid;
				for (size_t i = 0; i < bytes; ++i) {
					next_char(tokenizer, input_stream);
				}
				if (bytes > 1) {
					report_error(ErrorCode::E2006, file_path, tokenizer.line_number, column,
						std::format("U+{:04X} can't start a name, and isn't an operator", code_point));
				}
				else {
					report_error(ErrorCode::E2006, file_path, tokenizer.line_number, tokenizer.column_number);
				}
				goto switch_start;
			}
			}
			break;
		case State::tilde:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_BITWISE_XOR;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::OPERATOR_BITWISE_XOR;
				break;
			}
			break;
		}

		switch (result_type) {
		case TokenType::ANNOTATION:
		case TokenType::COMMENT_BLOCK:
		case TokenType::COMMENT_LINE:
		case TokenType::DIRECTIVE:
		case TokenType::IDENTIFIER:
		case TokenType::LITERAL_CHAR:
		case TokenType::LITERAL_INTEGER:
		case TokenType::LITERAL_FLOATING_POINT:
		case TokenType::LITERAL_IMAGINARY:
		case TokenType::LITERAL_STRING:
		case TokenType::PIPE_REORDER_IDENTIFIER:
		{
			size_t first_position = 0;
			if (start_line == tokenizer.line_number) {
				first_position = start_column;
			}
			size_t remainder_count = static_cast<size_t>(tokenizer.column_number) - first_position;
			*token_contents += tokenizer.current_line.substr(first_position, remainder_count);
		}
			break;
		
		case TokenType::END_OF_FILE:
		case TokenType::INVALID:
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
		case TokenType::KEYWORD_FALSE:
		case TokenType::KEYWORD_FN:
		case TokenType::KEYWORD_FOR:
		case TokenType::KEYWORD_IF:
		case TokenType::KEYWORD_COMPUTE:
		case TokenType::KEYWORD_GIVE:
		case TokenType::KEYWORD_IS_ERROR:
		case TokenType::KEYWORD_IS_NONE:
		case TokenType::KEYWORD_IS_OK:
		case TokenType::KEYWORD_IS_SOME:
		case TokenType::KEYWORD_LOOP:
		case TokenType::KEYWORD_MATCH:
		case TokenType::KEYWORD_MUT:
		case TokenType::KEYWORD_NULL:
		case TokenType::KEYWORD_OR_BREAK:
		case TokenType::KEYWORD_OR_CONTINUE:
		case TokenType::KEYWORD_OR_ELSE:
		case TokenType::KEYWORD_OR_RETURN:
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
		case TokenType::START_OF_FILE:
		case TokenType::SYM_AMPERSAND:
		case TokenType::SYM_ARROW_DOUBLE:
		case TokenType::SYM_ARROW_SINGLE:
		case TokenType::SYM_COLON:
		case TokenType::SYM_COMMA:
		case TokenType::SYM_DOT:
		case TokenType::SYM_ELLIPSIS:
		case TokenType::SYM_GT:
		case TokenType::SYM_LBRACE:
		case TokenType::SYM_LBRACK:
		case TokenType::SYM_LPAREN:
		case TokenType::SYM_LT:
		case TokenType::SYM_QUESTION:
		case TokenType::SYM_RBRACE:
		case TokenType::SYM_RBRACK:
		case TokenType::SYM_RPAREN:
		case TokenType::SYM_UNDERSCORE:
		case TokenType::SYM_UNINITIALIZED:
			string_alloc.delete_object(token_contents);
			token_contents = nullptr;
			break;
		}

		if (result_type == TokenType::IDENTIFIER && token_contents) {
			// A name has one spelling: NFKC's, which an ASCII one always is (E2011)
			const std::string_view name(token_contents->data(), token_contents->size());
			if (std::any_of(name.begin(), name.end(), [](char c) { return static_cast<unsigned char>(c) >= 0x80; })) {
				const std::string normalized = identifier_nfkc(name);
				if (normalized != name) {
					report_error(ErrorCode::E2011, file_path, start_line, start_column,
						std::format("write it as \"{}\", its NFKC form, so it's spelled one way", normalized));
				}
			}
			std::optional<TokenType> maybe_token = keyword(*token_contents);
			// A keyword keeps its text, since it can still be a name where only a name can go
			if (maybe_token) {
				result_type = *maybe_token;
			}
		}

		InternedString interned_contents = intern(token_contents);
		
		if (token_contents != nullptr) {
			string_alloc.delete_object(token_contents);
			token_contents = nullptr;
		}

		return Token{ result_type, start_column, start_line, interned_contents };
	}

	void lex_file(const std::string& file_path, MyVector<Token>& output,
		Allocator<> string_alloc, bool include_comments) {

		// Binary, so the lexer sees the file's own bytes, CRLF included, whatever the system's text mode does
		std::ifstream input;
		input.open(file_path, std::ios::binary);

		if (!input.is_open()) {
			report_error(ErrorCode::E1000, file_path, 0, 0);
			return;
		}

		lex(input, output, string_alloc, file_path, include_comments);
	}

	void lex(std::istream& input_stream, MyVector<Token>& output,
		Allocator<> string_alloc, std::string_view file_path,
		bool include_comments) {

		Tokenizer tokenizer{};
		read_line(input_stream, tokenizer.current_line);
		// A byte order mark, which says the file is UTF-8, isn't part of the text
		if (tokenizer.current_line.starts_with("\xEF\xBB\xBF")) {
			tokenizer.current_line.erase(0, 3);
		}
		check_line(tokenizer, tokenizer.current_line);

		while (true) {
			Token next_token = next(tokenizer, input_stream, string_alloc, file_path);
			if (!include_comments && (next_token.type == TokenType::COMMENT_BLOCK
				|| next_token.type == TokenType::COMMENT_LINE)) {
				/*
				 * The text stays interned: interned strings are shared, so another file being lexed
				 * at the same time may hold the same comment's text.
				 */
				next_token.value = nullptr;
				continue;
			}
			output.push_back(next_token);
			if (next_token.type == TokenType::END_OF_FILE) {
				break;
			}
		}
	}
}
