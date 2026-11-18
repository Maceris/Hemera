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

	/*
	 * Offsets between the text a check read and the text now, through the one change between them (changed_span),
	 * worked out once, for many offsets
	 */
	class Moved {
	public:
		Moved(std::string_view then_text, std::string_view now_text) : change(changed_span(then_text, now_text)) {}

		// Where an offset in the text the check read is now; empty if it's in what changed
		std::optional<size_t> forward(size_t offset) const {
			if (!change.has_value() || offset < change->start) {
				return offset;
			}
			if (offset >= change->end) {
				return offset - change->end + change->start + change->text.size();
			}
			return std::nullopt;
		}

		// Where an offset now was in the text the check read; empty if it's in what changed
		std::optional<size_t> back(size_t offset) const {
			if (!change.has_value() || offset < change->start) {
				return offset;
			}
			if (offset >= change->start + change->text.size()) {
				return offset - change->start - change->text.size() + change->end;
			}
			return std::nullopt;
		}

	private:
		std::optional<TextChange> change;
	};

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
