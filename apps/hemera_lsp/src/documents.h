#pragma once

#include <cstdint>
#include <map>
#include <string>
#include <string_view>
#include <vector>

namespace hemera::lsp {

	/*
	 * What the client's positions count a line's characters in, chosen when it starts (initialize): UTF-8's bytes, as
	 * the compiler counts its columns, or UTF-16's code units, which every client takes.
	 */
	enum class Encoding {
		UTF8,
		UTF16,
	};

	/*
	 * Where a text's lines start, for turning the compiler's byte columns into the client's characters. A line ends at
	 * \n, \r\n or \r, as the Language Server Protocol counts them.
	 */
	class LineIndex {
	public:
		explicit LineIndex(std::string_view text);

		// How many lines: 1 for an empty text, and one more after a text's last line end
		uint32_t line_count() const;

		// Line line's text, counting from 0, without its line end; empty past the last line
		std::string_view line(uint32_t line) const;

		/*
		 * A byte offset in line line (both counting from 0) in encoding's units. An offset past the line's end is
		 * its end; one inside a character counts it as begun. Bytes that aren't UTF-8 count one unit each.
		 */
		uint32_t character(uint32_t line, uint32_t byte, Encoding encoding) const;

	private:
		std::string text;
		// Each line's first byte, then each line's end, before its line end
		std::vector<size_t> starts;
		std::vector<size_t> ends;
	};

	// A document the client has open, with what it holds now, which may not be saved.
	struct Document {
		// The URI as the client named it, which diagnostics for it are published under
		std::string uri;
		// The path it names, with / throughout (path_from_uri)
		std::string path;
		std::string text;
		// The client's version of it, from didOpen and each didChange
		int64_t version = 0;
	};

	/*
	 * The documents the client has open, by path_key, so one the client named one way is found from a diagnostic
	 * the compiler gives another.
	 */
	class Documents {
	public:
		// Opened or replaced; a URI that isn't a file: one is kept too, but has no path and is never checked
		void open(std::string uri, std::string text, int64_t version);
		// Its whole text replaced, from a full-text didChange; nothing if it isn't open
		void change(std::string_view uri, std::string text, int64_t version);
		void close(std::string_view uri);

		// The open document uri names, or null
		const Document* find_uri(std::string_view uri) const;
		// The open document at path, as the compiler names it, or null
		const Document* find_path(std::string_view path) const;

		const std::map<std::string, Document>& all() const;

	private:
		// By path_key of their path, or by URI for one with no path
		std::map<std::string, Document> documents;

		std::string key_of(std::string_view uri) const;
	};
}
