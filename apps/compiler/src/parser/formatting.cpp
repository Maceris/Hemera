#include "parser/formatting.h"

#include <sstream>
#include <string>

#include "error/reporting.h"
#include "lexer/lexer.h"
#include "lexer/token.h"
#include "memory/allocator.h"
#include "parser/ast_types.h"
#include "parser/parser.h"
#include "parser/printing.h"

namespace hemera::formatting {

	std::string_view newline_of(std::string_view source) {
		const size_t line_feed = source.find('\n');
		if (line_feed != std::string_view::npos && line_feed > 0 && source[line_feed - 1] == '\r') {
			return "\r\n";
		}
		return "\n";
	}

	Result format_source(std::string_view source, std::string_view file_path, size_t width) {
		Result result;
		const size_t errors_before = thread_error_count();

		Allocator<> string_alloc;
		MyVector<Token> all_tokens;
		std::istringstream stream{ std::string(source) };
		lexer::lex(stream, all_tokens, string_alloc, file_path, true);
		// The parser takes no comments: they go apart, in order
		MyVector<Token> tokens;
		MyVector<Token> comments;
		tokens.reserve(all_tokens.size());
		for (const Token& token : all_tokens) {
			if (TokenType::COMMENT_BLOCK == token.type || TokenType::COMMENT_LINE == token.type) {
				comments.push_back(token);
			}
			else {
				tokens.push_back(token);
			}
		}
		if (thread_error_count() != errors_before) {
			return result;
		}

		Allocator<> node_alloc;
		ast::QuoteTable quotes;
		ast::Node* tree = parser::file(file_path, tokens, node_alloc, &quotes);
		if (tree == nullptr || thread_error_count() != errors_before) {
			return result;
		}
		ast::Formatted formatted = ast::format_tree(tree, &quotes, source, tokens, comments, width, newline_of(source));
		result.parsed = true;
		result.text = std::move(formatted.text);
		result.lost_comments = std::move(formatted.lost_comments);
		return result;
	}

}
