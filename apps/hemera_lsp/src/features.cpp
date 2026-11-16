#include "features.h"

#include <algorithm>

namespace hemera::lsp {

	using llvm::json::Object;
	using llvm::json::Value;

	// Whether offset is inside a UTF-8 character, or between a \r and its \n, so not a place a position can name
	static bool inside_character(std::string_view text, size_t offset) {
		if (offset == 0 || offset >= text.size()) {
			return false;
		}
		return (static_cast<unsigned char>(text[offset]) & 0xC0) == 0x80 || (text[offset - 1] == '\r' && text[offset] == '\n');
	}

	std::optional<TextChange> changed_span(std::string_view old_text, std::string_view new_text) {
		if (old_text == new_text) {
			return std::nullopt;
		}
		const size_t shorter = std::min(old_text.size(), new_text.size());
		size_t start = 0;
		while (start < shorter && old_text[start] == new_text[start]) {
			++start;
		}
		// Back to where a character starts, which is the same place in both
		while (inside_character(old_text, start) || inside_character(new_text, start)) {
			--start;
		}
		// The common end, not reaching back past start in either
		size_t common_end = 0;
		while (common_end < shorter - start && old_text[old_text.size() - 1 - common_end] == new_text[new_text.size() - 1 - common_end]) {
			++common_end;
		}
		while (common_end > 0 && (inside_character(old_text, old_text.size() - common_end)
			|| inside_character(new_text, new_text.size() - common_end))) {
			--common_end;
		}
		return TextChange{ start, old_text.size() - common_end,
			std::string(new_text.substr(start, new_text.size() - common_end - start)) };
	}

	Value position_at(const LineIndex& index, size_t offset, Encoding encoding) {
		const auto [line, byte] = index.line_and_byte(offset);
		return Object{ { "line", line }, { "character", index.character(line, byte, encoding) } };
	}
}
