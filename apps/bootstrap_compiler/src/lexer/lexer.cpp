#include <concepts>
#include <format>
#include <fstream>
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
		if (identifier.compare("break") == 0) {
			return TokenType::KEYWORD_BREAK;
		}
		if (identifier.compare("case") == 0) {
			return TokenType::KEYWORD_CASE;
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
		if (identifier.compare("do") == 0) {
			return TokenType::KEYWORD_DO;
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

	enum class State {
		ampersand,
		annotation,
		asterisk,
		backslash,
		block_comment,
		caret,
		colon,
		comma,
		end,
		equal,
		exclamation,
		expect_newline,
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
		period,
		period_2,
		pipe,
		plus,
		question_mark,
		r_angle_bracket,
		r_angle_bracket_2,
		slash,
		start,
	};

	struct Tokenizer {
		MyString current_line;
		uint32_t line_number;
		State state;
		uint16_t column_number;
		uint8_t comment_depth;
		const char _padding[5] = { 0 };

		Tokenizer()
			: current_line{}
			, line_number{ 1 }
			, state{ State::start }
			, column_number{ 0 }
			, comment_depth{ 0 }
		{}
		Tokenizer(const Tokenizer&) = delete;
		Tokenizer(Tokenizer&&) = default;
		Tokenizer& operator=(const Tokenizer&) = delete;
		Tokenizer& operator=(Tokenizer&&) = delete;
	};

	static bool next_line(Tokenizer& tokenizer, std::ifstream& input_stream) {
		if (!std::getline(input_stream, tokenizer.current_line)) {
			tokenizer.state = State::end;
			return false;
		}
		tokenizer.column_number = 0;
		tokenizer.line_number += 1;
		return true;
	}

	static char peek_char(Tokenizer& tokenizer) {
		size_t next_index = static_cast<size_t>(tokenizer.column_number) + 1;
		if (next_index >= tokenizer.current_line.length()) {
			return 0;
		}
		return tokenizer.current_line[next_index];
	}

	static char next_char(Tokenizer& tokenizer, std::ifstream& input_stream, 
		MyString* token_contents = nullptr) {
		if (tokenizer.column_number >= tokenizer.current_line.length()) {
			if (token_contents) {
				*token_contents += tokenizer.current_line;
			}

			if (!next_line(tokenizer, input_stream)) {
				return 0;
			}
		}
		if (tokenizer.column_number >= tokenizer.current_line.length()) {
			return 0;
		}
		char result = tokenizer.current_line[tokenizer.column_number];
		tokenizer.column_number += 1;
		return result;
	}

	static Token next(Tokenizer& tokenizer, std::ifstream& input_stream,
		Allocator<> string_alloc) {

		uint32_t start_line = tokenizer.line_number;
		uint16_t start_column = tokenizer.column_number;
		TokenType result_type = TokenType::END_OF_FILE;
		MyString* token_contents = string_alloc.new_object<MyString>();

		//TODO(ches) finish tokenizing

		switch_start:
		switch (tokenizer.state) {
		case State::ampersand:
			switch (peek_char(tokenizer)) {
			case '=':
				result_type = TokenType::OPERATOR_ASSIGN_BITWISE_AND;
				next_char(tokenizer, input_stream);
				break;
			default:
				result_type = TokenType::OPERATOR_BITWISE_AND;
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
				next_char(tokenizer, input_stream, token_contents);
				goto switch_start;
			default:
				break;
			}
			break;
		case State::backslash:
			switch (peek_char(tokenizer)) {
			case '\\':
				tokenizer.state = State::multiline_string_line;
				next_char(tokenizer, input_stream, token_contents);
				goto switch_start;
			case 0:
			case '\n':
			default:
				result_type = TokenType::INVALID;
				break;
			}
			break;
		case State::block_comment:
			switch (next_char(tokenizer, input_stream, token_contents)) {
			case '*':
				if (peek_char(tokenizer) == '/') {
					next_char(tokenizer, input_stream, token_contents);
					tokenizer.comment_depth -= 1;
				}
				if (tokenizer.comment_depth > 0) {
					goto switch_start;
				}
				break;
			case '/':
				if (peek_char(tokenizer) == '*') {
					next_char(tokenizer, input_stream, token_contents);
					tokenizer.comment_depth += 1;
				}
				goto switch_start;
			default:
				goto switch_start;
			}
			break;
		case State::caret:
			switch (peek_char(tokenizer)) {
			case '=':
				tokenizer.state = State::multiline_string_line;
				next_char(tokenizer, input_stream);
				break;
			case 0:
			case '\n':
			default:
				result_type = TokenType::INVALID;
				break;
			}
			break;
		case State::colon:
			result_type = TokenType::SYM_COLON;
			break;
		case State::comma:
			result_type = TokenType::SYM_COMMA;
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
			default:
				result_type = TokenType::SYM_EQ;
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
				tokenizer.state = State::start;
				next_char(tokenizer, input_stream, token_contents);
				goto switch_start;
			case 0:
			default:
				tokenizer.state = State::invalid;
				goto switch_start;
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
				next_char(tokenizer, input_stream, token_contents);
				goto switch_start;
			default:
				break;
			}
			break;
		case State::integer:
			switch (peek_char(tokenizer)) {
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
				next_char(tokenizer, input_stream, token_contents);
				goto switch_start;
			case '_':
				//NOTE(ches) just pretend underscore isn't there
				next_char(tokenizer, input_stream);
				goto switch_start;
			case '.':
				tokenizer.state = State::integer_period;
				result_type = TokenType::LITERAL_FLOATING_POINT;
				next_char(tokenizer, input_stream, token_contents);
				goto switch_start;
			case 'e':
			case 'E':
				tokenizer.state = State::integer_exponent;
				result_type = TokenType::LITERAL_FLOATING_POINT;
				next_char(tokenizer, input_stream, token_contents);
				if (peek_char(tokenizer) == '-') {
					next_char(tokenizer, input_stream, token_contents);
				}
				goto switch_start;
			default:
				break;
			}
			break;
		case State::integer_binary:
			switch (peek_char(tokenizer)) {
			case '0': case '1':
				next_char(tokenizer, input_stream, token_contents);
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
				next_char(tokenizer, input_stream, token_contents);
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
				next_char(tokenizer, input_stream, token_contents);
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
				next_char(tokenizer, input_stream, token_contents);
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
				next_char(tokenizer, input_stream, token_contents);
				goto switch_start;
			case '_':
				//NOTE(ches) just pretend underscore isn't there
				next_char(tokenizer, input_stream);
				goto switch_start;
			case 'e':
			case 'E':
				tokenizer.state = State::integer_exponent;
				LOG_ASSERT(result_type == TokenType::LITERAL_FLOATING_POINT);
				next_char(tokenizer, input_stream, token_contents);
				if (peek_char(tokenizer) == '-') {
					next_char(tokenizer, input_stream, token_contents);
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
			break;
		case State::l_angle_bracket_2:
			break;
		case State::line_comment://TODO(ches)
			break;
		case State::literal_char:
			break;
		case State::literal_char_backslash:
			break;
		case State::literal_string:
			break;
		case State::literal_string_backslash:
			break;
		case State::minus:
			break;
		case State::multiline_string_line:
			break;
		case State::percent:
			break;
		case State::period:
			break;
		case State::period_2:
			break;
		case State::pipe:
			break;
		case State::plus:
			break;
		case State::question_mark:
			break;
		case State::r_angle_bracket:
			break;
		case State::r_angle_bracket_2:
			break;
		case State::slash:
			break;
		case State::start:
			switch (next_char(tokenizer, input_stream, token_contents)) {
			case 0:
				tokenizer.state = State::end;
				return Token{ TokenType::END_OF_FILE, start_column, start_line };
			case ' ':
			case '\n':
			case '\r':
			case '\t':
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
				tokenizer.state = State::identifier;
				goto switch_start;
			case '1': case '2': case '3': case '4': case '5':
			case '6': case '7': case '8': case '9':
				result_type = TokenType::LITERAL_INTEGER;
				tokenizer.state = State::integer;
				goto switch_start;
			case '0':
				result_type = TokenType::LITERAL_INTEGER;
				tokenizer.state = State::integer;
				switch (peek_char(tokenizer)) {
				case 'x':
					tokenizer.state = State::integer_hex;
					next_char(tokenizer, input_stream, token_contents);
					break;
				case 'o':
					tokenizer.state = State::integer_octal;
					next_char(tokenizer, input_stream, token_contents);
					break;
				case 'b':
					tokenizer.state = State::integer_binary;
					next_char(tokenizer, input_stream, token_contents);
					break;
				}
				goto switch_start;
			case '_':
				result_type = TokenType::SYM_UNDERSCORE;
				break;
			case '"':
				tokenizer.state = State::literal_string;
				result_type = TokenType::LITERAL_STRING;
				goto switch_start;
			case '\'':
				tokenizer.state = State::literal_char;
				result_type = TokenType::LITERAL_CHAR;
				goto switch_start;
			case '@':
				tokenizer.state = State::annotation;
				goto switch_start;
			case '=':
				tokenizer.state = State::equal;
				goto switch_start;
			case '!':
				tokenizer.state = State::exclamation;
				goto switch_start;
			case '|':
				tokenizer.state = State::pipe;
				goto switch_start;
			case '%':
				tokenizer.state = State::percent;
				goto switch_start;
			case '*':
				tokenizer.state = State::asterisk;
				goto switch_start;
			case '+':
				tokenizer.state = State::plus;
				goto switch_start;
			case '<':
				tokenizer.state = State::l_angle_bracket;
				goto switch_start;
			case '>':
				tokenizer.state = State::r_angle_bracket;
				goto switch_start;
			case '^':
				tokenizer.state = State::caret;
				goto switch_start;
			case '.':
				tokenizer.state = State::period;
				goto switch_start;
			case '-':
				tokenizer.state = State::minus;
				goto switch_start;
			case '/':
				tokenizer.state = State::slash;
				goto switch_start;
			case '&':
				tokenizer.state = State::ampersand;
				goto switch_start;
			case '\\':
				tokenizer.state = State::backslash;
				goto switch_start;
			case '(':
				result_type = TokenType::SYM_LPAREN;
				break;
			case ')':
				result_type = TokenType::SYM_RPAREN;
				break;
			case '[':
				result_type = TokenType::SYM_LBRACK;
				break;
			case ']':
				result_type = TokenType::SYM_RBRACK;
				break;
			case '{':
				result_type = TokenType::SYM_LBRACE;
				break;
			case '}':
				result_type = TokenType::SYM_RBRACE;
				break;
			case ',':
				tokenizer.state = State::comma;
				goto switch_start;
			case ':':
				tokenizer.state = State::colon;
				goto switch_start;
			case '?':
				tokenizer.state = State::question_mark;
				goto switch_start;
			default:
				tokenizer.state = State::invalid;
			}
			break;
		}

		switch (result_type) {
		case TokenType::ANNOTATION:
		case TokenType::IDENTIFIER:
		case TokenType::LITERAL_CHAR:
		case TokenType::LITERAL_INTEGER:
		case TokenType::LITERAL_FLOATING_POINT:
		case TokenType::LITERAL_STRING:
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
		case TokenType::KEYWORD_BREAK:
		case TokenType::KEYWORD_CASE:
		case TokenType::KEYWORD_CONTEXT:
		case TokenType::KEYWORD_CONTINUE:
		case TokenType::KEYWORD_DEFER:
		case TokenType::KEYWORD_DISTINCT:
		case TokenType::KEYWORD_DO:
		case TokenType::KEYWORD_ELSE:
		case TokenType::KEYWORD_ENUM:
		case TokenType::KEYWORD_FALSE:
		case TokenType::KEYWORD_FN:
		case TokenType::KEYWORD_FOR:
		case TokenType::KEYWORD_IF:
		case TokenType::KEYWORD_IMPORT:
		case TokenType::KEYWORD_IN:
		case TokenType::KEYWORD_LOOP:
		case TokenType::KEYWORD_MATCH:
		case TokenType::KEYWORD_MUT:
		case TokenType::KEYWORD_NULL:
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
		case TokenType::OPERATOR_BITWISE_AND:
		case TokenType::OPERATOR_BITWISE_OR:
		case TokenType::OPERATOR_BITWISE_XOR:
		case TokenType::OPERATOR_DIVIDE:
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
		case TokenType::OPERATOR_QUESTION:
		case TokenType::OPERATOR_REMAINDER:
		case TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC:
		case TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL:
		case TokenType::SYM_ARROW:
		case TokenType::SYM_COLON:
		case TokenType::SYM_COMMA:
		case TokenType::SYM_DOT:
		case TokenType::SYM_EQ:
		case TokenType::SYM_GT:
		case TokenType::SYM_LBRACE:
		case TokenType::SYM_LBRACK:
		case TokenType::SYM_LPAREN:
		case TokenType::SYM_LT:
		case TokenType::SYM_QUOTE:
		case TokenType::SYM_RBRACE:
		case TokenType::SYM_RBRACK:
		case TokenType::SYM_RPAREN:
		case TokenType::SYM_SINGLE_QUOTE:
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

	void lex(const std::string& file_path, MyVector<Token> output,
		Allocator<> string_alloc) {

		std::ifstream input;
		input.open(file_path);

		if (!input.is_open()) {
			report_error(ErrorCode::E1000, file_path, 0, 0);
			return;
		}

		Tokenizer tokenizer{};
		std::getline(input, tokenizer.current_line);

		while (true) {
			Token next_token = next(tokenizer, input, string_alloc);
			//TODO(ches) if invalid token, probably bail on the file
			if (next_token.type == TokenType::END_OF_FILE) {
				break;
			}
			output.push_back(next_token);
		}

	}
}