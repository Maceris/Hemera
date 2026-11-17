#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <string_view>

#include "lexer/token.h"
#include "memory/allocator.h"
#include "parser/ast_types.h"

// Lexing and parsing an open document in the server's own process, for what the lexer and parser can answer alone.
namespace hemera::lsp {

	/*
	 * A document's text lexed and parsed, and everything its tokens and tree live in, so it's used as long as it's
	 * kept and freed with it. Made by parse_document; not copied or moved, as its tree points into it.
	 */
	struct ParsedDocument {
		// The client's version of the text it was made from
		int64_t version = 0;
		// The text, which offsets in tokens and the tree count bytes of
		std::string text;
		Allocator<> string_alloc;
		Allocator<> node_alloc;
		// Every token but comments, in order, END_OF_FILE last; empty if the text didn't lex
		MyVector<Token> tokens;
		// The comments, in order
		MyVector<Token> comments;
		ast::QuoteTable quotes;
		// Whether the text lexed without errors; tokens and comments are only complete if it did
		bool lexed = false;
		// The file's tree, or null when it didn't lex or parse
		ast::Node* tree = nullptr;
		/*
		 * The file's tree as far as the parser could make it, going on past its errors, each top-level declaration with
		 * one in an ERROR node (parser::file); the same as tree when it parsed, and null only when it didn't lex
		 */
		ast::Node* recovered = nullptr;

		ParsedDocument() = default;
		ParsedDocument(const ParsedDocument&) = delete;
		ParsedDocument& operator=(const ParsedDocument&) = delete;
	};

	/*
	 * Sets up what lexing and parsing need, once for the process however often it's called: the string cache, and
	 * reporting's tables, with printing off, as standard output is the protocol's.
	 */
	void prepare_parsing();

	/*
	 * text lexed, with its comments apart, then parsed. path names it in errors only. What it reports goes into a
	 * reporting scope of its own and is dropped: the compiler's check reports a file's errors. It must come after
	 * prepare_parsing, from one thread at a time, as it empties reporting's process-wide lists. Never null.
	 */
	std::unique_ptr<ParsedDocument> parse_document(std::string text, int64_t version, std::string_view path);
}
