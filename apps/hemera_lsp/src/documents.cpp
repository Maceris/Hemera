#include "documents.h"

#include <algorithm>

#include "uri.h"

namespace hemera::lsp {

	LineIndex::LineIndex(std::string_view text) : text(text) {
		starts.push_back(0);
		for (size_t i = 0; i < text.size(); ++i) {
			if (text[i] == '\n' || text[i] == '\r') {
				ends.push_back(i);
				if (text[i] == '\r' && i + 1 < text.size() && text[i + 1] == '\n') {
					++i;
				}
				starts.push_back(i + 1);
			}
		}
		ends.push_back(text.size());
	}

	uint32_t LineIndex::line_count() const {
		return static_cast<uint32_t>(starts.size());
	}

	std::string_view LineIndex::line(uint32_t line) const {
		if (line >= starts.size()) {
			return {};
		}
		return std::string_view(text).substr(starts[line], ends[line] - starts[line]);
	}

	// How many bytes the UTF-8 character starting with lead takes: 1 for a byte that can't start one
	static size_t utf8_length(unsigned char lead) {
		if (lead >= 0xF0 && lead <= 0xF7) {
			return 4;
		}
		if (lead >= 0xE0) {
			return lead <= 0xEF ? 3 : 1;
		}
		return lead >= 0xC0 ? 2 : 1;
	}

	uint32_t LineIndex::character(uint32_t line, uint32_t byte, Encoding encoding) const {
		const std::string_view text_of_line = this->line(line);
		const size_t end = std::min<size_t>(byte, text_of_line.size());
		if (Encoding::UTF8 == encoding) {
			return static_cast<uint32_t>(end);
		}
		uint32_t units = 0;
		for (size_t i = 0; i < end;) {
			const size_t length = utf8_length(static_cast<unsigned char>(text_of_line[i]));
			// Past the end it's broken, so its bytes count one each
			bool whole = i + length <= text_of_line.size();
			for (size_t j = 1; whole && j < length; ++j) {
				whole = (static_cast<unsigned char>(text_of_line[i + j]) & 0xC0) == 0x80;
			}
			if (!whole) {
				++units;
				++i;
				continue;
			}
			units += length == 4 ? 2 : 1;
			i += length;
		}
		return units;
	}

	std::string Documents::key_of(std::string_view uri) const {
		const std::string path = path_from_uri(uri);
		return path.empty() ? std::string(uri) : path_key(path);
	}

	void Documents::open(std::string uri, std::string text, int64_t version) {
		std::string key = key_of(uri);
		std::string path = path_from_uri(uri);
		documents[std::move(key)] = Document{ std::move(uri), std::move(path), std::move(text), version };
	}

	void Documents::change(std::string_view uri, std::string text, int64_t version) {
		auto found = documents.find(key_of(uri));
		if (found != documents.end()) {
			found->second.text = std::move(text);
			found->second.version = version;
		}
	}

	void Documents::close(std::string_view uri) {
		documents.erase(key_of(uri));
	}

	const Document* Documents::find_uri(std::string_view uri) const {
		auto found = documents.find(key_of(uri));
		return found != documents.end() ? &found->second : nullptr;
	}

	const Document* Documents::find_path(std::string_view path) const {
		auto found = documents.find(path_key(path));
		return found != documents.end() ? &found->second : nullptr;
	}

	const std::map<std::string, Document>& Documents::all() const {
		return documents;
	}
}
