#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "parser/ast_types.h"

namespace hemera::ast {

	/// <summary>
	/// Hemera source for a tree, which parses back into the same tree: a file, or one declaration,
	/// statement or expression. For code compile-time code made (docs/compilation.md), and for reading
	/// it. Comments and the original layout aren't kept. #code quotes are found in quotes, and written as
	/// #code alone without it.
	/// </summary>
	std::string source_of(const Node* node, const QuoteTable* quotes = nullptr);

	/// <summary>
	/// Hemera source for a block's statements, without its braces: what a #code { ... } quote holds.
	/// #code quotes are found in quotes, and written as #code alone without it.
	/// </summary>
	std::string source_of_statements(const Node* block, const QuoteTable* quotes = nullptr);

	/// <summary>
	/// A file laid out by format_tree, and the comments it couldn't place.
	/// </summary>
	struct Formatted {
		std::string text;
		/// <summary>
		/// The byte offsets, in the source, of comments text leaves out because no node could take them,
		/// in order; empty when every comment is kept. A file with any isn't safe to write back.
		/// </summary>
		std::vector<uint32_t> lost_comments;
	};

	/// <summary>
	/// file, the tree the parser made of source, laid out within width columns (SIZE_MAX for no limit), its
	/// lines ending in newline, with each of comments where it was among the code and the blank lines that
	/// were between declarations and statements, at most one in a row. tokens are the ones file was parsed
	/// from, without the comments, each with its span; comments are the file's comments, in order, each
	/// with its span. quotes are the file's #code quotes, or null. An empty Formatted for a null file.
	/// </summary>
	Formatted format_tree(const Node* file, const QuoteTable* quotes, std::string_view source, const MyVector<Token>& tokens,
		const MyVector<Token>& comments, size_t width, std::string_view newline);

}
