#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "lexer/token.h"
#include "memory/allocator.h"

namespace hemera {

	/*
	 * Documentation comments (docs/documentation.md): a comment opened with two stars directly before a declaration
	 * documents it, and one opened with two stars and a less-than after a field, parameter or member documents the one
	 * on its line. Each is kept as its file is lexed, by where it is, its text parsed into a summary, details and tags,
	 * which compile-time code reads through reflection.
	 */

	/// <summary>
	/// One of a comment's tags, like param, return or error, with its text. name is the parameter's, the generic
	/// parameter's or the error's, for the tags that name one, and empty for the rest.
	/// </summary>
	struct DocumentationTag {
		std::string tag;
		std::string name;
		std::string text;
		uint32_t line = 0;
		uint16_t column = 0;
	};

	/// <summary>
	/// A documentation comment, parsed: its summary (its brief tag's, or its first sentence), the rest of its text, and
	/// its tags, in order.
	/// </summary>
	struct Documentation {
		std::string brief;
		std::string details;
		std::vector<DocumentationTag> tags;
		// Where the comment starts, for errors about it
		uint32_t line = 0;
		uint16_t column = 0;

		/// <summary>
		/// The text of the first tag of this kind naming name, or of the first of this kind for an empty name, if
		/// there's one.
		/// </summary>
		const DocumentationTag* tag_named(std::string_view tag, std::string_view name = {}) const;
	};

	/// <summary>
	/// A file's tokens, lexed with their comments, made the file's tokens without them: each documentation comment
	/// kept for the file, and, when checking, one that's malformed or documents nothing reported (E3034).
	/// </summary>
	void keep_documentation(std::string_view file_path, MyVector<Token>& tokens, bool check);

	/// <summary>
	/// The documentation of what's declared at the token at line and column in a file: a documentation comment just
	/// before it, or one after it on its line.
	/// </summary>
	std::optional<Documentation> documentation_at(std::string_view file_path, uint32_t line, uint16_t column);

	/// <summary>
	/// A documentation comment's text, from its opening to its closing, parsed; problems with it, if any, in problems,
	/// each with where in the file it is.
	/// </summary>
	Documentation parse_documentation(std::string_view text, uint32_t line, uint16_t column, std::vector<DocumentationTag>* problems);

	/// <summary>
	/// What a function's documentation says of each of its results, named names (all empty for unnamed ones): with
	/// names, the return tag whose text starts with each one's name, the rest of its text; without, each return tag in
	/// turn. Empty for a result none says anything of.
	/// </summary>
	std::vector<std::string> result_documentation(const Documentation& documentation, const std::vector<std::string>& names);

	/// <summary>
	/// Whether a declaration's documentation, at its name's line and column in a file, is to be checked: the first time
	/// it's asked, and not again, for a declaration that's resolved more than once.
	/// </summary>
	bool first_documentation_check(std::string_view file_path, uint32_t line, uint16_t column);

	/// <summary>
	/// Whether a comment's text is a documentation comment's: one opened with two stars, or two stars and a less-than,
	/// but not three stars, and not an empty comment.
	/// </summary>
	bool is_documentation(std::string_view comment);
}
