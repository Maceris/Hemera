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
	};

	struct Tokenizer {
		const std::string& buffer;
		uint16_t index;
		const char _padding[6] = { 0 };

		Tokenizer(const std::string& buffer)
			: buffer{ buffer }
			, index{ 0 }
		{}
		Tokenizer(const Tokenizer&) = delete;
		Tokenizer(Tokenizer&&) = default;
		Tokenizer& operator=(const Tokenizer&) = delete;
		Tokenizer& operator=(Tokenizer&&) = delete;
	};

	static Token next(Tokenizer& tokenizer, const uint32_t line_number) {
		//State state = State::start;

		if (tokenizer.index >= tokenizer.buffer.length()) {
			return Token{ TokenType::END_OF_FILE, tokenizer.index, line_number};
		}
		//TODO(ches) tokenize
		return Token{ TokenType::END_OF_FILE, tokenizer.index, line_number };
	}

	void lex_line(const std::string& line, const uint32_t line_number,
		MyVector<Token> output) {
		if (line.empty()) {
			return;
		}
		
		const size_t line_length = line.length();

		for (size_t i = 0; i < line_length; ++i) {
			Tokenizer line_tokenizer{ line };
			
			for (size_t safety_net = 0; ; ++safety_net) {
				if (safety_net > std::numeric_limits<decltype(Token::column_number)>::max()) {
					LOG_ERROR("Too many tokens on one line");
					break;
				}
				Token next_token = next(line_tokenizer, line_number);
				if (next_token.type == TokenType::END_OF_FILE) {
					break;
				}
				output.push_back(next_token);
			}

		}

	}

	void lex(const std::string& file_path, MyVector<Token> output) {
		std::ifstream input;
		input.open(file_path);

		if (!input.is_open()) {
			report_error(ErrorCode::E1000, file_path, 0, 0);
			return;
		}

		std::string line;
		uint32_t line_number = 1;

		while (std::getline(input, line)) {
			lex_line(line, line_number, output);
			line_number += 1;
		}
	}
}