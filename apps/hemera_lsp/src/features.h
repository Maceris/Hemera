#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>

#include "documents.h"

#include "llvm/Support/JSON.h"

// What tier 2 answers from a document's text, tokens and tree alone (docs/editor.md).
namespace hemera::lsp {

	// A change to a text: the bytes from start to end, offsets in the old text, become text.
	struct TextChange {
		size_t start = 0;
		size_t end = 0;
		std::string text;
	};

	/*
	 * The one change that makes old_text new_text: everything between their common start and common end, with
	 * neither end inside a UTF-8 character or between a \r and its \n, so it can be given as a position in any
	 * encoding. Empty when they're the same.
	 */
	std::optional<TextChange> changed_span(std::string_view old_text, std::string_view new_text);

	// A Language Server Protocol position, {line, character}, for byte offset in index's text, in encoding's units.
	llvm::json::Value position_at(const LineIndex& index, size_t offset, Encoding encoding);
}
