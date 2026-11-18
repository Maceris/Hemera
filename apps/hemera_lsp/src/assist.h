#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "completion.h"
#include "documents.h"
#include "index.h"
#include "parsing.h"

#include "llvm/Support/JSON.h"

// Signature help, workspace symbols and inlay hints (docs/editor.md), from the name index and the text as it is now.
namespace hemera::lsp {

	/*
	 * workspace/symbol's answer: the functions, types and constants, then the fields, members and variants, of each
	 * index's tables whose name has query's characters in order, ignoring case, as SymbolInformation, each in its file as
	 * the check read it. Names starting with query first, then those under one of workspace_folders, then the rest, at
	 * most limit of them. Locals and parameters aren't symbols, nor what inserted code made.
	 */
	llvm::json::Array workspace_symbols(std::string_view query, const std::vector<CompletionTables*>& tables,
		const std::vector<std::string>& workspace_folders, Encoding encoding, size_t limit = 500);

	// Where signature help, or inlay hints, are asked for, and what they're answered from.
	struct AssistRequest {
		// The document's path on disk, with / throughout, and its text now
		std::string file;
		std::string_view text;
		// Its text as the index's check read it, which the index's offsets in it count in; text when it's the same
		std::string_view checked_text;
		// Its text lexed and parsed now; tokens are what's read, so a text that doesn't parse is fine. May be null
		const ParsedDocument* parsed = nullptr;
		Encoding encoding = Encoding::UTF16;
		// The cursor, for signature help; the range, for inlay hints: byte offsets in text
		size_t offset = 0;
		size_t end = 0;
	};

	/*
	 * textDocument/signatureHelp's answer: for the call whose ( is the nearest open one before the cursor, what it
	 * calls, through the index, as SignatureHelp with one signature, like name(by : int, factor : int = 3) -> int,
	 * with its doc comment's brief, each parameter's @param text, and the parameter the cursor's argument goes to: by
	 * its name in a named argument, else by the commas before it. A value of function type has its type's
	 * parameters, which have no names. Null when the cursor isn't in a call, or what it calls isn't known.
	 */
	llvm::json::Value signature_help(const AssistRequest& request, CompletionTables* tables);

	/*
	 * textDocument/inlayHint's answer for request's range: after each local's name declared without a written type, like
	 * x := 0, a loop's variables or a match's bindings, its type, as the index has it, cut to 40 characters with the
	 * whole type in its tooltip. Its offsets are moved from the checked text as other answers are; one in what changed
	 * has none.
	 */
	llvm::json::Array inlay_hints(const AssistRequest& request, const LoadedIndex& index);
}
