#include <format>
#include <fstream>

#include "error/reporting.h"
#include "lexer/lexer.h"
#include "util/logger.h"

namespace hemera::lexer {

	void lex_line(const std::string& line, const uint32_t line_number,
		MyVector<Token> output) {
		if (line.empty()) {//TODO(ches) actually lex things
			return;
		}
		
		const size_t line_length = line.length();

		if (line_number == 0) return; //TODO(ches) remove this, working around C4100

		for (size_t i = 0; i < line_length; ++i) {

		}

	}

	void lex(const std::string& file_path, MyVector<Token> output) {
		std::ifstream input;
		input.open(file_path);

		if (!input.is_open()) {
			LOG_ERROR(std::format("Cannot find file ", file_path));
			//TODO(ches) I think this is a compiler error
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