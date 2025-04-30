#include <concepts>
#include <format>
#include <limits>
#include <optional>

#include "error/reporting.h"
#include "lexer/lexer.h"
#include "util/logger.h"

namespace hemera::lexer {
	static std::optional<TokenType> get_reserved_identifier(std::string_view identifier) {
		if (identifier.compare("alias") == 0) {
			return TokenType::KEYWORD_ALIAS;
		}
		if (identifier.compare("all") == 0) {
			return TokenType::KEYWORD_ALL;
		}
		if (identifier.compare("as") == 0) {
			return TokenType::KEYWORD_AS;
		}
		if (identifier.compare("auto_cast") == 0) {
			return TokenType::KEYWORD_AUTO_CAST;
		}
		if (identifier.compare("bit_cast") == 0) {
			return TokenType::KEYWORD_BIT_CAST;
		}
		if (identifier.compare("break") == 0) {
			return TokenType::KEYWORD_BREAK;
		}
		if (identifier.compare("case") == 0) {
			return TokenType::KEYWORD_CASE;
		}
		if (identifier.compare("cast") == 0) {
			return TokenType::KEYWORD_CAST;
		}
		if (identifier.compare("context") == 0) {
			return TokenType::KEYWORD_CONTEXT;
		}
		if (identifier.compare("continue") == 0) {
			return TokenType::KEYWORD_CONTINUE;
		}
		if (identifier.compare("defer") == 0) {
			return TokenType::KEYWORD_DEFER;
		}
		if (identifier.compare("distinct") == 0) {
			return TokenType::KEYWORD_DISTINCT;
		}
		if (identifier.compare("else") == 0) {
			return TokenType::KEYWORD_ELSE;
		}
		if (identifier.compare("enum") == 0) {
			return TokenType::KEYWORD_ENUM;
		}
		if (identifier.compare("false") == 0) {
			return TokenType::KEYWORD_FALSE;
		}
		if (identifier.compare("fn") == 0) {
			return TokenType::KEYWORD_FN;
		}
		if (identifier.compare("for") == 0) {
			return TokenType::KEYWORD_FOR;
		}
		if (identifier.compare("if") == 0) {
			return TokenType::KEYWORD_IF;
		}
		if (identifier.compare("import") == 0) {
			return TokenType::KEYWORD_IMPORT;
		}
		if (identifier.compare("in") == 0) {
			return TokenType::KEYWORD_IN;
		}
		if (identifier.compare("is_none") == 0) {
			return TokenType::KEYWORD_IS_NONE;
		}
		if (identifier.compare("is_some") == 0) {
			return TokenType::KEYWORD_IS_SOME;
		}
		if (identifier.compare("loop") == 0) {
			return TokenType::KEYWORD_LOOP;
		}
		if (identifier.compare("match") == 0) {
			return TokenType::KEYWORD_MATCH;
		}
		if (identifier.compare("mut") == 0) {
			return TokenType::KEYWORD_MUT;
		}
		if (identifier.compare("null") == 0) {
			return TokenType::KEYWORD_NULL;
		}
		if (identifier.compare("or_break") == 0) {
			return TokenType::KEYWORD_OR_BREAK;
		}
		if (identifier.compare("or_continue") == 0) {
			return TokenType::KEYWORD_OR_CONTINUE;
		}
		if (identifier.compare("or_else") == 0) {
			return TokenType::KEYWORD_OR_ELSE;
		}
		if (identifier.compare("or_return") == 0) {
			return TokenType::KEYWORD_OR_RETURN;
		}
		if (identifier.compare("package") == 0) {
			return TokenType::KEYWORD_PACKAGE;
		}
		if (identifier.compare("return") == 0) {
			return TokenType::KEYWORD_RETURN;
		}
		if (identifier.compare("struct") == 0) {
			return TokenType::KEYWORD_STRUCT;
		}
		if (identifier.compare("switch") == 0) {
			return TokenType::KEYWORD_SWITCH;
		}
		if (identifier.compare("true") == 0) {
			return TokenType::KEYWORD_TRUE;
		}
		if (identifier.compare("union") == 0) {
			return TokenType::KEYWORD_UNION;
		}
		if (identifier.compare("using") == 0) {
			return TokenType::KEYWORD_USING;
		}
		if (identifier.compare("void") == 0) {
			return TokenType::KEYWORD_VOID;
		}
		if (identifier.compare("while") == 0) {
			return TokenType::KEYWORD_WHILE;
		}
		if (identifier.compare("with") == 0) {
			return TokenType::KEYWORD_WITH;
		}
		return {};
	}

	static bool next_line(Tokenizer& tokenizer, std::istream& input_stream) {
		if (!std::getline(input_stream, tokenizer.current_line)) {
			return false;
		}
		tokenizer.column_number = 0;
		tokenizer.line_number += 1;
		return true;
	}

	static char peek_char(Tokenizer& tokenizer) {
		size_t next_index = static_cast<size_t>(tokenizer.column_number);
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

	Token next(Tokenizer& tokenizer, std::istream& input_stream,
		Allocator<> string_alloc) {

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
				next_char(tokenizer, input_stream, start_line, start_column, token_contents);
				goto switch_start;
			case 0:
			case '\n':
			default:
				result_type = TokenType::INVALID;
				goto switch_start;
			}
			break;
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
				break;
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
				goto switch_start;
			default:
				state = State::literal_char;
				goto switch_start;
			}
			break;
		case State::literal_string:
			switch (next_char(tokenizer, input_stream)) {
			case '"':
				break;
			case '\\':
				state = State::literal_string_backslash;
				break;
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
				goto switch_start;
			default:
				goto switch_start;
			}
			break;
		case State::literal_string_backslash:
			switch (next_char(tokenizer, input_stream)) {
			case 0:
			case '\n':
				state = State::invalid;
				goto switch_start;
			default:
				state = State::literal_string;
				goto switch_start;
			}
			break;
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
			default:
				result_type = TokenType::OPERATOR_MINUS;
				break;
			}
			break;
		case State::multiline_string_line:
			switch (next_char(tokenizer, input_stream, start_line, start_column, token_contents)) {
			case 0:
				state = State::invalid;
				goto switch_start;
			case '\n':
				break;
			case '\r':
				if (peek_char(tokenizer) != '\n') {
					state = State::invalid;
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
				break;
			case ' ':
			case '\n':
			case '\r':
			case '\t':
				next_char(tokenizer, input_stream);
				start_column += 1;
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
			default:
				state = State::invalid;
				next_char(tokenizer, input_stream);
				break;
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
		case TokenType::KEYWORD_ALIAS:
		case TokenType::KEYWORD_ALL:
		case TokenType::KEYWORD_AS:
		case TokenType::KEYWORD_AUTO_CAST:
		case TokenType::KEYWORD_BIT_CAST:
		case TokenType::KEYWORD_BREAK:
		case TokenType::KEYWORD_CASE:
		case TokenType::KEYWORD_CAST:
		case TokenType::KEYWORD_CONTEXT:
		case TokenType::KEYWORD_CONTINUE:
		case TokenType::KEYWORD_DEFER:
		case TokenType::KEYWORD_DISTINCT:
		case TokenType::KEYWORD_ELSE:
		case TokenType::KEYWORD_ENUM:
		case TokenType::KEYWORD_FALSE:
		case TokenType::KEYWORD_FN:
		case TokenType::KEYWORD_FOR:
		case TokenType::KEYWORD_IF:
		case TokenType::KEYWORD_IMPORT:
		case TokenType::KEYWORD_IN:
		case TokenType::KEYWORD_IS_NONE:
		case TokenType::KEYWORD_IS_SOME:
		case TokenType::KEYWORD_LOOP:
		case TokenType::KEYWORD_MATCH:
		case TokenType::KEYWORD_MUT:
		case TokenType::KEYWORD_NULL:
		case TokenType::KEYWORD_OR_BREAK:
		case TokenType::KEYWORD_OR_CONTINUE:
		case TokenType::KEYWORD_OR_ELSE:
		case TokenType::KEYWORD_OR_RETURN:
		case TokenType::KEYWORD_PACKAGE:
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
		default:
			string_alloc.delete_object(token_contents);
			token_contents = nullptr;
			break;
		}

		if (result_type == TokenType::IDENTIFIER && token_contents) {
			std::optional<TokenType> maybe_token = get_reserved_identifier(*token_contents);
			if (maybe_token) {
				result_type = *maybe_token;
				string_alloc.delete_object(token_contents);
				token_contents = nullptr;
			}
		}

		return Token{ result_type, start_column, start_line, token_contents };
	}

	void lex_file(const std::string& file_path, MyVector<Token>& output,
		Allocator<> string_alloc) {

		std::ifstream input;
		input.open(file_path);

		if (!input.is_open()) {
			report_error(ErrorCode::E1000, file_path, 0, 0);
			return;
		}

		lex(input, output, string_alloc);
	}

	void lex(std::istream& input_stream, MyVector<Token>& output,
		Allocator<> string_alloc) {

		Tokenizer tokenizer{};
		std::getline(input_stream, tokenizer.current_line);

		while (true) {
			Token next_token = next(tokenizer, input_stream, string_alloc);
			output.push_back(next_token);
			if (next_token.type == TokenType::END_OF_FILE) {
				break;
			}
			if (next_token.type == TokenType::INVALID) {
				break;
			}
		}
	}
}