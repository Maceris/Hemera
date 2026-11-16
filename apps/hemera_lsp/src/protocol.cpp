#include "protocol.h"

#include <cctype>
#include <charconv>
#include <format>

namespace hemera::lsp {

	// Whether name is header, in any case
	static bool header_is(std::string_view name, std::string_view header) {
		if (name.size() != header.size()) {
			return false;
		}
		for (size_t i = 0; i < name.size(); ++i) {
			if (std::tolower(static_cast<unsigned char>(name[i])) != std::tolower(static_cast<unsigned char>(header[i]))) {
				return false;
			}
		}
		return true;
	}

	static std::string_view trimmed(std::string_view text) {
		while (!text.empty() && (text.front() == ' ' || text.front() == '\t')) {
			text.remove_prefix(1);
		}
		while (!text.empty() && (text.back() == ' ' || text.back() == '\t' || text.back() == '\r')) {
			text.remove_suffix(1);
		}
		return text;
	}

	std::optional<std::string> read_message(std::istream& in) {
		std::optional<size_t> length;
		bool malformed = false;
		std::string line;
		for (;;) {
			if (!std::getline(in, line)) {
				return std::nullopt;
			}
			if (!line.empty() && line.back() == '\r') {
				line.pop_back();
			}
			if (line.empty()) {
				// The end of the headers, or blank lines before them
				if (length.has_value() || malformed) {
					break;
				}
				continue;
			}
			const size_t colon = line.find(':');
			if (colon == std::string::npos) {
				malformed = true;
				continue;
			}
			if (header_is(trimmed(std::string_view(line).substr(0, colon)), "Content-Length")) {
				const std::string_view value = trimmed(std::string_view(line).substr(colon + 1));
				size_t parsed = 0;
				const auto [end, error] = std::from_chars(value.data(), value.data() + value.size(), parsed);
				if (error != std::errc() || end != value.data() + value.size()) {
					malformed = true;
				}
				else {
					length = parsed;
				}
			}
		}
		if (malformed || !length.has_value()) {
			return std::nullopt;
		}
		std::string body(*length, '\0');
		if (*length > 0 && !in.read(body.data(), static_cast<std::streamsize>(*length))) {
			return std::nullopt;
		}
		return body;
	}

	std::string frame(std::string_view body) {
		return std::format("Content-Length: {}\r\n\r\n{}", body.size(), body);
	}
}
