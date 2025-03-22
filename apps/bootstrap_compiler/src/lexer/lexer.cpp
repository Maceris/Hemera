#include <concepts>
#include <format>
#include <fstream>
#include <limits>

#include "error/reporting.h"
#include "lexer/lexer.h"
#include "util/logger.h"

namespace hemera::lexer {

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