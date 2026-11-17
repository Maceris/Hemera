#include "features.h"

#include <algorithm>

namespace hemera::lsp {

	using llvm::json::Array;
	using llvm::json::Object;
	using llvm::json::Value;

	// Whether offset is inside a UTF-8 character, or between a \r and its \n, so not a place a position can name
	static bool inside_character(std::string_view text, size_t offset) {
		if (offset == 0 || offset >= text.size()) {
			return false;
		}
		return (static_cast<unsigned char>(text[offset]) & 0xC0) == 0x80 || (text[offset - 1] == '\r' && text[offset] == '\n');
	}

	std::optional<TextChange> changed_span(std::string_view old_text, std::string_view new_text) {
		if (old_text == new_text) {
			return std::nullopt;
		}
		const size_t shorter = std::min(old_text.size(), new_text.size());
		size_t start = 0;
		while (start < shorter && old_text[start] == new_text[start]) {
			++start;
		}
		// Back to where a character starts, which is the same place in both
		while (inside_character(old_text, start) || inside_character(new_text, start)) {
			--start;
		}
		// The common end, not reaching back past start in either
		size_t common_end = 0;
		while (common_end < shorter - start && old_text[old_text.size() - 1 - common_end] == new_text[new_text.size() - 1 - common_end]) {
			++common_end;
		}
		while (common_end > 0 && (inside_character(old_text, old_text.size() - common_end)
			|| inside_character(new_text, new_text.size() - common_end))) {
			--common_end;
		}
		return TextChange{ start, old_text.size() - common_end,
			std::string(new_text.substr(start, new_text.size() - common_end - start)) };
	}

	Value position_at(const LineIndex& index, size_t offset, Encoding encoding) {
		const auto [line, byte] = index.line_and_byte(offset);
		return Object{ { "line", line }, { "character", index.character(line, byte, encoding) } };
	}

	namespace {

		// The Language Server Protocol's SymbolKind numbers this uses
		namespace symbol_kinds {
			constexpr int64_t FIELD = 8;
			constexpr int64_t ENUM = 10;
			constexpr int64_t FUNCTION = 12;
			constexpr int64_t CONSTANT = 14;
			constexpr int64_t ENUM_MEMBER = 22;
			constexpr int64_t STRUCT = 23;
			constexpr int64_t TYPE_PARAMETER = 26;
		}

		// A run of bytes in the text, empty until widened
		struct Span {
			size_t start = SIZE_MAX;
			size_t end = 0;

			bool empty() const { return start == SIZE_MAX; }
		};

		// span widened to take in node's token and every token under it
		void widen(const ast::Node* node, Span& span) {
			if (node->value.offset != Token::NO_SPAN) {
				span.start = std::min<size_t>(span.start, node->value.offset);
				span.end = std::max<size_t>(span.end, static_cast<size_t>(node->value.offset) + node->value.length);
			}
			for (const ast::Node* child : node->children) {
				widen(child, span);
			}
		}

		Span span_of(const ast::Node* node) {
			Span span;
			widen(node, span);
			return span;
		}

		// A symbol's JSON, with its children if it has any
		struct Symbols {
			const ParsedDocument& document;
			const LineIndex index;
			const Encoding encoding;

			Value range(size_t start, size_t end) const {
				return Object{ { "start", position_at(index, start, encoding) }, { "end", position_at(index, end, encoding) } };
			}

			Object symbol(const ast::Node* name, std::string_view detail, int64_t kind, size_t start, size_t end) const {
				const size_t name_start = name->value.offset;
				Object made{
					{ "name", name->value.value != nullptr ? std::string(*name->value.value) : std::string() },
					{ "detail", std::string(detail) },
					{ "kind", kind },
					{ "range", range(std::min(start, name_start), std::max<size_t>(end, name_start + name->value.length)) },
					{ "selectionRange", range(name_start, name_start + name->value.length) },
				};
				return made;
			}

			// Where the last token before offset ends: a declaration's closing brace, which no node holds
			size_t last_token_end_before(size_t offset) const {
				// Tokens come in the order of their offsets
				auto after = std::lower_bound(document.tokens.begin(), document.tokens.end(), offset,
					[](const Token& token, size_t at) { return token.offset < at; });
				while (after != document.tokens.begin()) {
					--after;
					if (after->offset != Token::NO_SPAN && TokenType::END_OF_FILE != after->type) {
						return static_cast<size_t>(after->offset) + after->length;
					}
				}
				return 0;
			}

			// The start of the doc comment right before start, with only blanks between, or start if there's none
			size_t doc_comment_start(size_t start) const {
				for (auto comment = document.comments.rbegin(); comment != document.comments.rend(); ++comment) {
					const size_t comment_end = static_cast<size_t>(comment->offset) + comment->length;
					if (comment->offset == Token::NO_SPAN || comment_end > start) {
						continue;
					}
					const std::string_view between = std::string_view(document.text).substr(comment_end, start - comment_end);
					const bool blank = between.find_first_not_of(" \t\r\n") == std::string_view::npos;
					const bool doc = std::string_view(document.text).substr(comment->offset).starts_with("/**");
					return blank && doc ? comment->offset : start;
				}
				return start;
			}

			// A struct's fields, an enum's members or a union's variants
			Array members(const ast::Node* body) const {
				Array found;
				for (size_t i = 0; i < body->children.size(); ++i) {
					const ast::Node* member = body->children[i];
					if (ast::NodeType::STRUCT == body->node_type && ast::NodeType::DEFINITION == member->node_type && !member->children.empty()
						&& ast::NodeType::IDENTIFIER == member->children[0]->node_type) {
						const Span span = span_of(member);
						found.push_back(symbol(member->children[0], "", symbol_kinds::FIELD, span.start, span.end));
					}
					else if (ast::NodeType::STRUCT != body->node_type && ast::NodeType::IDENTIFIER == member->node_type
						&& member->value.offset != Token::NO_SPAN) {
						Span span = span_of(member);
						// A variant's payload is the node after its name
						if (i + 1 < body->children.size() && ast::NodeType::PAREN_GROUP == body->children[i + 1]->node_type) {
							widen(body->children[i + 1], span);
						}
						found.push_back(symbol(member, "", symbol_kinds::ENUM_MEMBER, span.start, span.end));
					}
				}
				return found;
			}

			Array top_level() const {
				Array found;
				// A declaration with an error is in an ERROR node, with what the parser made of it
				std::vector<const ast::Node*> declarations;
				for (const ast::Node* child : document.recovered->children) {
					if (ast::NodeType::ERROR != child->node_type) {
						declarations.push_back(child);
						continue;
					}
					for (const ast::Node* made : child->children) {
						declarations.push_back(made);
					}
				}
				for (size_t i = 0; i < declarations.size(); ++i) {
					const ast::Node* declaration = declarations[i];
					if (ast::NodeType::DEFINITION != declaration->node_type || declaration->children.empty()
						|| ast::NodeType::IDENTIFIER != declaration->children[0]->node_type
						|| declaration->children[0]->value.offset == Token::NO_SPAN) {
						continue;
					}
					std::string_view detail;
					int64_t kind = symbol_kinds::CONSTANT;
					const ast::Node* body = nullptr;
					for (size_t j = 1; j < declaration->children.size() && body == nullptr && detail.empty(); ++j) {
						const ast::Node* value = declaration->children[j];
						const ast::NodeType type = value->node_type;
						if (ast::NodeType::FUNCTION == type) {
							detail = "fn";
							kind = symbol_kinds::FUNCTION;
						}
						else if (ast::NodeType::STRUCT == type || ast::NodeType::ENUM == type || ast::NodeType::UNION == type) {
							detail = ast::NodeType::STRUCT == type ? "struct" : ast::NodeType::ENUM == type ? "enum" : "union";
							kind = ast::NodeType::STRUCT == type ? symbol_kinds::STRUCT : symbol_kinds::ENUM;
							body = value;
						}
						else if (ast::NodeType::KEYWORD_ALIAS == type || ast::NodeType::KEYWORD_DISTINCT == type) {
							detail = ast::NodeType::KEYWORD_DISTINCT == type ? "distinct alias" : "alias";
							kind = symbol_kinds::TYPE_PARAMETER;
						}
					}
					// To the last token before what comes next, so a closing brace is in it
					const size_t next = i + 1 < declarations.size() && !span_of(declarations[i + 1]).empty()
						? span_of(declarations[i + 1]).start : document.text.size();
					const Span span = span_of(declaration);
					Object made = symbol(declaration->children[0], detail, kind, doc_comment_start(span.start),
						std::max(span.end, last_token_end_before(next)));
					if (body != nullptr) {
						made["children"] = members(body);
					}
					found.push_back(std::move(made));
				}
				return found;
			}
		};
	}

	namespace {

		// A fold from line start to line end, counting from 0, of kind comment or imports, or with no kind for code
		Object fold(uint32_t start, uint32_t end, std::string_view kind = {}) {
			Object made{ { "startLine", start }, { "endLine", end } };
			if (!kind.empty()) {
				made["kind"] = std::string(kind);
			}
			return made;
		}

		// The line a token ends on, counting from 0: its start's, plus the line ends inside it
		uint32_t last_line(const Token& token, std::string_view text) {
			uint32_t line = token.line_number - 1;
			if (token.offset != Token::NO_SPAN) {
				const std::string_view inside = text.substr(token.offset, token.length);
				line += static_cast<uint32_t>(std::count(inside.begin(), inside.end(), '\n'));
			}
			return line;
		}

		bool is_import(const Token& token) {
			return TokenType::IDENTIFIER == token.type && token.column_number == 0 && token.value != nullptr
				&& std::string_view(*token.value) == "import";
		}
	}

	Array folding_ranges(const ParsedDocument& document) {
		Array folds;
		if (!document.lexed) {
			return folds;
		}
		// Brackets, matched as they're closed; a stray closing one is passed over
		std::vector<const Token*> open;
		for (const Token& token : document.tokens) {
			if (TokenType::SYM_LBRACE == token.type || TokenType::SYM_LBRACK == token.type || TokenType::SYM_LPAREN == token.type) {
				open.push_back(&token);
				continue;
			}
			const TokenType opener = TokenType::SYM_RBRACE == token.type ? TokenType::SYM_LBRACE
				: TokenType::SYM_RBRACK == token.type ? TokenType::SYM_LBRACK
				: TokenType::SYM_RPAREN == token.type ? TokenType::SYM_LPAREN : TokenType::END_OF_FILE;
			if (TokenType::END_OF_FILE == opener || open.empty() || open.back()->type != opener) {
				continue;
			}
			const uint32_t start = open.back()->line_number - 1;
			open.pop_back();
			// To the line before the match's, which stays in sight
			if (token.line_number >= 2 && token.line_number - 2 > start) {
				folds.push_back(fold(start, token.line_number - 2));
			}
		}
		// Block comments over several lines, and runs of line comments
		for (size_t i = 0; i < document.comments.size(); ++i) {
			const Token& comment = document.comments[i];
			const uint32_t start = comment.line_number - 1;
			if (TokenType::COMMENT_BLOCK == comment.type) {
				const uint32_t end = last_line(comment, document.text);
				if (end > start) {
					folds.push_back(fold(start, end, "comment"));
				}
				continue;
			}
			size_t last = i;
			while (last + 1 < document.comments.size() && TokenType::COMMENT_LINE == document.comments[last + 1].type
				&& document.comments[last + 1].line_number == document.comments[last].line_number + 1) {
				++last;
			}
			if (last > i) {
				folds.push_back(fold(start, document.comments[last].line_number - 1, "comment"));
			}
			i = last;
		}
		// Imports in a row: each on a line of its own, the next one starting the line after the last one's tokens
		for (size_t i = 0; i < document.tokens.size(); ++i) {
			if (!is_import(document.tokens[i])) {
				continue;
			}
			const uint32_t start = document.tokens[i].line_number - 1;
			uint32_t end = start;
			size_t at = i;
			for (;;) {
				// Past this import's tokens, to the next line's first
				const uint32_t line = document.tokens[at].line_number;
				while (at < document.tokens.size() && document.tokens[at].line_number == line) {
					++at;
				}
				if (at >= document.tokens.size() || !is_import(document.tokens[at])) {
					break;
				}
				end = document.tokens[at].line_number - 1;
			}
			if (end > start) {
				folds.push_back(fold(start, end, "imports"));
			}
			i = at;
		}
		return folds;
	}

	Array document_symbols(const ParsedDocument& document, Encoding encoding) {
		if (document.recovered == nullptr) {
			return Array{};
		}
		return Symbols{ document, LineIndex(document.text), encoding }.top_level();
	}
}
