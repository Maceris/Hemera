#pragma once

#include <string>

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

}
