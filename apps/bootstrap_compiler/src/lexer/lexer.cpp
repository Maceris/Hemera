#include <format>
#include <fstream>

#include "lexer/lexer.h"
#include "util/logger.h"

namespace hemera::lexer {

	void lex_line(const std::string& line, MyVector<Token> output) {
		if (line.empty()) {//TODO(ches) actually lex things
			return;
		}
	}

	void lex(const std::string& file_path, MyVector<Token> output) {
		std::ifstream input;
		input.open(file_path);

		if (!input.is_open()) {
			LOG_ERROR(std::format("Cannot find file ", file_path));
			//TODO(ches) I think this is a compiler error
			return;
		}

		std::string line;
		//TODO(ches) eh
		while (std::getline(input, line)) {
			lex_line(line, output);
		}
	}
}