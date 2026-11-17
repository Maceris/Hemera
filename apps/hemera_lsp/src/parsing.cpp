#include "parsing.h"

#include <mutex>
#include <sstream>
#include <utility>

#include "error/reporting.h"
#include "lexer/lexer.h"
#include "parser/parser.h"

namespace hemera::lsp {

	void prepare_parsing() {
		static std::once_flag prepared;
		std::call_once(prepared, [] {
			initialize_interned_string_cache();
			initialize_reporting_storage();
			disable_reporting_printing();
		});
	}

	std::unique_ptr<ParsedDocument> parse_document(std::string text, int64_t version, std::string_view path) {
		auto parsed = std::make_unique<ParsedDocument>();
		parsed->version = version;
		parsed->text = std::move(text);

		// Its errors are kept here and dropped, never printed: standard output is the protocol's
		ReportScope scope;
		ReportScope* outer = report_scope();
		set_report_scope(&scope);
		const size_t errors_before = thread_error_count();

		MyVector<Token> all_tokens;
		std::istringstream stream{ parsed->text };
		lexer::lex(stream, all_tokens, parsed->string_alloc, path, true);
		parsed->lexed = thread_error_count() == errors_before;
		if (parsed->lexed) {
			// The parser takes no comments: they go apart, in order
			parsed->tokens.reserve(all_tokens.size());
			for (const Token& token : all_tokens) {
				if (TokenType::COMMENT_BLOCK == token.type || TokenType::COMMENT_LINE == token.type) {
					parsed->comments.push_back(token);
				}
				else {
					parsed->tokens.push_back(token);
				}
			}
			ast::Node* tree = parser::file(path, parsed->tokens, parsed->node_alloc, &parsed->quotes);
			parsed->recovered = tree;
			if (tree != nullptr && thread_error_count() == errors_before) {
				parsed->tree = tree;
			}
		}

		set_report_scope(outer);
		// Errors also go in the process's lists, which would grow with every parse of a long session
		reset_reporting_storage();
		return parsed;
	}
}
