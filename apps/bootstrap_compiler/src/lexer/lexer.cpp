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
		if (identifier.compare("const") == 0) {
			return TokenType::KEYWORD_CONST;
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
		start,
		end,
		identifier,
		integer,
		invalid,
		string_literal,
	};

	struct Tokenizer {
		std::string current_line;
		uint32_t line_number;
		State state;
		uint16_t column_number;
		const char _padding[6] = { 0 };

		Tokenizer()
			: current_line{}
			, line_number{ 1 }
			, state{ State::start }
			, column_number{ 0 }
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

	static char next_char(Tokenizer& tokenizer, std::ifstream& input_stream) {
		if (tokenizer.column_number >= tokenizer.current_line.length()) {
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

		//TODO(ches) finish tokenizing

		switch_start:
		switch (tokenizer.state) {
		case State::start:
			switch (next_char(tokenizer, input_stream)) {
			case 0:
				tokenizer.state = State::end;
				return Token{ TokenType::END_OF_FILE, start_column, start_line };
			case ' ':
			case '\n':
			case '\r':
			case '\t':
				tokenizer.column_number += 1;
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
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
				result_type = TokenType::LITERAL_NUMBER;
				tokenizer.state = State::integer;
				tokenizer.column_number += 1;
				goto switch_start;
			case '_':
				result_type = TokenType::SYM_UNDERSCORE;
				break;
			case '"':
				tokenizer.state = State::string_literal;
				result_type = TokenType::LITERAL_STRING;
				goto switch_start;
			default:
				tokenizer.state = State::invalid;
			}
			break;
		case State::end:
			break;
		case State::invalid:
			break;
		case State::identifier:
			break;
		}

		//TODO(ches) get string form when relevant

		MyString* result_string;
		switch (result_type) {
		case TokenType::IDENTIFIER:
		case TokenType::LITERAL_NUMBER:
			result_string = string_alloc.new_object<MyString>("generate a string here");
			break;
		
		case TokenType::END_OF_FILE:
		case TokenType::INVALID:
		case TokenType::KEYWORD_ALIAS:
		case TokenType::KEYWORD_ALL:
		case TokenType::KEYWORD_AS:
		case TokenType::KEYWORD_BREAK:
		case TokenType::KEYWORD_CASE:
		case TokenType::KEYWORD_CONST:
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
		case TokenType::OPERATOR_ASSIGN_DIV:
		case TokenType::OPERATOR_ASSIGN_MOD:
		case TokenType::OPERATOR_ASSIGN_MUL:
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
			result_string = nullptr;
			break;
		}

		if (result_type == TokenType::IDENTIFIER) {
			std::optional<TokenType> maybe_token = get_reserved_identifier(*result_string);
			if (maybe_token) {
				result_type = *maybe_token;
				result_string = nullptr;
			}
		}

		return Token{ result_type, start_column, start_line };
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
			if (next_token.type == TokenType::END_OF_FILE) {
				break;
			}
			output.push_back(next_token);
		}

	}
}