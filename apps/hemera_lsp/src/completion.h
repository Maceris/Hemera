#pragma once

#include <cstddef>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "documents.h"
#include "index.h"
#include "parsing.h"

#include "llvm/Support/JSON.h"

// Completion (docs/editor.md, Completion): from the last check's index and the document's own parse, without a check.
namespace hemera::lsp {

	/*
	 * What completion looks up in an index, made from it once and kept with it: each type's members, each package's
	 * top-level declarations, and each declaration's name, read from its file's text as the index counts in it. Not
	 * for several threads at once, as names are read as they're asked for.
	 */
	class CompletionTables {
	public:
		/*
		 * Tables for index. text_of gives a file's text, by its path as the index names it, as the check read it: an open
		 * document's from the index's texts, another's from disk; empty when it can't be read.
		 */
		CompletionTables(std::shared_ptr<const LoadedIndex> index, std::function<std::string(const std::string&)> text_of);

		const LoadedIndex& index() const { return *loaded; }
		const std::shared_ptr<const LoadedIndex>& shared() const { return loaded; }

		// The fields, members or variants in the type declaration numbered type, in the order they're declared
		const std::vector<size_t>& members_of(size_t type) const;

		// The top-level functions, types and constants of the package in folder, a path_key of a folder
		const std::vector<size_t>& top_level_in(const std::string& folder) const;

		// A declaration's name, as its file has it; empty when its file can't be read
		std::string_view name_of(size_t declaration);

		// A file's text as the index counts in it, by its path
		std::string_view text_of(const std::string& file);

	private:
		std::shared_ptr<const LoadedIndex> loaded;
		std::function<std::string(const std::string&)> read;
		std::map<size_t, std::vector<size_t>> members;
		std::map<std::string, std::vector<size_t>> top_level;
		std::map<std::string, std::string> texts;
		std::vector<size_t> none;
	};

	// Where completion is asked for, and what it can answer from.
	struct CompletionRequest {
		// The document's path on disk, and its text now
		std::string file;
		std::string_view text;
		// The cursor, a byte offset in text
		size_t offset = 0;
		// The document's text as the index's check read it, which the index's offsets in it count in; text if it's the same
		std::string_view checked_text;
		// The document parsed now, its tree recovered from errors; or null
		const ParsedDocument* parsed = nullptr;
		/*
		 * The folder holding base's packages, beside the compiler, with std's and vendor's beside it; empty when it
		 * isn't known, and then imports from base:, std: and vendor: aren't completed
		 */
		std::string base_folder;
		Encoding encoding = Encoding::UTF16;
	};

	/*
	 * textDocument/completion's CompletionItems at request's cursor, from tables, which may be null when there's no index
	 * yet:
	 * - In an import's string, the packages its path can go on to: the folders in the one it names so far, std:, vendor:
	 *   and base: beside the compiler, or relative to the file.
	 * - After a ., the members of what's before it: a package's top-level declarations after an import's name, a type's
	 *   members after its name, and a value's type's after it, following each . before through fields' types, and a call's
	 *   () through what its function gives.
	 * - Elsewhere, what can be named there: the locals declared before it in its declaration, those since the check
	 *   included, the package's top-level declarations, the file's imports, the builtin types and the keywords.
	 * Each has its kind, its type as detail, and its doc comment. Empty when there's nothing to offer.
	 */
	llvm::json::Array completion_items(const CompletionRequest& request, CompletionTables* tables);
}
