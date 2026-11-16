#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>

#include "documents.h"
#include "parsing.h"

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

	/*
	 * textDocument/documentSymbol's answer for a document that parsed: its top-level declarations as DocumentSymbols,
	 * functions, structs, enums, unions, aliases and constants, with a struct's fields, an enum's members and a
	 * union's variants as their children. A declaration's range runs from its doc comment, if it has one, to its last
	 * token, closing brace included; its selection range is its name. Empty for a document with no tree.
	 */
	llvm::json::Array document_symbols(const ParsedDocument& document, Encoding encoding);

	/*
	 * textDocument/foldingRange's answer, from the document's tokens alone, so a document that lexed folds whether
	 * it parsed or not: a {, [ or ( whose match is on a later line, to the line before the match's, so the match
	 * stays in sight; a block comment over several lines; two or more line comments on lines in a row; and two or
	 * more imports in a row. Lines count from 0. Empty for a document that didn't lex.
	 */
	llvm::json::Array folding_ranges(const ParsedDocument& document);
}
