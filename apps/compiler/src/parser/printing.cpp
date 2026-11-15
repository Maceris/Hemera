#include "parser/printing.h"

#include <algorithm>
#include <cstdint>
#include <format>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "parser/layout.h"

namespace hemera::ast {

	/*
	 * Writes a tree back as Hemera, by the shapes the parser makes (parser.cpp): the same tree comes back
	 * when the text is parsed, which the parser's round-trip test checks against every file in base, std
	 * and the scenarios. A tree the parser didn't make, like code compile-time code built, gets the
	 * parentheses its operators need, which parsing turns into PAREN_GROUP nodes.
	 */
	namespace {

		// How tightly an expression binds, by where the parser parses it: an operand needs at least its level.
		enum Level : int {
			ANY = 0,
			ASSIGNMENT = 1,
			// or_else, or_return, is_none, is_some, or_break, or_continue, and if
			FALLBACK = 2,
			RANGE = 3,
			OR = 4,
			AND = 5,
			COMPARISON = 6,
			SUM = 7,
			PRODUCT = 8,
			PREFIX = 10,
			ATOM = 11,
		};

		std::string_view text_of(const Node* node) {
			return node->value.value != nullptr ? std::string_view(*node->value.value) : std::string_view();
		}

		bool is_token(const Node* node, TokenType type) {
			return node->value.type == type;
		}

		std::string_view operator_text(TokenType type) {
			if (type == TokenType::OPERATOR_AND) {
				return "&&";
			}
			else if (type == TokenType::OPERATOR_ASSIGN) {
				return "=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_ADD) {
				return "+=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_AND) {
				return "&&=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_BITWISE_AND) {
				return "&=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_BITWISE_OR) {
				return "|=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_BITWISE_XOR) {
				return "~=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_DIV) {
				return "/=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_LEFT_SHIFT) {
				return "<<=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_MOD) {
				return "%=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_MUL) {
				return "*=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_OR) {
				return "||=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_REMAINDER) {
				return "%%=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC) {
				return ">>=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL) {
				return ">>>=";
			}
			else if (type == TokenType::OPERATOR_ASSIGN_SUB) {
				return "-=";
			}
			else if (type == TokenType::OPERATOR_BITWISE_OR) {
				return "|";
			}
			else if (type == TokenType::OPERATOR_BITWISE_XOR) {
				return "~";
			}
			else if (type == TokenType::OPERATOR_DIVIDE) {
				return "/";
			}
			else if (type == TokenType::OPERATOR_DEREFERENCE) {
				return "^";
			}
			else if (type == TokenType::OPERATOR_EQUAL) {
				return "==";
			}
			else if (type == TokenType::OPERATOR_GREATER_THAN_OR_EQUAL) {
				return ">=";
			}
			else if (type == TokenType::OPERATOR_LEFT_SHIFT) {
				return "<<";
			}
			else if (type == TokenType::OPERATOR_LESS_THAN_OR_EQUAL) {
				return "<=";
			}
			else if (type == TokenType::OPERATOR_MINUS) {
				return "-";
			}
			else if (type == TokenType::OPERATOR_MODULUS) {
				return "%";
			}
			else if (type == TokenType::OPERATOR_MULTIPLY) {
				return "*";
			}
			else if (type == TokenType::OPERATOR_NOT) {
				return "!";
			}
			else if (type == TokenType::OPERATOR_NOT_EQUAL) {
				return "!=";
			}
			else if (type == TokenType::OPERATOR_OR) {
				return "||";
			}
			else if (type == TokenType::OPERATOR_PIPE) {
				return "|>";
			}
			else if (type == TokenType::OPERATOR_PLUS) {
				return "+";
			}
			else if (type == TokenType::OPERATOR_RANGE_ARRAY) {
				return "..";
			}
			else if (type == TokenType::OPERATOR_RANGE_EXCLUSIVE) {
				return "..<";
			}
			else if (type == TokenType::OPERATOR_RANGE_INCLUSIVE) {
				return "..=";
			}
			else if (type == TokenType::OPERATOR_REMAINDER) {
				return "%%";
			}
			else if (type == TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC) {
				return ">>";
			}
			else if (type == TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL) {
				return ">>>";
			}
			else if (type == TokenType::SYM_AMPERSAND) {
				return "&";
			}
			else if (type == TokenType::SYM_GT) {
				return ">";
			}
			else if (type == TokenType::SYM_LT) {
				return "<";
			}
			else if (type == TokenType::SYM_QUESTION) {
				return "?";
			}
			else if (type == TokenType::KEYWORD_OR_ELSE) {
				return "or_else";
			}
			else if (type == TokenType::KEYWORD_OR_RETURN) {
				return "or_return";
			}
			else if (type == TokenType::KEYWORD_IS_NONE) {
				return "is_none";
			}
			else if (type == TokenType::KEYWORD_IS_SOME) {
				return "is_some";
			}
			else if (type == TokenType::KEYWORD_IS_OK) {
				return "is_ok";
			}
			else if (type == TokenType::KEYWORD_IS_ERROR) {
				return "is_error";
			}
			else if (type == TokenType::KEYWORD_OR_BREAK) {
				return "or_break";
			}
			else if (type == TokenType::KEYWORD_OR_CONTINUE) {
				return "or_continue";
			}
			else if (type == TokenType::KEYWORD_CAST) {
				return "cast";
			}
			else if (type == TokenType::KEYWORD_BIT_CAST) {
				return "bit_cast";
			}
			else if (type == TokenType::KEYWORD_AUTO_CAST) {
				return "auto_cast";
			}
			else {
				return "";
			}
		}

		bool is_assignment(TokenType type) {
			return TokenType::OPERATOR_ASSIGN == type || TokenType::OPERATOR_ASSIGN_ADD == type
				|| TokenType::OPERATOR_ASSIGN_AND == type || TokenType::OPERATOR_ASSIGN_BITWISE_AND == type
				|| TokenType::OPERATOR_ASSIGN_BITWISE_OR == type || TokenType::OPERATOR_ASSIGN_BITWISE_XOR == type
				|| TokenType::OPERATOR_ASSIGN_DIV == type || TokenType::OPERATOR_ASSIGN_LEFT_SHIFT == type
				|| TokenType::OPERATOR_ASSIGN_MOD == type || TokenType::OPERATOR_ASSIGN_MUL == type
				|| TokenType::OPERATOR_ASSIGN_OR == type || TokenType::OPERATOR_ASSIGN_REMAINDER == type
				|| TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC == type || TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL == type
				|| TokenType::OPERATOR_ASSIGN_SUB == type;
		}

		int binary_level(TokenType type) {
			if (is_assignment(type)) {
				return ASSIGNMENT;
			}
			if (type == TokenType::KEYWORD_OR_ELSE || type == TokenType::KEYWORD_OR_RETURN) {
				return FALLBACK;
			}
			else if (type == TokenType::OPERATOR_RANGE_EXCLUSIVE || type == TokenType::OPERATOR_RANGE_INCLUSIVE) {
				return RANGE;
			}
			else if (type == TokenType::OPERATOR_OR) {
				return OR;
			}
			else if (type == TokenType::OPERATOR_AND) {
				return AND;
			}
			else if (type == TokenType::OPERATOR_EQUAL || type == TokenType::OPERATOR_NOT_EQUAL || type == TokenType::SYM_LT || type == TokenType::SYM_GT || type == TokenType::OPERATOR_LESS_THAN_OR_EQUAL || type == TokenType::OPERATOR_GREATER_THAN_OR_EQUAL) {
				return COMPARISON;
			}
			else if (type == TokenType::OPERATOR_PLUS || type == TokenType::OPERATOR_MINUS || type == TokenType::OPERATOR_BITWISE_OR || type == TokenType::OPERATOR_BITWISE_XOR) {
				return SUM;
			}
			else if (type == TokenType::OPERATOR_PIPE) {
				return ATOM;
			}
			else {
				return PRODUCT;
			}
		}

		// A postfix marker in a chain like a.b[c](d)^: the operations are siblings after the value's head.
		bool is_marker(const Node* node) {
			if (!node->children.empty()) {
				return false;
			}
			return NodeType::DOT_ACCESS == node->node_type || NodeType::ARRAY_DIMENSION == node->node_type
				|| NodeType::PAREN_GROUP == node->node_type
				|| (NodeType::UNARY_OPERATOR == node->node_type && (is_token(node, TokenType::OPERATOR_DEREFERENCE)
					|| is_token(node, TokenType::OPERATOR_NOT)));
		}

		bool is_prefix(const Node* node) {
			return NodeType::UNARY_OPERATOR == node->node_type && !node->children.empty()
				&& (is_token(node, TokenType::OPERATOR_MINUS) || is_token(node, TokenType::OPERATOR_PLUS)
					|| is_token(node, TokenType::OPERATOR_BITWISE_XOR) || is_token(node, TokenType::OPERATOR_NOT));
		}

		int level_of(const Node* node) {
			if (node->node_type == NodeType::BINARY_OPERATOR) {
				return binary_level(node->value.type);
			}
			else if (node->node_type == NodeType::UNARY_OPERATOR) {
				if (is_prefix(node) || is_token(node, TokenType::SYM_QUESTION)) {
					return PREFIX;
				}
				if (is_token(node, TokenType::SYM_AMPERSAND)) {
					return ATOM;
				}
				return FALLBACK;
			}
			else if (node->node_type == NodeType::IF) {
				return FALLBACK;
			}
			else if (node->node_type == NodeType::LIST) {
				return ASSIGNMENT;
			}
			else if (node->node_type == NodeType::MATCH || node->node_type == NodeType::BLOCK) {
				return ANY;
			}
			else {
				return ATOM;
			}
		}

		bool is_type_node(const Node* node) {
			// A type in parentheses, like (mut u8[]), holds one
			if (NodeType::PAREN_GROUP == node->node_type && !node->children.empty()) {
				return is_type_node(node->children[0]);
			}
			return NodeType::TYPE == node->node_type || NodeType::FUNCTION == node->node_type || NodeType::VOID == node->node_type;
		}

		// The = of a variable's definition, kept as an IDENTIFIER, or a constant's COLON.
		bool is_separator(const Node* node) {
			return NodeType::COLON == node->node_type
				|| (NodeType::IDENTIFIER == node->node_type && is_token(node, TokenType::OPERATOR_ASSIGN));
		}

		// An #insert among fields, variants, members, patterns or cases, rather than a directive on what holds them.
		bool is_insert(const Node* node) {
			return NodeType::DIRECTIVE == node->node_type && text_of(node) == "#insert";
		}

		bool is_question(const Node* node) {
			return NodeType::UNARY_OPERATOR == node->node_type && node->children.empty() && is_token(node, TokenType::SYM_QUESTION);
		}

		/*
		 * The #insert placeholders in a quote's tree, in the order the parser gave their operands to the #code
		 * node (find_splices): not counting those inside a #code within it.
		 */
		void find_placeholders(const Node* node, std::vector<const Node*>& found) {
			for (const Node* child : node->children) {
				if (NodeType::DIRECTIVE == child->node_type && text_of(child) == "#insert") {
					found.push_back(child);
					// What follows its operand, like a member's value, can have its own
					find_placeholders(child, found);
					continue;
				}
				if (NodeType::DIRECTIVE == child->node_type && text_of(child) == "#code") {
					continue;
				}
				find_placeholders(child, found);
			}
		}

		using layout::Doc;
		using layout::EMPTY;

		// Parts of a layout gathered in order, to concat once
		struct Parts {
			layout::Document& d;
			std::vector<Doc> items;

			explicit Parts(layout::Document& d)
				: d{ d }
			{}

			Parts& operator<<(Doc doc) {
				if (doc != EMPTY) {
					items.push_back(doc);
				}
				return *this;
			}

			Parts& operator<<(std::string_view text) {
				return *this << d.text(text);
			}

			bool empty() const {
				return items.empty();
			}

			Doc doc() const {
				return d.concat(items);
			}
		};

		/*
		 * A file's comments, each attached to a node the printer prints, as leading (before it), trailing (after
		 * it) or dangling (inside it, with nothing else there, like an empty block's). A comment goes to the
		 * nodes around it in the innermost node that holds it: trailing the one before it when it's on that
		 * one's line, else leading the one after it, else trailing the last one, else dangling. Only nodes the
		 * printer prints through host count, found by printing once without comments.
		 */
		struct Comments {
			struct Extent {
				uint32_t start = UINT32_MAX;
				uint32_t end = 0;
			};

			struct Attached {
				std::vector<uint32_t> leading;
				std::vector<uint32_t> trailing;
				std::vector<uint32_t> dangling;
			};

			std::string_view source;
			const MyVector<Token>& tokens;
			const MyVector<Token>& comments;
			const QuoteTable* quote_table;
			// Each node's first and last byte, from its tokens and the brackets they open or close
			std::unordered_map<const Node*, Extent> extents;
			std::unordered_map<const Node*, const Node*> parents;
			std::unordered_map<const Node*, Attached> attached;
			std::unordered_set<const Node*> hosted;
			// True while printing without comments, to find what host prints
			bool recording = false;

			/*
			 * For each token, the index of the bracket it pairs with if it's one, and for range queries over
			 * them, sparse tables of the furthest pair to the right (closes) and left (opens) of each range.
			 */
			std::vector<std::vector<uint32_t>> closes;
			std::vector<std::vector<uint32_t>> opens;

			Comments(std::string_view source, const MyVector<Token>& tokens, const MyVector<Token>& comments, const QuoteTable* quote_table)
				: source{ source }
				, tokens{ tokens }
				, comments{ comments }
				, quote_table{ quote_table }
			{
				pair_brackets();
			}

			void pair_brackets() {
				const size_t count = tokens.size();
				std::vector<uint32_t> close(count);
				std::vector<uint32_t> open(count);
				std::vector<uint32_t> stack;
				for (uint32_t i = 0; i < count; ++i) {
					close[i] = i;
					open[i] = i;
					const TokenType type = tokens[i].type;
					if (TokenType::SYM_LPAREN == type || TokenType::SYM_LBRACE == type || TokenType::SYM_LBRACK == type) {
						stack.push_back(i);
					}
					else if ((TokenType::SYM_RPAREN == type || TokenType::SYM_RBRACE == type || TokenType::SYM_RBRACK == type)
						&& !stack.empty()) {
						close[stack.back()] = i;
						open[i] = stack.back();
						stack.pop_back();
					}
				}
				closes.push_back(std::move(close));
				opens.push_back(std::move(open));
				for (size_t span = 1; span * 2 <= count; span *= 2) {
					const std::vector<uint32_t>& closes_before = closes.back();
					const std::vector<uint32_t>& opens_before = opens.back();
					std::vector<uint32_t> next_closes(count - span * 2 + 1);
					std::vector<uint32_t> next_opens(count - span * 2 + 1);
					for (size_t i = 0; i + span * 2 <= count; ++i) {
						next_closes[i] = std::max(closes_before[i], closes_before[i + span]);
						next_opens[i] = std::min(opens_before[i], opens_before[i + span]);
					}
					closes.push_back(std::move(next_closes));
					opens.push_back(std::move(next_opens));
				}
			}

			// The token at offset, or tokens.size() if none starts there.
			size_t token_at(uint32_t offset) const {
				auto found = std::lower_bound(tokens.begin(), tokens.end(), offset,
					[](const Token& token, uint32_t value) { return token.offset < value; });
				return found != tokens.end() && found->offset == offset ? static_cast<size_t>(found - tokens.begin()) : tokens.size();
			}

			// Widens first..last (token indices) to take in the pair of every bracket in it.
			void take_in_brackets(size_t& first, size_t& last) const {
				while (true) {
					const size_t length = last - first + 1;
					size_t level = 0;
					while ((size_t{ 2 } << level) <= length) {
						++level;
					}
					const size_t other = last + 1 - (size_t{ 1 } << level);
					const size_t right = std::max(closes[level][first], closes[level][other]);
					const size_t left = std::min(opens[level][first], opens[level][other]);
					if (right <= last && left >= first) {
						return;
					}
					first = std::min(first, left);
					last = std::max(last, right);
				}
			}

			void children_of(const Node* node, std::vector<const Node*>& out) const {
				out.assign(node->children.begin(), node->children.end());
				// A #code quote's tree is where its text is, among what it splices
				if (quote_table != nullptr && NodeType::DIRECTIVE == node->node_type && text_of(node) == "#code") {
					if (const Node* tree = quote_table->get(node)) {
						out.push_back(tree);
					}
				}
			}

			// Finds node's extent and its descendants', as token indices first..last; false if it has no tokens.
			bool measure(const Node* node, size_t& first, size_t& last) {
				first = SIZE_MAX;
				last = 0;
				if (node->value.offset != Token::NO_SPAN) {
					const size_t own = token_at(node->value.offset);
					if (own < tokens.size()) {
						first = own;
						last = own;
					}
				}
				std::vector<const Node*> children;
				children_of(node, children);
				for (const Node* child : children) {
					parents[child] = node;
					size_t child_first = 0;
					size_t child_last = 0;
					if (measure(child, child_first, child_last)) {
						first = std::min(first, child_first);
						last = std::max(last, child_last);
					}
				}
				if (first == SIZE_MAX) {
					return false;
				}
				take_in_brackets(first, last);
				extents[node] = Extent{ tokens[first].offset, tokens[last].offset + tokens[last].length };
				return true;
			}

			Extent extent(const Node* node) const {
				auto found = extents.find(node);
				return found != extents.end() ? found->second : Extent{};
			}

			uint32_t start_of(uint32_t comment) const {
				return comments[comment].offset;
			}

			uint32_t end_of(uint32_t comment) const {
				return comments[comment].offset + comments[comment].length;
			}

			bool is_line_comment(uint32_t comment) const {
				return TokenType::COMMENT_LINE == comments[comment].type;
			}

			// The line breaks in source from from to to.
			size_t breaks_between(uint32_t from, uint32_t to) const {
				size_t count = 0;
				for (uint32_t i = from; i < to && i < source.size(); ++i) {
					count += source[i] == '\n' ? 1 : 0;
				}
				return count;
			}

			// Whether nothing but spaces follows offset on its line.
			bool ends_line(uint32_t offset) const {
				size_t i = offset;
				while (i < source.size() && (source[i] == ' ' || source[i] == '\t' || source[i] == '\r')) {
					++i;
				}
				return i >= source.size() || source[i] == '\n';
			}

			// The line breaks in the spaces before offset, back to the code or comment before them.
			size_t breaks_before(uint32_t offset) const {
				size_t count = 0;
				size_t i = std::min<size_t>(offset, source.size());
				while (i > 0 && (source[i - 1] == ' ' || source[i - 1] == '\t' || source[i - 1] == '\r' || source[i - 1] == '\n')) {
					--i;
					count += source[i] == '\n' ? 1 : 0;
				}
				// The file's start counts as a line's
				return i == 0 ? std::max<size_t>(count, 1) : count;
			}

			bool is_quote(const Node* node) const {
				return quote_table != nullptr && NodeType::DIRECTIVE == node->node_type && text_of(node) == "#code"
					&& quote_table->get(node) != nullptr;
			}

			// nodes that are printed through host, in order, each that isn't replaced by those among its own.
			void printed_in(const std::vector<const Node*>& nodes, std::vector<const Node*>& out) const {
				for (const Node* node : nodes) {
					const Extent span = extent(node);
					if (span.start > span.end) {
						continue;
					}
					if (hosted.contains(node)) {
						out.push_back(node);
						continue;
					}
					std::vector<const Node*> children;
					children_of(node, children);
					std::stable_sort(children.begin(), children.end(),
						[&](const Node* a, const Node* b) { return extent(a).start < extent(b).start; });
					printed_in(children, out);
				}
			}

			void attach_all(const Node* root) {
				std::vector<const Node*> children;
				for (uint32_t comment = 0; comment < comments.size(); ++comment) {
					const uint32_t start = start_of(comment);
					const uint32_t end = end_of(comment);
					const Node* node = root;
					while (true) {
						children_of(node, children);
						std::stable_sort(children.begin(), children.end(),
							[&](const Node* a, const Node* b) { return extent(a).start < extent(b).start; });
						/*
						 * The child it's inside, if any. A childless node that isn't printed through host, like a
						 * call's ( marker, whose extent reaches its ), holds nothing a comment could go with.
						 */
						const Node* enclosing = nullptr;
						for (const Node* child : children) {
							const Extent span = extent(child);
							if (span.start <= start && end <= span.end
								&& (hosted.contains(child) || !child->children.empty() || is_quote(child))) {
								enclosing = child;
								break;
							}
						}
						if (enclosing != nullptr) {
							node = enclosing;
							continue;
						}
						// The printed nodes around it: one that isn't printed through host stands aside for its children
						std::vector<const Node*> around;
						printed_in(children, around);
						const Node* before = nullptr;
						const Node* after = nullptr;
						for (const Node* child : around) {
							const Extent span = extent(child);
							if (span.end <= start) {
								before = child;
							}
							else if (span.start >= end && after == nullptr) {
								after = child;
							}
						}
						const bool on_line_before = before != nullptr && breaks_between(extent(before).end, start) == 0;
						const bool on_line_after = after != nullptr && breaks_between(end, extent(after).start) == 0;
						if (is_line_comment(comment) && on_line_before) {
							attached[before].trailing.push_back(comment);
						}
						else if (!is_line_comment(comment) && on_line_after) {
							attached[after].leading.push_back(comment);
						}
						else if (on_line_before) {
							attached[before].trailing.push_back(comment);
						}
						else if (after != nullptr) {
							attached[after].leading.push_back(comment);
						}
						else if (before != nullptr) {
							attached[before].trailing.push_back(comment);
						}
						else {
							// Nothing printed around it in node: in the nearest node that's printed
							while (!hosted.contains(node) && parents.contains(node)) {
								node = parents.at(node);
							}
							attached[node].dangling.push_back(comment);
						}
						break;
					}
				}
			}
		};

		struct Printer {
			layout::Document& d;
			const QuoteTable* quote_table = nullptr;
			// The file's comments, or null for code without them, like code compile-time code made
			Comments* comments = nullptr;
			// The nodes whose comments have been printed, which are printed once
			std::unordered_set<const Node*> printed;
			// Which of the file's comments are in the layout
			std::vector<bool> comments_printed;
			/*
			 * The #code quotes being printed, innermost last, each with what each of its placeholders splices:
			 * by placeholder, so it doesn't matter in which order the printer reaches them.
			 */
			std::vector<std::unordered_map<const Node*, const Node*>> quotes;

			explicit Printer(layout::Document& d)
				: d{ d }
			{}

			Parts parts() {
				return Parts(d);
			}

			Doc text(std::string_view text) {
				return d.text(text);
			}

			Doc nl() {
				return d.hard_line();
			}

			// Each of docs on a line of its own, one indent deeper: what goes between a { and its }.
			Doc indented_lines(const std::vector<Doc>& docs) {
				Parts out = parts();
				for (const Doc doc : docs) {
					out << nl() << doc;
				}
				return d.indent(out.doc());
			}

			/*
			 * Each item on a line of its own, one indent deeper, with a blank line before one that had one
			 * (L6), but not the first: what goes between a { and its }. A comment in one doesn't break
			 * the groups around them.
			 */
			Doc item_lines(const std::vector<std::pair<const Node*, Doc>>& items) {
				Parts out = parts();
				for (size_t i = 0; i < items.size(); ++i) {
					out << nl();
					if (i > 0 && blank_before(items[i].first)) {
						out << nl();
					}
					out << items[i].second;
				}
				return d.indent(d.isolate(out.doc()));
			}

			// Whether the source had a blank line before node, or before its leading comments.
			bool blank_before(const Node* node) {
				if (comments == nullptr || comments->recording) {
					return false;
				}
				uint32_t start = comments->extent(node).start;
				auto found = comments->attached.find(node);
				if (found != comments->attached.end() && !found->second.leading.empty()) {
					start = std::min(start, comments->start_of(found->second.leading[0]));
				}
				return start != UINT32_MAX && comments->breaks_before(start) >= 2;
			}

			/*
			 * A comment as written, without spaces at its lines' ends. A block comment's later lines keep
			 * where they are against its first, so they move with it when it's indented (C4).
			 */
			Doc comment(uint32_t index) {
				const Token& token = comments->comments[index];
				comments_printed[index] = true;
				std::string_view written = comments->source.substr(token.offset, token.length);
				size_t line_start = token.offset;
				while (line_start > 0 && comments->source[line_start - 1] != '\n') {
					--line_start;
				}
				const size_t column = token.offset - line_start;
				Parts out = parts();
				bool first = true;
				while (true) {
					const size_t line_end = written.find('\n');
					std::string_view line = written.substr(0, line_end);
					while (!line.empty() && (line.back() == ' ' || line.back() == '\t' || line.back() == '\r')) {
						line.remove_suffix(1);
					}
					if (!first) {
						size_t strip = 0;
						while (strip < column && strip < line.size() && (line[strip] == ' ' || line[strip] == '\t')) {
							++strip;
						}
						line.remove_prefix(strip);
						out << nl();
					}
					out << line;
					first = false;
					if (line_end == std::string_view::npos) {
						break;
					}
					written.remove_prefix(line_end + 1);
				}
				return out.doc();
			}

			/*
			 * doc with node's comments around it: leading ones before it, each on its own line if it was or
			 * if it's a line comment; trailing ones after it, at its line's end if they ended their line
			 * and on lines of their own after it if they had one; dangling ones as trailing ones, unless the
			 * caller prints them (a block). Each is printed once, wherever node is printed first.
			 */
			Doc host(const Node* node, Doc doc, bool with_dangling = true) {
				if (comments == nullptr) {
					return doc;
				}
				if (comments->recording) {
					comments->hosted.insert(node);
					return doc;
				}
				auto found = comments->attached.find(node);
				if (found == comments->attached.end() || printed.contains(node)) {
					return doc;
				}
				printed.insert(node);
				const Comments::Attached& attached = found->second;
				const Comments::Extent span = comments->extent(node);
				Parts out = parts();
				for (size_t i = 0; i < attached.leading.size(); ++i) {
					const uint32_t index = attached.leading[i];
					const uint32_t next = i + 1 < attached.leading.size() ? comments->start_of(attached.leading[i + 1]) : span.start;
					const size_t breaks = comments->breaks_between(comments->end_of(index), next);
					out << comment(index);
					if (comments->is_line_comment(index) || breaks > 0) {
						out << nl() << (breaks > 1 ? nl() : EMPTY) << d.break_parent();
					}
					else {
						out << " ";
					}
				}
				out << doc;
				std::vector<uint32_t> after = attached.trailing;
				if (with_dangling) {
					after.insert(after.end(), attached.dangling.begin(), attached.dangling.end());
				}
				uint32_t end = span.end;
				bool at_line_end = false;
				for (const uint32_t index : after) {
					const size_t breaks = comments->breaks_between(end, comments->start_of(index));
					end = comments->end_of(index);
					// Whether it ends its line in the source, so it ends its line here too
					const bool ends_line = comments->ends_line(end);
					if (breaks > 0) {
						out << d.line_suffix(d.concat({ nl(), breaks > 1 ? nl() : EMPTY, comment(index) })) << d.break_parent();
						at_line_end = true;
					}
					else if (at_line_end || ends_line || comments->is_line_comment(index)) {
						out << d.line_suffix(d.concat({ text(" "), comment(index) }));
						if (comments->is_line_comment(index)) {
							out << d.break_parent();
						}
						at_line_end = true;
					}
					else {
						out << " " << comment(index);
					}
				}
				return out.doc();
			}

			// ---------------------------------------------------------------------------------
			// Files and declarations

			// The package statement, then a blank line, then each declaration on a line of its own.
			Doc file(const Node* node) {
				Parts out = parts();
				bool first = true;
				for (const Node* child : node->children) {
					if (NodeType::PACKAGE == child->node_type) {
						const std::string_view name = child->children.empty() ? std::string_view() : text_of(child->children[0]);
						out << host(child, d.concat({ text("package "), text(name) })) << nl() << nl();
						first = true;
						continue;
					}
					if (!first && blank_before(child)) {
						out << nl();
					}
					out << top_level(child) << nl();
					first = false;
				}
				// Comments in a file with nothing else in it
				if (comments != nullptr && !comments->recording) {
					auto found = comments->attached.find(node);
					if (found != comments->attached.end()) {
						for (const uint32_t index : found->second.dangling) {
							out << comment(index) << nl();
						}
					}
				}
				return out.doc();
			}

			Doc top_level(const Node* node) {
				if (NodeType::IMPORT == node->node_type) {
					return host(node, import(node));
				}
				if (NodeType::DIRECTIVE == node->node_type) {
					return host(node, top_level_directive(node));
				}
				return statement(node);
			}

			Doc import(const Node* node) {
				Parts out = parts();
				out << "import";
				for (const Node* child : node->children) {
					if (NodeType::KEYWORD_AS == child->node_type) {
						out << " as";
					}
					else if (NodeType::KEYWORD_FROM == child->node_type) {
						out << " from";
					}
					else {
						out << " " << text_of(child);
					}
				}
				return out.doc();
			}

			// #if, #else_if and #else at the top level hold imports and declarations; #run and #assert an expression.
			Doc top_level_directive(const Node* node) {
				const std::string_view name = text_of(node);
				if (name == "#if" || name == "#else_if" || name == "#else") {
					Parts out = parts();
					out << name;
					size_t first = 0;
					if (name != "#else" && !node->children.empty()) {
						out << " " << expression(node->children[0], ANY);
						first = 1;
					}
					std::vector<std::pair<const Node*, Doc>> lines;
					for (size_t i = first; i < node->children.size(); ++i) {
						lines.emplace_back(node->children[i], top_level(node->children[i]));
					}
					out << " {" << item_lines(lines) << nl() << "}";
					return out.doc();
				}
				return directive(node);
			}

			Doc names(const Node* node) {
				if (NodeType::DIRECTIVE == node->node_type) {
					return directive(node);
				}
				if (NodeType::LIST == node->node_type) {
					Parts out = parts();
					for (size_t i = 0; i < node->children.size(); ++i) {
						if (i > 0) {
							out << ", ";
						}
						out << names(node->children[i]);
					}
					return out.doc();
				}
				if (NodeType::UNDERSCORE == node->node_type) {
					return text("_");
				}
				Parts out = parts();
				out << text_of(node);
				for (const Node* child : node->children) {
					if (NodeType::DIRECTIVE == child->node_type) {
						out << " " << directive(child);
					}
				}
				return out.doc();
			}

			/*
			 * A definition: names, the type if one is written, then :: or : for a constant, := or = for a
			 * variable, and the value. Annotations, which follow everything, go before it, a line each.
			 */
			Doc definition(const Node* node) {
				Parts prefix = parts();
				Parts out = parts();
				if (!node->children.empty()) {
					out << names(node->children[0]);
				}
				bool is_using = false;
				size_t i = 1;
				const Node* written_type = nullptr;
				while (i < node->children.size() && !is_separator(node->children[i])) {
					const Node* child = node->children[i];
					if (NodeType::ANNOTATION == child->node_type) {
						prefix << text_of(child) << nl();
					}
					else if (NodeType::USING == child->node_type) {
						is_using = true;
					}
					else {
						written_type = child;
					}
					++i;
				}
				if (written_type != nullptr) {
					out << " : " << type(written_type, false);
				}
				if (i < node->children.size()) {
					const bool constant = NodeType::COLON == node->children[i]->node_type;
					if (written_type != nullptr) {
						out << (constant ? " : " : " = ");
					}
					else {
						out << (constant ? " :: " : " := ");
					}
					++i;
					out << value(node, i, prefix, is_using);
				}
				else if (written_type == nullptr) {
					out << " :";
				}
				return host(node, d.concat({ prefix.doc(), is_using ? text("using ") : EMPTY, out.doc() }));
			}

			// What a definition's separator is followed by, from children[i] on.
			Doc value(const Node* node, size_t i, Parts& prefix, bool& is_using) {
				Parts out = parts();
				bool first = true;
				for (; i < node->children.size(); ++i) {
					const Node* child = node->children[i];
					if (child->node_type == NodeType::ANNOTATION) {
						prefix << text_of(child) << nl();
						continue;
					}
					else if (child->node_type == NodeType::USING) {
						is_using = true;
						continue;
					}
					else if (child->node_type == NodeType::FUNCTION) {
						out << signature(child);
					}
					else if (child->node_type == NodeType::BLOCK) {
						out << " " << block(child);
					}
					else if (child->node_type == NodeType::STRUCT) {
						out << struct_declaration(child);
					}
					else if (child->node_type == NodeType::UNION) {
						out << union_declaration(child);
					}
					else if (child->node_type == NodeType::ENUM) {
						out << enum_declaration(child);
					}
					else if (child->node_type == NodeType::UNINITIALIZED) {
						out << "---";
					}
					else if (child->node_type == NodeType::KEYWORD_DISTINCT || child->node_type == NodeType::KEYWORD_ALIAS) {
						out << alias(node, i);
					}
					else {
						out << (first ? "" : " ") << expression(child, ANY);
					}
					first = false;
				}
				return out.doc();
			}

			/*
			 * distinct alias[V] T #directives where C: the generic list and where clause are on the first
			 * word, the directives on alias, and the type after. i moves past what it prints.
			 */
			Doc alias(const Node* node, size_t& i) {
				const Node* first = node->children[i];
				const Node* alias_word = first;
				Parts out = parts();
				if (NodeType::KEYWORD_DISTINCT == first->node_type) {
					out << "distinct ";
					if (i + 1 < node->children.size()) {
						alias_word = node->children[++i];
					}
				}
				out << "alias";
				for (const Node* child : first->children) {
					if (NodeType::GENERIC_TAG == child->node_type) {
						out << generic_list(child);
					}
				}
				if (i + 1 < node->children.size()) {
					out << " " << type(node->children[++i], false);
				}
				for (const Node* child : alias_word->children) {
					if (NodeType::DIRECTIVE == child->node_type) {
						out << " " << directive(child);
					}
				}
				for (const Node* child : first->children) {
					if (NodeType::WHERE_CLAUSE == child->node_type) {
						out << where_clause(child);
					}
				}
				return out.doc();
			}

			Doc where_clause(const Node* node) {
				if (node->children.empty()) {
					return text(" where");
				}
				return d.concat({ text(" where "), expression(node->children[0], ANY) });
			}

			// keyword is struct, or fields for a quote of a struct's fields
			Doc struct_declaration(const Node* node, std::string_view keyword = "struct") {
				Parts out = parts();
				out << keyword;
				std::vector<std::pair<const Node*, Doc>> members;
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::GENERIC_TAG) {
						out << generic_list(child);
					}
					else if (is_insert(child)) {
						members.emplace_back(child, d.concat({ host(child, directive(child)), text(",") }));
					}
					else if (child->node_type == NodeType::DIRECTIVE) {
						out << " " << directive(child);
					}
					else if (child->node_type == NodeType::WHERE_CLAUSE) {
						out << where_clause(child);
					}
					else if (child->node_type == NodeType::USING) {
						members.emplace_back(child, d.concat({ host(child, d.concat({ text("using "), qualified(child, 0) })), text(",") }));
					}
					else {
						members.emplace_back(child, d.concat({ definition(child), text(",") }));
					}
				}
				out << " {" << item_lines(members) << nl() << "}";
				return out.doc();
			}

			// keyword is union, or variants for a quote of a union's variants
			Doc union_declaration(const Node* node, std::string_view keyword = "union") {
				Parts out = parts();
				out << keyword;
				std::vector<std::pair<const Node*, Doc>> variants;
				for (size_t i = 0; i < node->children.size(); ++i) {
					const Node* child = node->children[i];
					if (NodeType::GENERIC_TAG == child->node_type) {
						out << generic_list(child);
					}
					else if (is_insert(child)) {
						variants.emplace_back(child, d.concat({ host(child, directive(child)), text(",") }));
					}
					else if (NodeType::WHERE_CLAUSE == child->node_type) {
						out << where_clause(child);
					}
					else if (NodeType::IDENTIFIER == child->node_type) {
						Parts variant = parts();
						variant << text_of(child);
						if (i + 1 < node->children.size() && NodeType::PAREN_GROUP == node->children[i + 1]->node_type) {
							// A payload's function types are written without parentheses, which a union's payload doesn't take
							variant << "(" << list(node->children[++i]->children, [&](const Node* t) { return type(t, false); }) << ")";
						}
						variants.emplace_back(child, d.concat({ host(child, variant.doc()), text(",") }));
					}
				}
				out << " {" << item_lines(variants) << nl() << "}";
				return out.doc();
			}

			// keyword is enum, or members for a quote of an enum's members
			Doc enum_declaration(const Node* node, std::string_view keyword = "enum") {
				Parts out = parts();
				out << keyword;
				std::vector<std::pair<const Node*, Doc>> members;
				for (const Node* child : node->children) {
					if (is_insert(child)) {
						members.emplace_back(child, d.concat({ host(child, directive(child)), text(",") }));
						continue;
					}
					if (NodeType::DIRECTIVE == child->node_type) {
						out << " " << directive(child);
						continue;
					}
					Parts member = parts();
					member << text_of(child);
					for (const Node* assign : child->children) {
						if (!assign->children.empty()) {
							member << " = " << expression(assign->children[0], ANY);
						}
					}
					members.emplace_back(child, d.concat({ host(child, member.doc()), text(",") }));
				}
				out << " {" << item_lines(members) << nl() << "}";
				return out.doc();
			}

			// ---------------------------------------------------------------------------------
			// Types

			/*
			 * A type where one goes. Function types are written in parentheses where they're a part of
			 * something else, which needs them in parameter and result lists, and lets a ? follow.
			 */
			Doc type(const Node* node, bool part) {
				return host(node, type_bare(node, part));
			}

			Doc type_bare(const Node* node, bool part) {
				if (node->node_type == NodeType::VOID) {
					return text("void");
				}
				else if (node->node_type == NodeType::FUNCTION) {
					bool optional = false;
					for (const Node* child : node->children) {
						optional = optional || is_question(child);
					}
					if (part || optional) {
						return d.concat({ text("("), signature(node), text(")"), optional ? text("?") : EMPTY });
					}
					return signature(node);
				}
				else if (node->node_type == NodeType::TYPE) {
					return simple_type(node);
				}
				// (T), with mut before it if it's the pointer's, and ? after it
				else if (node->node_type == NodeType::PAREN_GROUP && !node->children.empty()) {
					bool is_mutable = false;
					bool optional = false;
					for (size_t i = 1; i < node->children.size(); ++i) {
						if (node->children[i]->node_type == NodeType::MUTABLE) {
							is_mutable = true;
						}
						else if (is_question(node->children[i])) {
							optional = true;
						}
					}
					return d.concat({ is_mutable ? text("mut ") : EMPTY, text("("), type(node->children[0], false), text(")"),
						optional ? text("?") : EMPTY });
				}
				// An anonymous struct member's, like _ : struct #packed { ... }
				else if (node->node_type == NodeType::STRUCT) {
					return struct_declaration(node);
				}
				else {
					return expression(node, ANY);
				}
			}

			// mut, a name maybe qualified by package, generic arguments, dimensions, ?, and a result's directives.
			Doc simple_type(const Node* node) {
				Parts out = parts();
				Parts after = parts();
				bool mutable_type = false;
				out << text_of(node);
				for (size_t i = 0; i < node->children.size(); ++i) {
					const Node* child = node->children[i];
					if (child->node_type == NodeType::MUTABLE) {
						mutable_type = true;
					}
					else if (child->node_type == NodeType::DOT_ACCESS) {
						out << ".";
					}
					else if (child->node_type == NodeType::IDENTIFIER) {
						out << text_of(child);
					}
					else if (child->node_type == NodeType::GENERIC_TAG) {
						out << generic_list(child);
					}
					else if (child->node_type == NodeType::ARRAY_DIMENSION) {
						out << dimension(child);
					}
					else if (child->node_type == NodeType::UNARY_OPERATOR) {
						out << "?";
					}
					else if (child->node_type == NodeType::DIRECTIVE) {
						after << " " << directive(child);
					}
				}
				return d.concat({ mutable_type ? text("mut ") : EMPTY, out.doc(), after.doc() });
			}

			Doc dimension(const Node* node) {
				if (node->children.empty()) {
					return text("[]");
				}
				if (node->children.size() == 1) {
					const Node* child = node->children[0];
					if (NodeType::RANGE_ARRAY == child->node_type) {
						return text("[..]");
					}
					return d.concat({ text("["), expression(child, ANY), text("]") });
				}
				return d.concat({ text("["), qualified(node, 0), text("]") });
			}

			// A name and its package qualifiers, from children[first] on: net.MTU, compiler.TypeInfo.
			Doc qualified(const Node* node, size_t first) {
				Parts out = parts();
				for (size_t i = first; i < node->children.size(); ++i) {
					const Node* child = node->children[i];
					out << (NodeType::DOT_ACCESS == child->node_type ? std::string_view(".") : text_of(child));
				}
				return out.doc();
			}

			Doc generic_list(const Node* node) {
				return d.concat({ text("["), list(node->children, [&](const Node* item) { return generic_item(item); }), text("]") });
			}

			Doc generic_item(const Node* node) {
				return host(node, generic_item_bare(node));
			}

			Doc generic_item_bare(const Node* node) {
				if (NodeType::COLON == node->node_type && node->children.size() == 2) {
					return d.concat({ text(text_of(node->children[0])), text(": "), type(node->children[1], true) });
				}
				if (NodeType::DERIVED_PARAMETER == node->node_type) {
					return d.concat({ text(text_of(node)), text(" = "),
						node->children.empty() ? EMPTY : expression(node->children[0], ANY) });
				}
				return is_type_node(node) ? type(node, true) : expression(node, ANY);
			}

			// fn[generics](parameters) -> results #directives where constraints
			Doc signature(const Node* node) {
				Parts generics = parts();
				Parts out = parts();
				bool seen_parameters = false;
				Parts after = parts();
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::GENERIC_TAG) {
						(seen_parameters ? out : generics) << generic_list(child);
					}
					else if (child->node_type == NodeType::LIST) {
						if (!seen_parameters) {
							seen_parameters = true;
							out << "(" << list(child->children, [&](const Node* p) { return parameter(p); }) << ")";
						}
						else {
							out << " -> (" << results(child) << ")";
						}
					}
					else if (child->node_type == NodeType::VOID) {
						out << " -> void";
					}
					else if (child->node_type == NodeType::TYPE) {
						out << " -> " << simple_type(child);
					}
					else if (child->node_type == NodeType::FUNCTION) {
						out << " -> " << type(child, true);
					}
					else if (child->node_type == NodeType::DIRECTIVE) {
						// A result type an #insert puts there, or the function's directives
						out << (text_of(child) == "#insert" ? " -> " : " ") << directive(child);
					}
					else if (child->node_type == NodeType::WHERE_CLAUSE) {
						after << where_clause(child);
					}
				}
				// No parameter list is written as (), right after fn
				return d.concat({ text("fn"), seen_parameters ? EMPTY : text("()"), generics.doc(), out.doc(), after.doc() });
			}

			/*
			 * A parameter: names and a type (name, name2 #escaping : T...), or a type alone in a function
			 * type, with = default.
			 */
			Doc parameter(const Node* node) {
				return host(node, parameter_bare(node));
			}

			Doc parameter_bare(const Node* node) {
				if (NodeType::BINARY_OPERATOR == node->node_type && is_token(node, TokenType::OPERATOR_ASSIGN)
					&& !node->children.empty()) {
					const Node* names_and_type = node->children[0];
					const Doc value = node->children.size() > 1 ? expression(node->children[1], ANY) : EMPTY;
					const bool deduced = NodeType::COLON == names_and_type->node_type && names_and_type->children.size() == 1;
					if (deduced) {
						return d.concat({ names(names_and_type->children[0]), text(" := "), value });
					}
					return d.concat({ parameter(names_and_type), text(" = "), value });
				}
				if (NodeType::COLON != node->node_type) {
					return d.concat({ type(node, true), varargs(node) });
				}
				Doc out = EMPTY;
				bool named = false;
				Doc type_text = EMPTY;
				bool is_varargs = false;
				for (const Node* part : node->children) {
					if (NodeType::ELLIIPSIS == part->node_type) {
						is_varargs = true;
					}
					else if (!named && (NodeType::IDENTIFIER == part->node_type || NodeType::LIST == part->node_type)) {
						out = names(part);
						named = true;
					}
					else {
						type_text = d.concat({ type(part, true), varargs(part) });
					}
				}
				return d.concat({ out, text(": "), type_text, is_varargs ? text("...") : EMPTY });
			}

			Doc varargs(const Node* node) {
				for (const Node* child : node->children) {
					if (NodeType::ELLIIPSIS == child->node_type) {
						return text("...");
					}
				}
				return EMPTY;
			}

			// Several results: types, or names sharing the type after a COLON, like a: u16, b, c: f32.
			Doc results(const Node* node) {
				Parts out = parts();
				for (size_t i = 0; i < node->children.size(); ++i) {
					const Node* part = node->children[i];
					if (NodeType::COLON == part->node_type) {
						out << ": ";
						continue;
					}
					if (i > 0 && NodeType::COLON != node->children[i - 1]->node_type) {
						out << ", ";
					}
					out << type(part, true);
				}
				return out.doc();
			}

			// ---------------------------------------------------------------------------------
			// Statements

			// { statements }, or {} for none: a block's comments with nothing else in it go inside it.
			Doc block(const Node* node) {
				const Doc inside = statement_lines(node);
				const Doc dangling = dangling_lines(node);
				if (inside == EMPTY && dangling == EMPTY) {
					return host(node, text("{}"), false);
				}
				return host(node, d.concat({ text("{"), inside, dangling, nl(), text("}") }), false);
			}

			// A block's statements without its braces, each on a line of its own after a line break.
			Doc statement_lines(const Node* node) {
				std::vector<std::pair<const Node*, Doc>> lines;
				for (const Node* child : node->children) {
					lines.emplace_back(child, statement(child));
				}
				return lines.empty() ? EMPTY : item_lines(lines);
			}

			// The comments in node with nothing else there, each on a line of its own, one indent deeper.
			Doc dangling_lines(const Node* node) {
				if (comments == nullptr || comments->recording) {
					return EMPTY;
				}
				auto found = comments->attached.find(node);
				if (found == comments->attached.end() || found->second.dangling.empty()) {
					return EMPTY;
				}
				Parts out = parts();
				for (const uint32_t index : found->second.dangling) {
					out << nl() << comment(index);
				}
				return d.indent(d.isolate(out.doc()));
			}

			Doc statement(const Node* node) {
				return host(node, statement_bare(node));
			}

			Doc statement_bare(const Node* node) {
				if (node->node_type == NodeType::DEFINITION) {
					return definition(node);
				}
				else if (node->node_type == NodeType::RETURN) {
					Parts out = parts();
					out << "return";
					for (size_t i = 0; i < node->children.size(); ++i) {
						const Node* child = node->children[i];
						out << (i > 0 ? ", " : " ") << (NodeType::VOID == child->node_type ? text("void") : expression(child, ANY));
					}
					return out.doc();
				}
				else if (node->node_type == NodeType::DEFER) {
					return d.concat({ text("defer "), node->children.empty() ? EMPTY : statement(node->children[0]) });
				}
				else if (node->node_type == NodeType::GIVE) {
					return d.concat({ text("give "), node->children.empty() ? EMPTY : expression(node->children[0], ANY) });
				}
				else if (node->node_type == NodeType::BREAK) {
					Parts out = parts();
					out << "break";
					for (const Node* child : node->children) {
						out << " " << (NodeType::KEYWORD_ALL == child->node_type ? std::string_view("all") : text_of(child));
					}
					return out.doc();
				}
				else if (node->node_type == NodeType::CONTINUE) {
					return text("continue");
				}
				else if (node->node_type == NodeType::DIRECTIVE) {
					return statement_directive(node);
				}
				else if (node->node_type == NodeType::FOR_LOOP) {
					return for_loop(node);
				}
				else if (node->node_type == NodeType::LOOP) {
					return loop(node);
				}
				else if (node->node_type == NodeType::PUSH_CONTEXT) {
					return push_context(node);
				}
				else if (node->node_type == NodeType::SWITCH) {
					return switch_statement(node);
				}
				else if (node->node_type == NodeType::USING) {
					return d.concat({ text("using "), qualified(node, 0) });
				}
				else {
					return expression(node, ANY);
				}
			}

			// #if, #else_if and #else in a body hold a block; the rest are directives in an expression.
			Doc statement_directive(const Node* node) {
				const std::string_view name = text_of(node);
				if (name == "#if" || name == "#else_if" || name == "#else") {
					Parts out = parts();
					out << name;
					for (const Node* child : node->children) {
						out << " " << (NodeType::BLOCK == child->node_type ? block(child) : expression(child, ANY));
					}
					return out.doc();
				}
				return directive(node);
			}

			// for &value, index in iterable #directives { body }: the names, IN, the iterable, directives, the block.
			Doc for_loop(const Node* node) {
				Parts out = parts();
				out << "for ";
				size_t i = 0;
				bool first_name = true;
				for (; i < node->children.size() && NodeType::IN != node->children[i]->node_type; ++i) {
					const Node* name = node->children[i];
					out << (first_name ? "" : ", ");
					first_name = false;
					if (NodeType::UNARY_OPERATOR == name->node_type) {
						out << "&" << (name->children.empty() ? std::string_view() : text_of(name->children[0]));
					}
					else {
						out << text_of(name);
					}
				}
				out << " in ";
				++i;
				if (i < node->children.size()) {
					out << expression(node->children[i], ANY);
					++i;
				}
				for (; i < node->children.size(); ++i) {
					const Node* child = node->children[i];
					out << " " << (NodeType::BLOCK == child->node_type ? block(child) : directive(child));
				}
				return out.doc();
			}

			// with { definitions } loop #directive { body } while condition
			Doc loop(const Node* node) {
				Parts out = parts();
				Doc after = EMPTY;
				Doc loop_directive = EMPTY;
				Doc body = EMPTY;
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::WITH_CLAUSE) {
						std::vector<std::pair<const Node*, Doc>> lines;
						for (const Node* definitions : child->children) {
							for (const Node* definition_node : definitions->children) {
								lines.emplace_back(definition_node, definition(definition_node));
							}
						}
						out << "with {" << item_lines(lines) << nl() << "}" << nl();
					}
					else if (child->node_type == NodeType::DIRECTIVE) {
						loop_directive = d.concat({ text(" "), directive(child) });
					}
					else if (child->node_type == NodeType::BLOCK) {
						body = d.concat({ text(" "), block(child) });
					}
					else if (child->node_type == NodeType::WHILE_CLAUSE) {
						after = d.concat({ nl(), text("while "), child->children.empty() ? EMPTY : expression(child->children[0], ANY) });
					}
				}
				out << "loop" << loop_directive << body << after;
				return out.doc();
			}

			Doc push_context(const Node* node) {
				Parts out = parts();
				out << "push_context";
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::IDENTIFIER) {
						out << " " << text_of(child);
					}
					else if (child->node_type == NodeType::KEYWORD_FROM) {
						out << " from " << (child->children.empty() ? EMPTY : expression(child->children[0], ANY));
					}
					else if (child->node_type == NodeType::LIST) {
						out << " (" << list(child->children, [&](const Node* assign) { return field_value(assign); }) << ")";
					}
					else if (child->node_type == NodeType::BLOCK) {
						out << " " << block(child);
					}
				}
				return out.doc();
			}

			Doc field_value(const Node* assign) {
				return host(assign, field_value_bare(assign));
			}

			Doc field_value_bare(const Node* assign) {
				if (NodeType::BINARY_OPERATOR == assign->node_type && is_token(assign, TokenType::OPERATOR_ASSIGN)
					&& assign->children.size() == 2) {
					return d.concat({ text(text_of(assign->children[0])), text(" = "), argument(assign->children[1]) });
				}
				return expression(assign, ANY);
			}

			Doc switch_statement(const Node* node) {
				return d.concat({
					text("switch "),
					node->children.empty() ? EMPTY : expression(node->children[0], ANY),
					text(" "),
					node->children.size() > 1 ? switch_cases(node->children[1]) : d.concat({ text("{"), nl(), text("}") }),
				});
			}

			// A switch's cases, in braces, each at the switch's indent and its statements one deeper.
			Doc switch_cases(const Node* cases) {
				Parts out = parts();
				out << "{";
				bool first = true;
				for (const Node* item : cases->children) {
					if (!first && blank_before(item)) {
						out << nl();
					}
					first = false;
					if (NodeType::DIRECTIVE == item->node_type) {
						out << indented_lines({ directive(item) });
						continue;
					}
					Parts entries = parts();
					const Node* body = nullptr;
					for (const Node* part : item->children) {
						if (NodeType::BLOCK == part->node_type) {
							body = part;
						}
						else {
							entries << (entries.empty() ? "" : ", ") << case_entry(part);
						}
					}
					const Doc statements = body != nullptr ? statement_lines(body) : EMPTY;
					out << nl() << host(item, d.concat({ text("case "), entries.doc(), text(":"), statements }));
				}
				out << nl() << "}";
				return d.isolate(out.doc());
			}

			// A case's or arm's entry: a literal, a range, Enum.Member, .Member, _, or a pattern like Some(x).
			Doc case_entry(const Node* node) {
				return host(node, case_entry_bare(node));
			}

			Doc case_entry_bare(const Node* node) {
				if (node->node_type == NodeType::BINARY_OPERATOR) {
					if (node->children.size() != 2) {
						return EMPTY;
					}
					return d.concat({ text(text_of(node->children[0])), text(operator_text(node->value.type)), text(text_of(node->children[1])) });
				}
				else if (node->node_type == NodeType::DOT_ACCESS) {
					if (node->children.size() != 2) {
						return EMPTY;
					}
					return d.concat({ text(text_of(node->children[0])), text("."), text(text_of(node->children[1])) });
				}
				else if (node->node_type == NodeType::UNDERSCORE) {
					return text("_");
				}
				else if (node->node_type == NodeType::IDENTIFIER) {
					Parts out = parts();
					out << text_of(node);
					for (const Node* child : node->children) {
						if (NodeType::PAREN_GROUP == child->node_type) {
							out << "(" << list(child->children, [&](const Node* p) { return case_entry(p); }) << ")";
						}
					}
					return out.doc();
				}
				else {
					return expression(node, ANY);
				}
			}

			Doc match(const Node* node) {
				return d.concat({
					text("match "),
					node->children.empty() ? EMPTY : expression(node->children[0], ANY),
					text(" "),
					node->children.size() > 1 ? match_arms(node->children[1]) : d.concat({ text("{"), nl(), text("}") }),
				});
			}

			// A match's patterns, each with what it runs, in braces.
			Doc match_arms(const Node* arms) {
				std::vector<std::pair<const Node*, Doc>> lines;
				for (const Node* arm : arms->children) {
					if (is_insert(arm)) {
						lines.emplace_back(arm, directive(arm));
						continue;
					}
					Parts line = parts();
					line << "case ";
					for (size_t i = 0; i + 1 < arm->children.size(); ++i) {
						line << (i > 0 ? ", " : "") << case_entry(arm->children[i]);
					}
					line << " => " << (arm->children.empty() ? EMPTY : statement(arm->children.back()));
					lines.emplace_back(arm, host(arm, line.doc()));
				}
				return d.concat({ text("{"), lines.empty() ? EMPTY : item_lines(lines), nl(), text("}") });
			}

			// ---------------------------------------------------------------------------------
			// Expressions

			template <typename F>
			Doc list(const MyVector<Node*>& items, F each) {
				Parts out = parts();
				for (size_t i = 0; i < items.size(); ++i) {
					if (i > 0) {
						out << ", ";
					}
					out << each(items[i]);
				}
				return out.doc();
			}

			Doc parenthesized(Doc inside) {
				return d.concat({ text("("), inside, text(")") });
			}

			Doc expression(const Node* node, int needed) {
				return host(node, expression_bare(node, needed));
			}

			Doc expression_bare(const Node* node, int needed) {
				if (level_of(node) < needed) {
					return parenthesized(expression(node, ANY));
				}
				if (node->node_type == NodeType::LITERAL) {
					return literal(node);
				}
				else if (node->node_type == NodeType::IDENTIFIER || node->node_type == NodeType::PIPE_REORDER_IDENTIFIER) {
					return d.concat({ text(text_of(node)), chain(node, 0) });
				}
				else if (node->node_type == NodeType::UNDERSCORE) {
					return text("_");
				}
				else if (node->node_type == NodeType::VOID) {
					return text("void");
				}
				else if (node->node_type == NodeType::RANGE_ARRAY) {
					return text("..");
				}
				else if (node->node_type == NodeType::UNINITIALIZED) {
					return text("---");
				}
				else if (node->node_type == NodeType::TYPE || node->node_type == NodeType::FUNCTION) {
					return type(node, true);
				}
				else if (node->node_type == NodeType::PAREN_GROUP) {
					return parenthesized(node->children.empty() ? EMPTY : expression(node->children[0], ANY));
				}
				else if (node->node_type == NodeType::BINARY_OPERATOR) {
					return binary(node);
				}
				else if (node->node_type == NodeType::UNARY_OPERATOR) {
					return unary(node);
				}
				else if (node->node_type == NodeType::CAST) {
					return cast(node);
				}
				else if (node->node_type == NodeType::COMPUTE && node->children.size() == 2) {
					return d.concat({ text("compute["), type(node->children[0], false), text("] "), block(node->children[1]) });
				}
				else if (node->node_type == NodeType::STRUCT_LITERAL) {
					return typed_literal(node, ".{", "}");
				}
				else if (node->node_type == NodeType::ARRAY_LITERAL) {
					return typed_literal(node, ".[", "]");
				}
				else if (node->node_type == NodeType::ENUM_SHORTHAND) {
					// .#insert name in a quote
					if (!node->children.empty() && is_insert(node->children[0])) {
						return d.concat({ text("."), directive(node->children[0]), chain(node, 1) });
					}
					return d.concat({ text("."), text(text_of(node)), chain(node, 0) });
				}
				else if (node->node_type == NodeType::IF) {
					return if_expression(node);
				}
				else if (node->node_type == NodeType::MATCH) {
					return match(node);
				}
				else if (node->node_type == NodeType::BLOCK) {
					return block(node);
				}
				else if (node->node_type == NodeType::LIST && text_of(node) == "#list") {
					// A list of code compile-time code made: parameters, arguments, statements, ...
					return list(node->children, [&](const Node* item) {
						return NodeType::COLON == item->node_type ? parameter(item) : statement(item);
					});
				}
				else if (node->node_type == NodeType::LIST) {
					return list(node->children, [&](const Node* item) { return expression(item, FALLBACK); });
				}
				else if (node->node_type == NodeType::DIRECTIVE) {
					return directive(node);
				}
				else if (node->node_type == NodeType::DEFINITION) {
					return definition(node);
				}
				else if (node->node_type == NodeType::STRUCT) {
					return struct_declaration(node);
				}
				// Statements, which a match arm's body can be
				else if (node->node_type == NodeType::RETURN || node->node_type == NodeType::DEFER
					|| node->node_type == NodeType::BREAK || node->node_type == NodeType::CONTINUE || node->node_type == NodeType::GIVE
					|| node->node_type == NodeType::FOR_LOOP || node->node_type == NodeType::LOOP
					|| node->node_type == NodeType::PUSH_CONTEXT || node->node_type == NodeType::SWITCH
					|| node->node_type == NodeType::USING) {
					return statement(node);
				}
				else {
					return text(text_of(node));
				}
			}

			Doc literal(const Node* node) {
				Parts out = parts();
				out << text_of(node);
				// A multiline string: a line per token, each starting with \\.
				for (const Node* line : node->children) {
					out << nl() << text_of(line);
				}
				return out.doc();
			}

			/*
			 * What follows a chain's head, from children[first] on: .name, [index], (arguments) and ^, each
			 * a marker followed by what belongs to it.
			 */
			Doc chain(const Node* node, size_t first) {
				Parts out = parts();
				const auto& children = node->children;
				size_t i = first;
				while (i < children.size()) {
					const Node* marker = children[i];
					++i;
					if (!is_marker(marker)) {
						// Not a chain, like a match arm's pattern: written as it is
						out << expression(marker, ANY);
						continue;
					}
					// ^, or a macro call's !
					if (NodeType::UNARY_OPERATOR == marker->node_type) {
						out << operator_text(marker->value.type);
						continue;
					}
					if (NodeType::DOT_ACCESS == marker->node_type) {
						out << ".";
						if (i < children.size()) {
							// value.#insert name in a quote
							out << (is_insert(children[i]) ? directive(children[i]) : text(text_of(children[i])));
							++i;
						}
						continue;
					}
					const bool call = NodeType::PAREN_GROUP == marker->node_type;
					Parts inside = parts();
					bool first_item = true;
					while (i < children.size() && !is_marker(children[i])) {
						const Node* item = children[i];
						inside << (first_item ? "" : ", ") << (call ? argument(item) : index(item));
						first_item = false;
						++i;
					}
					out << (call ? "(" : "[") << inside.doc() << (call ? ")" : "]");
				}
				return out.doc();
			}

			Doc argument(const Node* node) {
				return host(node, argument_bare(node));
			}

			Doc argument_bare(const Node* node) {
				if (NodeType::BINARY_OPERATOR == node->node_type && is_token(node, TokenType::OPERATOR_ASSIGN)
					&& node->children.size() == 2 && NodeType::IDENTIFIER == node->children[0]->node_type
					&& node->children[0]->children.empty()) {
					return d.concat({ text(text_of(node->children[0])), text(" = "), argument(node->children[1]) });
				}
				if (NodeType::TYPE == node->node_type) {
					return simple_type(node);
				}
				return expression(node, FALLBACK);
			}

			// What's between a chain's brackets: an index, an open range like ..<5 or 5.., or a type argument.
			Doc index(const Node* node) {
				return host(node, index_bare(node));
			}

			Doc index_bare(const Node* node) {
				if (NodeType::BINARY_OPERATOR == node->node_type && node->children.size() == 2) {
					if (NodeType::RANGE_ARRAY == node->children[0]->node_type) {
						return d.concat({ text(operator_text(node->value.type)), expression(node->children[1], ANY) });
					}
					if (NodeType::RANGE_ARRAY == node->children[1]->node_type) {
						return d.concat({ expression(node->children[0], ANY), text("..") });
					}
				}
				// A function type as a value, like Callbacks[fn(int) -> bool], is written without parentheses there
				if (is_type_node(node)) {
					return type(node, false);
				}
				return expression(node, ANY);
			}

			Doc binary(const Node* node) {
				const TokenType op = node->value.type;
				if (node->children.empty()) {
					return text(operator_text(op));
				}
				const Node* lhs = node->children[0];
				// a |> f(b): the function's name and its arguments, in a PAREN_GROUP
				if (TokenType::OPERATOR_PIPE == op) {
					Parts out = parts();
					out << expression(lhs, ATOM);
					for (size_t i = 1; i < node->children.size(); ++i) {
						const Node* part = node->children[i];
						if (NodeType::PAREN_GROUP == part->node_type) {
							out << "(" << list(part->children, [&](const Node* a) { return argument(a); }) << ")";
						}
						else {
							out << " |> " << text_of(part);
						}
					}
					return out.doc();
				}
				const Node* rhs = node->children.size() > 1 ? node->children[1] : nullptr;
				/*
				 * What each side has to be, by where the parser parses it: the next level up, or the same on
				 * the side an operator groups to (left for arithmetic, right for || and &&).
				 */
				const int level = binary_level(op);
				int left = PRODUCT;
				int right = PREFIX;
				if (ASSIGNMENT == level) {
					left = FALLBACK;
					right = ANY;
				}
				else if (FALLBACK == level) {
					left = RANGE;
					right = ANY;
				}
				else if (RANGE == level) {
					left = OR;
					right = OR;
				}
				else if (OR == level) {
					left = AND;
					right = OR;
				}
				else if (AND == level) {
					left = COMPARISON;
					right = AND;
				}
				else if (COMPARISON == level) {
					left = SUM;
					right = SUM;
				}
				else if (SUM == level) {
					left = SUM;
					right = PRODUCT;
				}
				// An assignment's targets can be a list, and a range has no spaces
				const Doc left_doc = NodeType::LIST == lhs->node_type && ASSIGNMENT == binary_level(op)
					? expression(lhs, ANY) : expression(lhs, left);
				if (rhs == nullptr) {
					return d.concat({ left_doc, text(" "), text(operator_text(op)) });
				}
				const Doc right_doc = NodeType::VOID == rhs->node_type ? text("void") : expression(rhs, right);
				if (RANGE == binary_level(op)) {
					return d.concat({ left_doc, text(operator_text(op)), right_doc });
				}
				return d.concat({ left_doc, text(" "), text(operator_text(op)), text(" "), right_doc });
			}

			Doc unary(const Node* node) {
				if (node->children.empty()) {
					return text(operator_text(node->value.type));
				}
				const Node* operand = node->children[0];
				const TokenType op = node->value.type;
				if (TokenType::SYM_AMPERSAND == op) {
					return d.concat({ text("&"), expression(operand, ATOM) });
				}
				if (is_prefix(node)) {
					return d.concat({ text(operator_text(op)), expression(operand, PREFIX) });
				}
				if (TokenType::SYM_QUESTION == op) {
					// x?: its operand is a prefix operation or an atom, but not another ?
					const bool needs_parentheses = level_of(operand) < PREFIX || is_token(operand, TokenType::SYM_QUESTION);
					return d.concat({ needs_parentheses ? parenthesized(expression(operand, ANY)) : expression(operand, PREFIX), text("?") });
				}
				return d.concat({ expression(operand, RANGE), text(" "), text(operator_text(op)) });
			}

			// cast[T](x), bit_cast[T](x) or auto_cast(x), and a chain after it.
			Doc cast(const Node* node) {
				// (x).member and the like
				if (is_token(node, TokenType::SYM_LPAREN)) {
					// A string literal's chain, like "abc".count, has no parentheses: the node is where the literal is
					const Node* first = node->children.empty() ? nullptr : node->children[0];
					if (first != nullptr && ast::NodeType::LITERAL == first->node_type && first->value.line_number == node->value.line_number
						&& first->value.column_number == node->value.column_number) {
						return d.concat({ expression(first, ANY), chain(node, 1) });
					}
					if (node->children.empty()) {
						return text("()");
					}
					return d.concat({ parenthesized(expression(node->children[0], ANY)), chain(node, 1) });
				}
				Parts out = parts();
				out << operator_text(node->value.type);
				size_t i = 0;
				if (!is_token(node, TokenType::KEYWORD_AUTO_CAST) && i < node->children.size()) {
					out << "[" << type(node->children[i], true) << "]";
					++i;
				}
				if (i < node->children.size()) {
					out << parenthesized(expression(node->children[i], ANY));
					++i;
				}
				out << chain(node, i);
				return out.doc();
			}

			// Type.{...} or Type.[...], or .{...} for the type expected there.
			Doc typed_literal(const Node* node, std::string_view open, std::string_view close) {
				Parts out = parts();
				if (!is_token(node, TokenType::SYM_DOT)) {
					out << text_of(node);
				}
				const Node* items = nullptr;
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::DOT_ACCESS) {
						out << ".";
					}
					else if (child->node_type == NodeType::IDENTIFIER) {
						out << text_of(child);
					}
					else if (child->node_type == NodeType::GENERIC_TAG) {
						out << generic_list(child);
					}
					else if (child->node_type == NodeType::LIST) {
						items = child;
					}
				}
				out << open;
				if (items == nullptr || items->children.empty()) {
					out << close;
					return out.doc();
				}
				// Each item printed once, as its comments are
				std::vector<Doc> values;
				for (const Node* item : items->children) {
					values.push_back(field_value(item));
				}
				Parts inline_items = parts();
				for (size_t i = 0; i < values.size(); ++i) {
					inline_items << (i > 0 ? ", " : "") << values[i];
				}
				const std::string inline_text = d.render(inline_items.doc(), SIZE_MAX);
				if (inline_text.size() <= 100 && inline_text.find('\n') == std::string::npos && !d.breaks(inline_items.doc())) {
					out << inline_items.doc() << close;
					return out.doc();
				}
				// Long ones, like a table, an item to a line
				std::vector<std::pair<const Node*, Doc>> lines;
				for (size_t i = 0; i < values.size(); ++i) {
					lines.emplace_back(items->children[i], d.concat({ values[i], text(",") }));
				}
				out << item_lines(lines) << nl() << close;
				return out.doc();
			}

			Doc if_expression(const Node* node) {
				Parts out = parts();
				out << "if";
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::BLOCK) {
						out << " " << block(child);
					}
					else if (child->node_type == NodeType::ELSE) {
						out << " else";
						for (const Node* branch : child->children) {
							out << " " << (NodeType::IF == branch->node_type ? if_expression(branch) : block(branch));
						}
					}
					else {
						out << " " << expression(child, ANY);
					}
				}
				return out.doc();
			}

			// A directive in an expression: alone, with an expression (#run x), or with arguments (#align(16)).
			Doc directive(const Node* node) {
				return host(node, directive_bare(node));
			}

			Doc directive_bare(const Node* node) {
				const std::string_view name = text_of(node);
				if (name == "#code") {
					return quote(node);
				}
				Parts out = parts();
				// An #insert in a quote's tree: what its #code splices next, after mut if it's given with mut
				const bool marked_only = std::all_of(node->children.begin(), node->children.end(),
					[](const Node* child) { return NodeType::MUTABLE == child->node_type; });
				if (name == "#insert" && marked_only && !node->children.empty()) {
					out << "mut ";
				}
				out << name;
				if (name == "#insert" && !quotes.empty() && quotes.back().contains(node)) {
					const Node* spliced = quotes.back().find(node)->second;
					// It's printed in the quote around this one
					auto inner = std::move(quotes.back());
					quotes.pop_back();
					out << " " << expression(spliced, PREFIX);
					quotes.push_back(std::move(inner));
					// A member's value, as in #insert name = 3
					for (const Node* child : node->children) {
						if (is_token(child, TokenType::OPERATOR_ASSIGN) && !child->children.empty()) {
							out << " = " << expression(child->children[0], ANY);
						}
					}
					return out.doc();
				}
				if (node->children.empty()) {
					return out.doc();
				}
				if (is_marker(node->children[0]) && NodeType::PAREN_GROUP == node->children[0]->node_type) {
					out << "(";
					for (size_t i = 1; i < node->children.size(); ++i) {
						out << (i > 1 ? ", " : "") << argument(node->children[i]);
					}
					out << ")";
					return out.doc();
				}
				// #insert's operand binds like a prefix operator's; #run's and #assert's is an expression
				const int needed = name == "#insert" ? PREFIX : ANY;
				bool given_mut = false;
				for (const Node* child : node->children) {
					if (NodeType::MUTABLE == child->node_type) {
						given_mut = true;
						continue;
					}
					out << " " << expression(child, needed);
				}
				return d.concat({ given_mut ? text("mut ") : EMPTY, out.doc() });
			}

			// #code(expression) or #code { statements }, with what it splices where its #inserts are.
			Doc quote(const Node* node) {
				const Node* tree = quote_table != nullptr ? quote_table->get(node) : nullptr;
				if (tree == nullptr) {
					return text("#code");
				}
				std::vector<const Node*> placeholders;
				if (NodeType::DIRECTIVE == tree->node_type && text_of(tree) == "#insert") {
					placeholders.push_back(tree);
				}
				else {
					find_placeholders(tree, placeholders);
				}
				std::unordered_map<const Node*, const Node*> operands;
				for (size_t i = 0; i < placeholders.size() && i < node->children.size(); ++i) {
					operands[placeholders[i]] = node->children[i];
				}
				quotes.push_back(std::move(operands));
				Doc out = named_contents(tree);
				if (out != EMPTY) {
					out = d.concat({ text("#code "), out });
				}
				else if (NodeType::BLOCK == tree->node_type) {
					out = d.concat({ text("#code "), block(tree) });
				}
				else {
					out = d.concat({ text("#code"), parenthesized(expression(tree, ANY)) });
				}
				quotes.pop_back();
				return out;
			}

			/*
			 * What goes in something else, named by a word: fields, variants, members, patterns or cases, as
			 * #code quotes them and code made from them is. EMPTY for anything else.
			 */
			Doc named_contents(const Node* tree) {
				const std::string_view word = text_of(tree);
				if (NodeType::STRUCT == tree->node_type && word == "fields") {
					return struct_declaration(tree, "fields");
				}
				if (NodeType::UNION == tree->node_type && word == "variants") {
					return union_declaration(tree, "variants");
				}
				if (NodeType::ENUM == tree->node_type && word == "members") {
					return enum_declaration(tree, "members");
				}
				if (NodeType::LIST == tree->node_type && word == "patterns") {
					return d.concat({ text("patterns "), match_arms(tree) });
				}
				if (NodeType::LIST == tree->node_type && word == "cases") {
					return d.concat({ text("cases "), switch_cases(tree) });
				}
				return EMPTY;
			}
		};
	}

	Formatted format_tree(const Node* file, const QuoteTable* quotes, std::string_view source, const MyVector<Token>& tokens,
		const MyVector<Token>& comments, size_t width, std::string_view newline) {
		Formatted result;
		if (file == nullptr) {
			return result;
		}
		Comments trivia(source, tokens, comments, quotes);
		size_t first = 0;
		size_t last = 0;
		trivia.measure(file, first, last);
		// What the printer prints through host, which comments can go with
		{
			layout::Document scratch;
			Printer printer(scratch);
			printer.quote_table = quotes;
			printer.comments = &trivia;
			trivia.recording = true;
			printer.file(file);
			trivia.recording = false;
		}
		trivia.hosted.insert(file);
		trivia.attach_all(file);

		layout::Document d;
		Printer printer(d);
		printer.quote_table = quotes;
		printer.comments = &trivia;
		printer.comments_printed.assign(comments.size(), false);
		result.text = d.render(printer.file(file), width, newline);
		for (size_t i = 0; i < comments.size(); ++i) {
			if (!printer.comments_printed[i]) {
				result.lost_comments.push_back(comments[i].offset);
			}
		}
		return result;
	}

	std::string source_of(const Node* node, const QuoteTable* quotes) {
		if (node == nullptr) {
			return "";
		}
		layout::Document d;
		Printer printer(d);
		printer.quote_table = quotes;
		if (NodeType::FILE == node->node_type) {
			return d.render(printer.file(node), SIZE_MAX);
		}
		Doc contents = printer.named_contents(node);
		return d.render(contents != EMPTY ? contents : printer.statement(node), SIZE_MAX);
	}

	std::string source_of_statements(const Node* block, const QuoteTable* quotes) {
		if (block == nullptr) {
			return "";
		}
		layout::Document d;
		Printer printer(d);
		printer.quote_table = quotes;
		Parts out(d);
		for (const Node* child : block->children) {
			out << printer.statement(child) << d.hard_line();
		}
		return d.render(out.doc(), SIZE_MAX);
	}

}
