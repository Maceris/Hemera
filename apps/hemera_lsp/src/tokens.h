#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>

#include "documents.h"
#include "index.h"
#include "parsing.h"

#include "llvm/Support/JSON.h"

// textDocument/semanticTokens (docs/editor.md, Semantic Highlighting): each name colored by what it names.
namespace hemera::lsp {

	/*
	 * The legend the server gives in its capabilities: the token types and modifiers by name, in the order a token's
	 * numbers count them in
	 */
	llvm::json::Object semantic_tokens_legend();

	// What a request for a document's tokens needs.
	struct TokensRequest {
		// The document's path on disk, with / throughout, which the index's files are matched with by path_key
		std::string file;
		// Its text now, which the tokens' positions are in
		std::string_view text;
		/*
		 * Its text as the check read it, which the index's offsets are in; text when the check read it as it is now.
		 * Offsets in what changed between them have no token.
		 */
		std::string_view checked_text;
		// Its parse now, for package names in code, and the declarations of a file the index doesn't have; may be null
		const ParsedDocument* parsed = nullptr;
		// Where base's files and std's are, with / throughout, for what's defaultLibrary; empty when unknown
		std::string base_folder;
		std::string std_folder;
		Encoding encoding = Encoding::UTF16;
		// Only the tokens from start to end, byte offsets in text, for semanticTokens/range; every token without
		std::optional<size_t> start;
		std::optional<size_t> end;
	};

	/*
	 * A document's tokens, as SemanticTokens: {"data": [...]}, five numbers a token, its line and start relative to the
	 * token before, its length, its type and its modifiers, in request.encoding. From index, when it has the file: each
	 * use and each declaration's own name, as the declaration's kind says, and each import's name; from the parse, each
	 * package name before a ., and when the index doesn't have the file, its own top-level declarations and their fields,
	 * members and variants. Where two would overlap, the index's wins. index may be null.
	 */
	llvm::json::Object semantic_tokens(const TokensRequest& request, const LoadedIndex* index);
}
