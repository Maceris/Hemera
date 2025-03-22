#include <concepts>
#include <format>
#include <fstream>
#include <limits>
#include <optional>

#include "error/reporting.h"
#include "lexer/lexer.h"
#include "util/logger.h"

namespace hemera::lexer {
#if 0
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
		if (identifier.compare("_") == 0) {
			return TokenType::KEYWORD_UNDERSCORE;
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
		return {};
	}
#endif
	enum class State {
		start,
		end,
		invalid,
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


	static Token next(Tokenizer& tokenizer, std::ifstream& input_stream) {
		switch (tokenizer.state) {
		case State::start:
			switch (next_char(tokenizer, input_stream)) {
			case 0:
				tokenizer.state = State::end;
				return Token{ TokenType::END_OF_FILE, tokenizer.column_number,
					tokenizer.line_number };
			default:
				tokenizer.state = State::invalid;
			}
			break;
		case State::end:
			break;
		case State::invalid:

			break;
		}

		//TODO(ches) tokenize
		return Token{ TokenType::END_OF_FILE, tokenizer.column_number,
			tokenizer.line_number };
	}

	void lex(const std::string& file_path, MyVector<Token> output) {
		std::ifstream input;
		input.open(file_path);

		if (!input.is_open()) {
			report_error(ErrorCode::E1000, file_path, 0, 0);
			return;
		}

		Tokenizer tokenizer{};
		std::getline(input, tokenizer.current_line);

		while (true) {
			Token next_token = next(tokenizer, input);
			if (next_token.type == TokenType::END_OF_FILE) {
				break;
			}
			output.push_back(next_token);
		}

	}
}