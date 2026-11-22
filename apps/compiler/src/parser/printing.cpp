#include "parser/printing.h"

#include <algorithm>
#include <cstdint>
#include <format>
#include <string_view>
#include <tuple>
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

		/*
		 * W7: a run of at least ALIGNED_RUN similar declarations has its names padded so their : and :: line up,
		 * and a run breaks where that would pad a line by more than ALIGNMENT_LIMIT spaces. Both are to tune once
		 * std and the Vulkan bindings are formatted.
		 */
		constexpr size_t ALIGNED_RUN = 4;
		constexpr size_t ALIGNMENT_LIMIT = 30;

		/*
		 * Whether an if expression whose value is used, with an else and an expression alone in each block, is
		 * on one line where it fits, like x :: if a { b } else { c }, rather than else on a line of its own (L5).
		 */
		constexpr bool ONE_LINE_IF_EXPRESSIONS = true;

		// How tightly an expression binds, by where the parser parses it: an operand needs at least its level.
		enum Level : int {
			ANY = 0,
			ASSIGNMENT = 1,
			// or_else, or_return, or_break, or_continue, and if
			FALLBACK = 2,
			RANGE = 3,
			OR = 4,
			AND = 5,
			// is_none, is_some, is_ok and is_error, after a comparison's operand
			TEST = 6,
			COMPARISON = 7,
			SUM = 8,
			PRODUCT = 9,
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

		// is_none, is_some, is_ok or is_error, with its operand.
		bool is_test(const Node* node) {
			return NodeType::UNARY_OPERATOR == node->node_type && !node->children.empty()
				&& (is_token(node, TokenType::KEYWORD_IS_NONE) || is_token(node, TokenType::KEYWORD_IS_SOME)
					|| is_token(node, TokenType::KEYWORD_IS_OK) || is_token(node, TokenType::KEYWORD_IS_ERROR));
		}

		int level_of(const Node* node) {
			if (node->node_type == NodeType::BINARY_OPERATOR) {
				return binary_level(node->value.type);
			}
			else if (node->node_type == NodeType::UNARY_OPERATOR) {
				if (is_prefix(node) || is_token(node, TokenType::SYM_QUESTION)) {
					return PREFIX;
				}
				if (is_test(node)) {
					return TEST;
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

			/*
			 * open items close, on one line where it fits, and otherwise an item to a line, each indented one
			 * level, with close on a line of its own (B5, B6): a comma after the last item then if
			 * trailing_comma, for the lists docs/formatting.md makes that comma optional in (D3). The items
			 * are indented only when broken, so a block in a flat list's last item isn't. Given the items'
			 * nodes, a broken list keeps the blank lines that were between them (L6).
			 */
			Doc bracketed(std::string_view open, const std::vector<Doc>& items, std::string_view close, bool trailing_comma,
				const std::vector<const Node*>* nodes = nullptr) {
				if (items.empty()) {
					return d.concat({ text(open), text(close) });
				}
				Parts body = parts();
				for (size_t i = 0; i < items.size(); ++i) {
					if (i > 0) {
						body << ",";
						if (nodes != nullptr && blank_before((*nodes)[i])) {
							body << d.if_break(nl());
						}
						body << d.line();
					}
					body << items[i];
				}
				const Doc inside = body.doc();
				/*
				 * Only the last item can run over lines in a flat list, as a block does in f(a, fn() { ... }): one
				 * before it that does breaks the list
				 */
				bool spans_lines = false;
				for (size_t i = 0; i + 1 < items.size(); ++i) {
					spans_lines = spans_lines || d.flat_width(items[i]) == SIZE_MAX;
				}
				return d.group(d.concat({
					spans_lines ? d.break_parent() : EMPTY,
					text(open),
					d.if_break(d.indent(d.concat({ d.soft_line(), inside, trailing_comma ? text(",") : EMPTY })), inside),
					d.soft_line(),
					text(close),
				}));
			}

			template <typename F>
			Doc bracket_list(std::string_view open, const MyVector<Node*>& items, F each, std::string_view close, bool trailing_comma) {
				std::vector<Doc> docs;
				docs.reserve(items.size());
				for (const Node* item : items) {
					docs.push_back(each(item));
				}
				return bracketed(open, docs, close, trailing_comma);
			}


			/*
			 * Each item on a line of its own, one indent deeper, with a blank line before one that had one
			 * (L6), but not the first: what goes between a { and its }. A comment in one doesn't break
			 * the groups around them.
			 */
			Doc item_lines(const std::vector<std::pair<const Node*, Doc>>& items) {
				if (items.empty()) {
					return EMPTY;
				}
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

			static std::string_view trim_end(std::string_view line) {
				while (!line.empty() && (line.back() == ' ' || line.back() == '\t' || line.back() == '\r')) {
					line.remove_suffix(1);
				}
				return line;
			}

			static size_t leading_spaces(std::string_view line) {
				size_t count = 0;
				while (count < line.size() && (line[count] == ' ' || line[count] == '\t')) {
					++count;
				}
				return count;
			}

			// A line comment's text with one space after its // (C1), unless it's empty or a run of slashes.
			static std::string line_comment_text(std::string_view written) {
				written = trim_end(written);
				if (written.size() > 2 && written[2] != ' ' && written[2] != '\t' && written[2] != '/') {
					return "// " + std::string(written.substr(2));
				}
				return std::string(written);
			}

			/*
			 * Where a block tag goes among a doc comment's (C7): @tparam, which the code always puts first, then
			 * @param, @return and @error; -1 for any other.
			 */
			static int tag_rank(std::string_view line) {
				const std::string_view text = line.substr(std::min(line.size(), size_t{ 2 }));
				for (const auto& [tag, rank] : { std::pair{ "@tparam ", 0 }, std::pair{ "@param ", 1 }, std::pair{ "@return ", 2 },
					std::pair{ "@error ", 3 } }) {
					if (text.starts_with(tag) || text == std::string_view(tag).substr(0, std::string_view(tag).size() - 1)) {
						return rank;
					}
				}
				return -1;
			}

			/*
			 * A doc comment's block tags in C7's order, each with its continuation lines, if every line after the
			 * first tag is a tag or a tag's continuation, indented past the *; as they are otherwise. lines are a
			 * block comment's inner lines, each starting with *.
			 */
			static void order_tags(std::vector<std::string>& lines) {
				size_t first = 0;
				while (first < lines.size() && !lines[first].starts_with("* @")) {
					++first;
				}
				if (first == lines.size()) {
					return;
				}
				std::vector<std::vector<std::string>> tags;
				for (size_t i = first; i < lines.size(); ++i) {
					if (lines[i].starts_with("* @")) {
						// A tag C7 doesn't place leaves them all as they are
						if (tag_rank(lines[i]) < 0) {
							return;
						}
						tags.push_back({ lines[i] });
					}
					else if (lines[i].starts_with("*  ")) {
						tags.back().push_back(lines[i]);
					}
					else {
						return;
					}
				}
				std::stable_sort(tags.begin(), tags.end(),
					[](const std::vector<std::string>& a, const std::vector<std::string>& b) { return tag_rank(a[0]) < tag_rank(b[0]); });
				lines.resize(first);
				for (const std::vector<std::string>& tag : tags) {
					lines.insert(lines.end(), tag.begin(), tag.end());
				}
			}

			/*
			 * A block comment of several lines laid out (C3): its opening on a line of its own, each line in it
			 * starting with a * under the opening's, and the closing on a line of its own. A line written
			 * without its * keeps how far it was indented past where the text after a * goes. column is
			 * where the comment started on its line.
			 */
			static std::vector<std::string> block_comment_lines(std::string_view written, size_t column) {
				std::vector<std::string_view> source_lines;
				while (true) {
					const size_t line_end = written.find('\n');
					source_lines.push_back(trim_end(written.substr(0, line_end)));
					if (line_end == std::string_view::npos) {
						break;
					}
					written.remove_prefix(line_end + 1);
				}
				const bool documentation = source_lines[0].starts_with("/**");
				const std::string_view opener = documentation ? "/**" : "/*";
				std::vector<std::string> inner;
				auto add = [&](std::string_view text, size_t indent) {
					if (text.starts_with("*")) {
						inner.emplace_back(text);
					}
					else if (text.empty()) {
						inner.emplace_back("*");
					}
					else {
						// Past where the text after " * " would start
						const size_t extra = indent > column + 3 ? indent - (column + 3) : 0;
						inner.push_back("* " + std::string(extra, ' ') + std::string(text));
					}
				};
				const std::string_view first_text = source_lines[0].substr(opener.size());
				if (!first_text.empty()) {
					add(first_text.substr(leading_spaces(first_text)), column + 3);
				}
				for (size_t i = 1; i < source_lines.size(); ++i) {
					const size_t indent = leading_spaces(source_lines[i]);
					std::string_view text = source_lines[i].substr(indent);
					if (i + 1 == source_lines.size()) {
						// The closing, alone or after the last line's text
						text.remove_suffix(std::min(text.size(), size_t{ 2 }));
						text = trim_end(text);
						if (text.empty() || text == "*") {
							break;
						}
					}
					add(text, indent);
				}
				if (documentation) {
					order_tags(inner);
				}
				std::vector<std::string> lines{ std::string(opener) };
				for (const std::string& line : inner) {
					lines.push_back(" " + line);
				}
				lines.emplace_back(" */");
				return lines;
			}

			/*
			 * A comment laid out by C1 and C3, without spaces at its lines' ends, its lines indented with the
			 * code it's in (C4). A one-line block comment stays as written.
			 */
			Doc comment(uint32_t index) {
				const Token& token = comments->comments[index];
				comments_printed[index] = true;
				const std::string_view written = comments->source.substr(token.offset, token.length);
				if (comments->is_line_comment(index)) {
					return one_line_or_block(index, line_comment_text(written));
				}
				if (written.find('\n') == std::string_view::npos) {
					return one_line_or_block(index, std::string(trim_end(written)));
				}
				size_t line_start = token.offset;
				while (line_start > 0 && comments->source[line_start - 1] != '\n') {
					--line_start;
				}
				Parts out = parts();
				const std::vector<std::string> lines = block_comment_lines(written, token.offset - line_start);
				for (size_t i = 0; i < lines.size(); ++i) {
					out << (i > 0 ? nl() : EMPTY) << lines[i];
				}
				return out.doc();
			}

			// Whether text holds a block comment's opening or closing, which can't go in one, as block comments nest.
			static bool has_block_marker(std::string_view text) {
				return text.find("/*") != std::string_view::npos || text.find("*/") != std::string_view::npos;
			}

			/*
			 * The words of a one-line comment, as written: a line comment's after its slashes, or a block comment's
			 * between its markers. Empty if they can't go in a block comment of their own: a run of slashes, a
			 * block comment's markers in them, or a hemera-format switch.
			 */
			static std::string_view block_words(std::string_view written) {
				std::string_view words;
				if (written.starts_with("//")) {
					if (written.starts_with("///") || is_format_switch(written)) {
						return {};
					}
					words = written.substr(2);
				}
				else if (written.starts_with("/*") && written.ends_with("*/") && written.size() >= 5) {
					const size_t opener = written.starts_with("/**") && written.size() >= 6 ? 3 : 2;
					words = written.substr(opener, written.size() - opener - 2);
				}
				words = trim_end(words);
				words.remove_prefix(std::min(words.size(), leading_spaces(words)));
				return has_block_marker(words) ? std::string_view{} : words;
			}

			/*
			 * A one-line comment, line written as C1 lays it out, as it is where it fits, and otherwise, when it's
			 * on a line of its own, made a block comment of one line (a doc comment staying one), which C5 then
			 * breaks.
			 */
			Doc one_line_or_block(uint32_t index, const std::string& line) {
				const std::string_view words = block_words(line);
				if (words.empty() || comments->breaks_before(comments->start_of(index)) == 0
					|| !comments->ends_line(comments->end_of(index))) {
					return text(line);
				}
				const std::string_view opener = line.starts_with("/**") ? "/**" : "/*";
				return d.group(d.if_break(
					d.concat({ text(opener), nl(), text(" * " + std::string(words)), nl(), text(" */") }),
					text(line)));
			}

			/*
			 * Whether a comment is a line comment on a line of its own, which a run of becomes one block (C2): not
			 * one whose words can't go in a block comment.
			 */
			bool joins_comment_run(uint32_t index) const {
				if (!comments->is_line_comment(index) || comments->breaks_before(comments->start_of(index)) == 0) {
					return false;
				}
				const Token& token = comments->comments[index];
				const std::string_view written = comments->source.substr(token.offset, token.length);
				return !is_format_switch(written) && !has_block_marker(written.substr(2));
			}

			// // hemera-format: off or on, which stays a line comment of its own.
			static bool is_format_switch(std::string_view written) {
				const std::string text = line_comment_text(written);
				return text == "// hemera-format: off" || text == "// hemera-format: on";
			}

			/*
			 * list[i], or the run of line comments starting there, each on a line of its own right after the one
			 * before, as one block (C2). i moves to the last comment taken.
			 */
			Doc comment_or_run(const std::vector<uint32_t>& list, size_t& i) {
				size_t last = i;
				if (joins_comment_run(list[i])) {
					while (last + 1 < list.size() && joins_comment_run(list[last + 1])
						&& comments->breaks_between(comments->end_of(list[last]), comments->start_of(list[last + 1])) == 1) {
						++last;
					}
				}
				if (last == i) {
					return comment(list[i]);
				}
				Parts out = parts();
				out << "/*";
				for (size_t k = i; k <= last; ++k) {
					comments_printed[list[k]] = true;
					const Token& token = comments->comments[list[k]];
					const std::string text = line_comment_text(comments->source.substr(token.offset, token.length));
					std::string_view words = std::string_view(text).substr(2);
					if (!words.empty() && words[0] == ' ') {
						words.remove_prefix(1);
					}
					out << nl() << (words.empty() ? std::string(" *") : " * " + std::string(words));
				}
				out << nl() << " */";
				i = last;
				return out.doc();
			}

			// Whether a comment is documentation, /** ... */.
			bool is_documentation(uint32_t index) const {
				const Token& token = comments->comments[index];
				return comments->source.substr(token.offset, token.length).starts_with("/**")
					&& !comments->source.substr(token.offset, token.length).starts_with("/**/");
			}

			/*
			 * doc with node's comments around it: leading ones before it, each on its own line if it was or
			 * if it's a line comment; trailing ones after it, at its line's end if they ended their line
			 * and on lines of their own after it if they had one; dangling ones as trailing ones, unless the
			 * caller prints them (a block). Each is printed once, wherever node is printed first. With
			 * blank_after_leading, a blank line follows the leading comments unless the last documents node,
			 * as a file's do (D1).
			 */
			Doc host(const Node* node, Doc doc, bool with_dangling = true, bool blank_after_leading = false) {
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
					const Doc written = comment_or_run(attached.leading, i);
					const uint32_t index = attached.leading[i];
					const uint32_t next = i + 1 < attached.leading.size() ? comments->start_of(attached.leading[i + 1]) : span.start;
					size_t breaks = comments->breaks_between(comments->end_of(index), next);
					if (blank_after_leading && i + 1 == attached.leading.size() && !is_documentation(index)) {
						breaks = 2;
					}
					out << written;
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
				for (size_t i = 0; i < after.size(); ++i) {
					uint32_t index = after[i];
					const size_t breaks = comments->breaks_between(end, comments->start_of(index));
					if (breaks > 0) {
						// On lines of its own, maybe a run of line comments
						const Doc written = comment_or_run(after, i);
						index = after[i];
						end = comments->end_of(index);
						out << d.line_suffix(d.concat({ nl(), breaks > 1 ? nl() : EMPTY, written })) << d.break_parent();
						at_line_end = true;
						continue;
					}
					end = comments->end_of(index);
					// Whether it ends its line in the source, so it ends its line here too
					const bool ends_line = comments->ends_line(end);
					if (at_line_end || ends_line || comments->is_line_comment(index)) {
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

			/*
			 * A file (D1): its leading comments, the package statement, its imports in order (D2), then its
			 * declarations, a blank line between each of those and the next (L6), and blank lines between
			 * declarations where there were some, at most one in a row.
			 */
			Doc file(const Node* node) {
				Parts out = parts();
				const auto& children = node->children;
				size_t i = 0;
				if (i < children.size() && NodeType::PACKAGE == children[i]->node_type) {
					const Node* package = children[i];
					const std::string_view name = package->children.empty() ? std::string_view() : text_of(package->children[0]);
					out << host(package, d.concat({ text("package "), text(name) }), true, true) << nl();
					++i;
					if (i < children.size()) {
						out << nl();
					}
				}
				// The imports right after it, sorted, one to a line with no blank lines between them
				const size_t first_import = i;
				while (i < children.size() && NodeType::IMPORT == children[i]->node_type) {
					++i;
				}
				std::vector<const Node*> imports(children.begin() + static_cast<std::ptrdiff_t>(first_import),
					children.begin() + static_cast<std::ptrdiff_t>(i));
				// The comments before the first import head them all, so they stay first
				if (!imports.empty() && comments != nullptr && !comments->recording) {
					auto found = comments->attached.find(imports.front());
					if (found != comments->attached.end()) {
						std::vector<uint32_t>& leading = found->second.leading;
						for (size_t k = 0; k < leading.size(); ++k) {
							const Doc written = comment_or_run(leading, k);
							const uint32_t next = k + 1 < leading.size() ? comments->start_of(leading[k + 1])
								: comments->extent(imports.front()).start;
							out << written << nl();
							if (comments->breaks_between(comments->end_of(leading[k]), next) > 1) {
								out << nl();
							}
						}
						leading.clear();
					}
				}
				std::stable_sort(imports.begin(), imports.end(),
					[](const Node* a, const Node* b) { return import_order(a) < import_order(b); });
				for (const Node* import_node : imports) {
					out << top_level(import_node) << nl();
				}
				if (!imports.empty() && i < children.size()) {
					out << nl();
				}
				std::vector<Entry> entries;
				for (; i < children.size(); ++i) {
					entries.push_back(entry_for(children[i], EMPTY));
				}
				const std::vector<std::pair<const Node*, Doc>> lines = aligned(entries);
				for (size_t k = 0; k < lines.size(); ++k) {
					if (k > 0 && blank_before(lines[k].first)) {
						out << nl();
					}
					out << lines[k].second << nl();
				}
				// Comments in a file with nothing else in it
				if (comments != nullptr && !comments->recording) {
					auto found = comments->attached.find(node);
					if (found != comments->attached.end()) {
						const std::vector<uint32_t>& dangling = found->second.dangling;
						for (size_t k = 0; k < dangling.size(); ++k) {
							out << comment_or_run(dangling, k) << nl();
						}
					}
				}
				return out.doc();
			}

			/*
			 * Where an import goes among a file's (D2): by its location's built-in prefix (base, std, user,
			 * vendor, then a relative folder), then the location's path, then the name. An import with no
			 * location is std's package of its name.
			 */
			static std::tuple<int, std::string_view, std::string_view> import_order(const Node* node) {
				std::string_view name;
				std::string_view location;
				for (size_t i = 0; i < node->children.size(); ++i) {
					const Node* child = node->children[i];
					if (NodeType::KEYWORD_FROM == child->node_type && i + 1 < node->children.size()) {
						location = text_of(node->children[i + 1]);
						++i;
					}
					else if (name.empty() && NodeType::IDENTIFIER == child->node_type) {
						name = text_of(child);
					}
				}
				if (location.size() >= 2 && location.front() == '"' && location.back() == '"') {
					location = location.substr(1, location.size() - 2);
				}
				if (location.empty()) {
					return { 1, name, name };
				}
				const size_t colon = location.find(':');
				if (colon == std::string_view::npos) {
					return { 4, location, name };
				}
				const std::string_view prefix = location.substr(0, colon);
				const int rank = prefix == "base" ? 0 : prefix == "std" ? 1 : prefix == "user" ? 2 : prefix == "vendor" ? 3 : 4;
				return { rank, location.substr(colon + 1), name };
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
					std::vector<Entry> entries;
					for (size_t i = first; i < node->children.size(); ++i) {
						entries.push_back(entry_for(node->children[i], EMPTY));
					}
					out << " {" << item_lines(aligned(entries)) << nl() << "}";
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
			 * A declaration in parts, so a run of them can be lined up (W7): its name, its type if one is
			 * written, and what follows them, like " :: value". Its shape says which runs it can be in.
			 */
			struct Declaration {
				enum class Shape {
					// Not lined up with others, like a variable, a function or anything with annotations
					OTHER,
					// NAME :: value
					CONSTANT,
					// NAME : Type : value
					TYPED_CONSTANT,
					// A struct's name : Type, or name : Type = default
					FIELD,
					FIELD_WITH_DEFAULT,
					// An enum's NAME = value
					MEMBER,
				};

				Shape shape = Shape::OTHER;
				// Annotations, each on a line of its own, and using
				Doc prefix = EMPTY;
				Doc name = EMPTY;
				Doc type = EMPTY;
				Doc rest = EMPTY;
			};

			Doc spaces(size_t count) {
				return count == 0 ? EMPTY : text(std::string(count, ' '));
			}

			// declaration with its name padded by name_pad spaces and its type, if what follows it is padded, by type_pad.
			Doc join(const Declaration& declaration, size_t name_pad, size_t type_pad) {
				Parts out = parts();
				out << declaration.prefix << declaration.name << spaces(name_pad);
				if (declaration.type != EMPTY) {
					out << " : " << declaration.type << (declaration.rest != EMPTY ? spaces(type_pad) : EMPTY);
				}
				out << declaration.rest;
				return out.doc();
			}

			/*
			 * A definition: names, the type if one is written, then :: or : for a constant, := or = for a
			 * variable, and the value. Annotations, which follow everything, go before it, a line each.
			 */
			Doc definition(const Node* node) {
				return host(node, join(declaration(node), 0, 0));
			}

			Declaration declaration(const Node* node) {
				Declaration out;
				Parts prefix = parts();
				if (!node->children.empty()) {
					// A name reads as one, so it never breaks
					out.name = d.flat(names(node->children[0]));
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
					out.type = type(written_type, false);
				}
				Parts rest = parts();
				if (i < node->children.size()) {
					const bool constant = NodeType::COLON == node->children[i]->node_type;
					// A value that starts on the next line, like a multiline string, has no space before it
					const bool next_line = i + 1 < node->children.size() && is_multiline_string(node->children[i + 1]);
					if (written_type != nullptr) {
						rest << (constant ? " :" : " =");
						out.shape = constant ? Declaration::Shape::TYPED_CONSTANT : Declaration::Shape::FIELD_WITH_DEFAULT;
					}
					else {
						rest << (constant ? " ::" : " :=");
						out.shape = constant ? Declaration::Shape::CONSTANT : Declaration::Shape::OTHER;
					}
					if (!next_line) {
						rest << " ";
					}
					++i;
					rest << value(node, i, prefix, is_using);
				}
				else if (written_type == nullptr) {
					rest << " :";
				}
				else {
					out.shape = Declaration::Shape::FIELD;
				}
				out.rest = rest.doc();
				out.prefix = d.concat({ prefix.doc(), is_using ? text("using ") : EMPTY });
				if (out.prefix != EMPTY) {
					out.shape = Declaration::Shape::OTHER;
				}
				return out;
			}

			/*
			 * A line of a list of declarations: one, or something else in the list, like an #insert, with what
			 * follows it, like a struct field's comma.
			 */
			struct Entry {
				const Node* node = nullptr;
				bool is_declaration = false;
				Declaration declaration;
				Doc other = EMPTY;
				Doc after = EMPTY;
			};

			static bool same_run(Declaration::Shape a, Declaration::Shape b) {
				const bool a_field = Declaration::Shape::FIELD == a || Declaration::Shape::FIELD_WITH_DEFAULT == a;
				const bool b_field = Declaration::Shape::FIELD == b || Declaration::Shape::FIELD_WITH_DEFAULT == b;
				return a == b || (a_field && b_field);
			}

			// Whether a declaration's type is padded in a run: when something follows it, like a default or value.
			static bool pads_type(Declaration::Shape shape) {
				return Declaration::Shape::TYPED_CONSTANT == shape || Declaration::Shape::FIELD_WITH_DEFAULT == shape;
			}

			bool has_leading_comment(const Node* node) const {
				if (comments == nullptr || comments->recording) {
					return false;
				}
				auto found = comments->attached.find(node);
				return found != comments->attached.end() && !found->second.leading.empty();
			}

			/*
			 * The entries' lines, each with its comments, lined up in runs (W7): a run is ALIGNED_RUN or more
			 * declarations of one shape, each on one line, in a row without a blank line or a comment on a line of
			 * its own between them, broken where lining them up would pad a line more than ALIGNMENT_LIMIT.
			 */
			std::vector<std::pair<const Node*, Doc>> aligned(const std::vector<Entry>& entries) {
				const size_t count = entries.size();
				std::vector<size_t> name_widths(count, 0);
				std::vector<size_t> type_widths(count, 0);
				std::vector<bool> can_align(count, false);
				for (size_t i = 0; i < count; ++i) {
					const Entry& entry = entries[i];
					if (!entry.is_declaration || Declaration::Shape::OTHER == entry.declaration.shape) {
						continue;
					}
					name_widths[i] = d.flat_width(entry.declaration.name);
					type_widths[i] = d.flat_width(entry.declaration.type);
					can_align[i] = d.flat_width(join(entry.declaration, 0, 0)) != SIZE_MAX && name_widths[i] != SIZE_MAX
						&& type_widths[i] != SIZE_MAX;
				}
				std::vector<size_t> name_pads(count, 0);
				std::vector<size_t> type_pads(count, 0);
				size_t start = 0;
				auto close_run = [&](size_t end) {
					if (end > start && end - start >= ALIGNED_RUN) {
						size_t widest_name = 0;
						size_t widest_type = 0;
						for (size_t k = start; k < end; ++k) {
							widest_name = std::max(widest_name, name_widths[k]);
							if (pads_type(entries[k].declaration.shape)) {
								widest_type = std::max(widest_type, type_widths[k]);
							}
						}
						for (size_t k = start; k < end; ++k) {
							name_pads[k] = widest_name - name_widths[k];
							type_pads[k] = pads_type(entries[k].declaration.shape) ? widest_type - type_widths[k] : 0;
						}
					}
					start = end;
				};
				// The widths a run would span with entry i in it
				auto too_wide = [&](size_t i) {
					size_t narrowest_name = name_widths[i];
					size_t widest_name = name_widths[i];
					size_t narrowest_type = SIZE_MAX;
					size_t widest_type = 0;
					for (size_t k = start; k <= i; ++k) {
						narrowest_name = std::min(narrowest_name, name_widths[k]);
						widest_name = std::max(widest_name, name_widths[k]);
						if (pads_type(entries[k].declaration.shape)) {
							narrowest_type = std::min(narrowest_type, type_widths[k]);
							widest_type = std::max(widest_type, type_widths[k]);
						}
					}
					return widest_name - narrowest_name > ALIGNMENT_LIMIT
						|| (narrowest_type != SIZE_MAX && widest_type - narrowest_type > ALIGNMENT_LIMIT);
				};
				for (size_t i = 0; i < count; ++i) {
					if (!can_align[i]) {
						close_run(i);
						start = i + 1;
						continue;
					}
					if (i > start && (!same_run(entries[start].declaration.shape, entries[i].declaration.shape)
						|| blank_before(entries[i].node) || has_leading_comment(entries[i].node) || too_wide(i))) {
						close_run(i);
					}
				}
				close_run(count);

				std::vector<std::pair<const Node*, Doc>> lines;
				lines.reserve(count);
				for (size_t i = 0; i < count; ++i) {
					const Entry& entry = entries[i];
					const Doc doc = entry.is_declaration ? join(entry.declaration, name_pads[i], type_pads[i]) : entry.other;
					lines.emplace_back(entry.node, d.concat({ host(entry.node, doc), entry.after }));
				}
				return lines;
			}

			// A list's entry for something that isn't a declaration, like an #insert.
			static Entry other_entry(const Node* node, Doc doc, Doc after) {
				Entry entry;
				entry.node = node;
				entry.other = doc;
				entry.after = after;
				return entry;
			}

			// A list's entry for a declaration, or for node printed as other if it isn't one.
			Entry entry_for(const Node* node, Doc after) {
				Entry entry;
				entry.node = node;
				entry.after = after;
				if (NodeType::DEFINITION == node->node_type) {
					entry.is_declaration = true;
					entry.declaration = declaration(node);
				}
				else {
					entry.other = top_level(node);
				}
				return entry;
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

			// " { lines }", where lines start with their line breaks, or " {}" for none.
			Doc braces(Doc lines) {
				if (lines == EMPTY) {
					return text(" {}");
				}
				return d.concat({ text(" {"), lines, nl(), text("}") });
			}

			// keyword is struct, or fields for a quote of a struct's fields
			Doc struct_declaration(const Node* node, std::string_view keyword = "struct") {
				Parts out = parts();
				out << keyword;
				std::vector<Entry> members;
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::GENERIC_TAG) {
						out << generic_list(child);
					}
					else if (is_insert(child)) {
						members.push_back(other_entry(child, directive(child), text(",")));
					}
					else if (child->node_type == NodeType::DIRECTIVE) {
						out << " " << directive(child);
					}
					else if (child->node_type == NodeType::WHERE_CLAUSE) {
						out << where_clause(child);
					}
					else if (child->node_type == NodeType::USING) {
						members.push_back(other_entry(child, d.concat({ text("using "), qualified(child, 0) }), text(",")));
					}
					else {
						members.push_back(entry_for(child, text(",")));
					}
				}
				out << braces(item_lines(aligned(members)));
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
							variant << bracket_list("(", node->children[++i]->children, [&](const Node* t) { return type(t, false); }, ")", false);
						}
						variants.emplace_back(child, d.concat({ host(child, variant.doc()), text(",") }));
					}
				}
				out << braces(item_lines(variants));
				return out.doc();
			}

			// keyword is enum, or members for a quote of an enum's members
			Doc enum_declaration(const Node* node, std::string_view keyword = "enum") {
				Parts out = parts();
				out << keyword;
				std::vector<Entry> members;
				for (const Node* child : node->children) {
					if (is_insert(child)) {
						members.push_back(other_entry(child, directive(child), text(",")));
						continue;
					}
					if (NodeType::DIRECTIVE == child->node_type) {
						out << " " << directive(child);
						continue;
					}
					Entry member;
					member.node = child;
					member.is_declaration = true;
					member.after = text(",");
					member.declaration.name = text(text_of(child));
					Parts value = parts();
					for (const Node* assign : child->children) {
						if (!assign->children.empty()) {
							value << " = " << expression(assign->children[0], ANY);
						}
					}
					member.declaration.rest = value.doc();
					member.declaration.shape = member.declaration.rest != EMPTY ? Declaration::Shape::MEMBER : Declaration::Shape::OTHER;
					members.push_back(member);
				}
				out << braces(item_lines(aligned(members)));
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
				// Generic arguments never break, a function type in them included: a type reads as one
				return d.flat(d.concat({ text("["), list(node->children, [&](const Node* item) { return generic_item(item); }), text("]") }));
			}

			Doc generic_item(const Node* node) {
				return host(node, generic_item_bare(node));
			}

			Doc generic_item_bare(const Node* node) {
				if (NodeType::COLON == node->node_type && node->children.size() == 2) {
					return d.concat({ text(text_of(node->children[0])), text(" : "), type(node->children[1], true) });
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
							out << bracket_list("(", child->children, [&](const Node* p) { return parameter(p); }, ")", false);
						}
						else {
							out << " -> " << results(child);
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
				return d.concat({ out, text(" : "), type_text, is_varargs ? text("...") : EMPTY });
			}

			Doc varargs(const Node* node) {
				for (const Node* child : node->children) {
					if (NodeType::ELLIIPSIS == child->node_type) {
						return text("...");
					}
				}
				return EMPTY;
			}

			// Several results: types, or names sharing the type after a COLON, like a : u16, b, c : f32.
			/*
			 * A function's results in parentheses, each a type or name : type, broken like parameters where they
			 * don't fit once the parameters have broken (B5).
			 */
			Doc results(const Node* node) {
				std::vector<Doc> items;
				const MyVector<Node*>& children = node->children;
				for (size_t i = 0; i < children.size(); ++i) {
					if (i + 2 < children.size() && NodeType::COLON == children[i + 1]->node_type) {
						items.push_back(d.concat({ type(children[i], true), text(" : "), type(children[i + 2], true) }));
						i += 2;
					}
					else {
						items.push_back(type(children[i], true));
					}
				}
				return bracketed("(", items, ")", false);
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
				const std::vector<uint32_t>& dangling = found->second.dangling;
				for (size_t k = 0; k < dangling.size(); ++k) {
					out << nl() << comment_or_run(dangling, k);
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
				else if (node->node_type == NodeType::IF) {
					return if_expression(node, true);
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
						out << " " << bracket_list("(", child->children, [&](const Node* assign) { return field_value(assign); }, ")", true);
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

			// A switch's cases, in braces, each one indent deeper than the switch and its statements one more.
			Doc switch_cases(const Node* cases) {
				Parts out = parts();
				bool first = true;
				for (const Node* item : cases->children) {
					if (!first && blank_before(item)) {
						out << nl();
					}
					first = false;
					if (NodeType::DIRECTIVE == item->node_type) {
						out << nl() << directive(item);
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
					// A block alone goes on the case's line, as case .A: { ... }
					const bool one_block = body != nullptr && body->children.size() == 1 && NodeType::BLOCK == body->children[0]->node_type;
					if (one_block) {
						const Doc block_doc = statement(body->children[0]);
						out << nl() << host(item, d.concat({ text("case "), entries.doc(), text(": "), block_doc }));
						continue;
					}
					// A statement alone stays on the case's line where it fits, as case 1: x += 1 (B7)
					if (body != nullptr && body->children.size() == 1) {
						const Doc statement_doc = statement(body->children[0]);
						if (d.flat_width(statement_doc) != SIZE_MAX) {
							const Doc one_line = d.group(d.concat({
								text("case "), entries.doc(), text(":"), d.indent(d.concat({ d.line(), statement_doc })),
							}));
							out << nl() << host(item, one_line);
							continue;
						}
						out << nl() << host(item, d.concat({ text("case "), entries.doc(), text(":"), d.indent(d.concat({ nl(), statement_doc })) }));
						continue;
					}
					const Doc statements = body != nullptr ? statement_lines(body) : EMPTY;
					out << nl() << host(item, d.concat({ text("case "), entries.doc(), text(":"), statements }));
				}
				return d.concat({ text("{"), d.indent(d.isolate(out.doc())), nl(), text("}") });
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
							out << bracket_list("(", child->children, [&](const Node* p) { return case_entry(p); }, ")", false);
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
					return if_expression(node, false);
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

			/*
			 * A literal as written. A multiline string, a line per token each starting with \\, starts on the
			 * next line, its lines 4 deeper than the line it's on (L3).
			 */
			Doc literal(const Node* node) {
				if (!is_multiline_string(node)) {
					return text(text_of(node));
				}
				Parts out = parts();
				out << nl() << string_line(text_of(node));
				for (const Node* line : node->children) {
					out << nl() << string_line(text_of(line));
				}
				return d.indent(out.doc());
			}

			// A multiline string's line, without the line break its token's text ends with.
			static std::string_view string_line(std::string_view line) {
				while (!line.empty() && (line.back() == '\n' || line.back() == '\r')) {
					line.remove_suffix(1);
				}
				return line;
			}

			static bool is_multiline_string(const Node* node) {
				return NodeType::LITERAL == node->node_type && text_of(node).starts_with("\\\\");
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
					std::vector<Doc> inside;
					while (i < children.size() && !is_marker(children[i])) {
						const Node* item = children[i];
						inside.push_back(call ? argument(item) : index(item));
						++i;
					}
					if (call) {
						out << bracketed("(", inside, ")", false);
						continue;
					}
					// An index or type arguments never break, as a type's don't
					out << "[";
					for (size_t k = 0; k < inside.size(); ++k) {
						out << (k > 0 ? ", " : "") << inside[k];
					}
					out << "]";
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
				// A match or block ends at its }, so it can be an argument without parentheses, before a , or )
				if (NodeType::MATCH == node->node_type || NodeType::BLOCK == node->node_type) {
					return expression(node, ANY);
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
							out << bracket_list("(", part->children, [&](const Node* a) { return argument(a); }, ")", false);
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
					left = TEST;
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
				if (rhs != nullptr && ASSIGNMENT != level && RANGE != level && NodeType::VOID != rhs->node_type) {
					return operator_run(node, level, left, right);
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

			// A binary operation at level, of two operands, that operator_run takes into its run.
			static bool joins_run(const Node* node, int level) {
				return NodeType::BINARY_OPERATOR == node->node_type && node->children.size() == 2
					&& !is_token(node, TokenType::OPERATOR_PIPE) && binary_level(node->value.type) == level;
			}

			/*
			 * a && b && c: the operands of one level's operators in a row, the side they group to taken in, on
			 * one line where they fit, and otherwise each operator starting a line of its own (B3), all of
			 * them at once (B2), 4 deeper than the first operand (L3). left and right are what each side has
			 * to be.
			 */
			Doc operator_run(const Node* node, int level, int left, int right) {
				// Each operand, with the operator before it (none before the first)
				std::vector<std::pair<TokenType, const Node*>> operands;
				if (left == level) {
					// Grouping to the left, like a + b + c, which is (a + b) + c
					std::vector<const Node*> spine;
					const Node* at = node;
					while (joins_run(at, level)) {
						spine.push_back(at);
						at = at->children[0];
					}
					operands.emplace_back(TokenType::START_OF_FILE, at);
					for (size_t i = spine.size(); i > 0; --i) {
						operands.emplace_back(spine[i - 1]->value.type, spine[i - 1]->children[1]);
					}
				}
				else {
					// Grouping to the right, like a || b || c, which is a || (b || c), or not grouping at all
					const Node* at = node;
					TokenType op = TokenType::START_OF_FILE;
					while (right == level && joins_run(at, level)) {
						operands.emplace_back(op, at->children[0]);
						op = at->value.type;
						at = at->children[1];
					}
					if (at == node) {
						operands.emplace_back(op, at->children[0]);
						op = at->value.type;
						at = at->children[1];
					}
					operands.emplace_back(op, at);
				}
				Parts rest = parts();
				for (size_t i = 1; i < operands.size(); ++i) {
					// The last operand on the side it groups to takes that side's level, the rest the other's
					const bool right_side = left == level || i + 1 == operands.size();
					rest << d.line() << operator_text(operands[i].first) << " " << expression(operands[i].second, right_side ? right : left);
				}
				const Doc first = expression(operands[0].second, left);
				return d.group(d.concat({ first, d.indent(rest.doc()) }));
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
				// A test's operand is a comparison's; or_break's and or_continue's, a range's
				return d.concat({ expression(operand, is_test(node) ? COMPARISON : RANGE), text(" "), text(operator_text(op)) });
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

			// name = value in a struct literal, naming the field it sets.
			static bool is_named_field(const Node* item) {
				return NodeType::BINARY_OPERATOR == item->node_type && is_token(item, TokenType::OPERATOR_ASSIGN)
					&& item->children.size() == 2 && NodeType::IDENTIFIER == item->children[0]->node_type
					&& item->children[0]->children.empty();
			}

			// A number or character, maybe negated: an item B8 packs.
			static bool is_number(const Node* item) {
				if (NodeType::UNARY_OPERATOR == item->node_type && is_token(item, TokenType::OPERATOR_MINUS) && item->children.size() == 1) {
					item = item->children[0];
				}
				return NodeType::LITERAL == item->node_type && item->children.empty()
					&& (is_token(item, TokenType::LITERAL_INTEGER) || is_token(item, TokenType::LITERAL_FLOATING_POINT)
						|| is_token(item, TokenType::LITERAL_CHAR) || is_token(item, TokenType::LITERAL_IMAGINARY));
			}

			// open items close on one line where it fits, and otherwise as many items to a line as fit (B8).
			Doc packed(std::string_view open, const std::vector<Doc>& items, const std::vector<const Node*>& nodes, std::string_view close) {
				Parts flat = parts();
				std::vector<Doc> lines;
				for (size_t i = 0; i < items.size(); ++i) {
					const bool last = i + 1 == items.size();
					flat << (i > 0 ? ", " : "") << items[i];
					lines.push_back(last ? items[i] : d.concat({ items[i], text(",") }));
					if (!last) {
						// An item with a comment before it, or a blank line, starts a line, as it heads what follows
						const Node* next = nodes[i + 1];
						if (has_leading_comment(next) || blank_before(next)) {
							lines.push_back(d.concat({ nl(), blank_before(next) ? nl() : EMPTY }));
						}
						else {
							lines.push_back(d.line());
						}
					}
				}
				const Doc broken = d.concat({ d.indent(d.concat({ d.soft_line(), d.fill(lines) })), d.soft_line() });
				return d.group(d.concat({ text(open), d.if_break(broken, flat.doc()), text(close) }));
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
				if (items == nullptr || items->children.empty()) {
					out << open << close;
					return out.doc();
				}
				std::vector<Doc> values;
				std::vector<const Node*> nodes;
				bool named = true;
				bool numbers = true;
				for (const Node* item : items->children) {
					values.push_back(field_value(item));
					nodes.push_back(item);
					named = named && is_named_field(item);
					numbers = numbers && is_number(item);
				}
				if (close == "]" && numbers) {
					out << packed(open, values, nodes, close);
					return out.doc();
				}
				// A struct literal's trailing comma is optional only where its fields are named (D3)
				out << bracketed(open, values, close, close == "}" && named, &nodes);
				return out.doc();
			}

			/*
			 * Whether an if expression whose value is used, like a constant's, can be on one line, as
			 * if a { b } else { c } (ONE_LINE_IF_EXPRESSIONS): it has an else, and each of its blocks holds a
			 * single expression.
			 */
			static bool is_short_if(const Node* node) {
				bool has_else = false;
				for (const Node* child : node->children) {
					if (NodeType::BLOCK == child->node_type) {
						if (child->children.size() != 1 || !is_short_value(child->children[0])) {
							return false;
						}
					}
					else if (NodeType::ELSE == child->node_type) {
						has_else = true;
						for (const Node* branch : child->children) {
							const bool short_branch = NodeType::IF == branch->node_type ? is_short_if(branch)
								: branch->children.size() == 1 && is_short_value(branch->children[0]);
							if (!short_branch) {
								return false;
							}
						}
					}
				}
				return has_else;
			}

			// An expression a short if's block can hold: not a statement, a block or another if.
			static bool is_short_value(const Node* node) {
				return NodeType::DEFINITION != node->node_type && NodeType::RETURN != node->node_type
					&& NodeType::BREAK != node->node_type && NodeType::CONTINUE != node->node_type
					&& NodeType::DEFER != node->node_type && NodeType::GIVE != node->node_type
					&& NodeType::FOR_LOOP != node->node_type && NodeType::LOOP != node->node_type
					&& NodeType::SWITCH != node->node_type && NodeType::MATCH != node->node_type
					&& NodeType::IF != node->node_type && NodeType::BLOCK != node->node_type
					&& NodeType::DIRECTIVE != node->node_type && NodeType::PUSH_CONTEXT != node->node_type
					&& NodeType::USING != node->node_type && !(NodeType::BINARY_OPERATOR == node->node_type
						&& is_assignment(node->value.type));
			}

			// { value }, broken as a block is where the if it's in is.
			Doc short_block(const Node* node) {
				return host(node, d.concat({ text("{"), d.indent(d.concat({ d.line(), statement(node->children[0]) })), d.line(), text("}") }));
			}

			/*
			 * if condition { ... }, then else and what follows it on the next line (L5). An if whose value is
			 * used and is_short_if is on one line where it fits, unless it's a statement (in_statement).
			 */
			Doc if_expression(const Node* node, bool in_statement) {
				const bool one_line = ONE_LINE_IF_EXPRESSIONS && !in_statement && is_short_if(node);
				return if_chain(node, one_line);
			}

			Doc if_chain(const Node* node, bool one_line) {
				Parts out = parts();
				out << "if";
				for (const Node* child : node->children) {
					if (child->node_type == NodeType::BLOCK) {
						out << " " << (one_line ? short_block(child) : block(child));
					}
					else if (child->node_type == NodeType::ELSE) {
						out << (one_line ? d.line() : nl()) << "else";
						for (const Node* branch : child->children) {
							out << " " << (NodeType::IF == branch->node_type ? host(branch, if_chain(branch, one_line))
								: one_line ? short_block(branch) : block(branch));
						}
					}
					else {
						out << " " << expression(child, ANY);
					}
				}
				return one_line ? d.group(out.doc()) : out.doc();
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
					std::vector<Doc> arguments;
					for (size_t i = 1; i < node->children.size(); ++i) {
						arguments.push_back(argument(node->children[i]));
					}
					out << bracketed("(", arguments, ")", false);
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

	namespace {
		// text's lines, without their line endings.
		std::vector<std::string_view> lines_of(std::string_view text) {
			std::vector<std::string_view> lines;
			size_t start = 0;
			while (start < text.size()) {
				size_t end = text.find('\n', start);
				if (end == std::string_view::npos) {
					end = text.size();
				}
				std::string_view line = text.substr(start, end - start);
				if (!line.empty() && line.back() == '\r') {
					line.remove_suffix(1);
				}
				lines.push_back(line);
				start = end + 1;
			}
			return lines;
		}

		std::string_view trimmed(std::string_view line) {
			const size_t first = line.find_first_not_of(" \t");
			if (first == std::string_view::npos) {
				return {};
			}
			return line.substr(first, line.find_last_not_of(" \t\r") - first + 1);
		}

		/*
		 * Whether a block comment's line, the text after its "* ", is never broken (C6): a code example, indented 4
		 * past the *, a list item, a table row or a line with a URL.
		 */
		bool never_broken(std::string_view words) {
			if (words.starts_with("    ") || words.starts_with("- ") || words.starts_with("* ") || words.starts_with("+ ")
				|| words.starts_with("|") || words.find("://") != std::string_view::npos) {
				return true;
			}
			size_t digits = 0;
			while (digits < words.size() && words[digits] >= '0' && words[digits] <= '9') {
				++digits;
			}
			return digits > 0 && digits + 1 < words.size() && words[digits] == '.' && words[digits + 1] == ' ';
		}

		/*
		 * The block comments' lines in text that are wider than width broken at the last space that fits (C5), each
		 * part after the first starting as the line did: the same * and indent, or a block tag's indented 4 past its
		 * @ (C7). Lines C6 keeps whole, and lines with no space to break at, run over.
		 */
		std::string wrap_comments(const std::string& text, size_t width, std::string_view newline) {
			if (width == SIZE_MAX) {
				return text;
			}
			std::string out;
			out.reserve(text.size());
			bool in_comment = false;
			for (std::string_view line : lines_of(text)) {
				const std::string_view words_of_line = trimmed(line);
				if (!in_comment && (words_of_line == "/*" || words_of_line == "/**")) {
					in_comment = true;
				}
				else if (in_comment && words_of_line == "*/") {
					in_comment = false;
				}
				else if (in_comment && words_of_line.starts_with("* ") && layout::width_of(line) > width) {
					const size_t star = line.find('*');
					std::string_view words = line.substr(star + 2);
					if (!never_broken(words)) {
						// The prefix later parts start with: a tag's continuation is 4 past its @
						const size_t words_indent = words.find_first_not_of(' ');
						std::string continuation(line.substr(0, star + 1));
						continuation += words.starts_with("@") ? std::string(5, ' ') : std::string(words_indent + 1, ' ');
						std::string rest(line);
						bool first = true;
						while (layout::width_of(rest) > width) {
							const std::string_view prefix = first ? line.substr(0, star + 2 + words_indent) : std::string_view(continuation);
							// The last space at or before the width, past the prefix
							size_t cut = std::string::npos;
							size_t columns = 0;
							for (size_t i = 0; i < rest.size(); ++i) {
								if ((static_cast<unsigned char>(rest[i]) & 0xC0) != 0x80) {
									++columns;
								}
								if (columns > width + 1) {
									break;
								}
								if (rest[i] == ' ' && i > prefix.size()) {
									cut = i;
								}
							}
							if (cut == std::string::npos) {
								break;
							}
							out.append(rest, 0, cut);
							out.append(newline);
							rest = continuation + rest.substr(rest.find_first_not_of(' ', cut));
							first = false;
						}
						out.append(rest);
						out.append(newline);
						continue;
					}
				}
				out.append(line);
				out.append(newline);
			}
			return out;
		}

		bool is_switch_line(std::string_view line, std::string_view state) {
			const std::string_view words = trimmed(line);
			if (!words.starts_with("//")) {
				return false;
			}
			std::string_view rest = trimmed(words.substr(2));
			return rest.starts_with("hemera-format:") && trimmed(rest.substr(14)) == state;
		}

		// The lines between each // hemera-format: off line and the next on line, or the end, by number.
		std::vector<std::pair<size_t, size_t>> unformatted_regions(const std::vector<std::string_view>& lines) {
			std::vector<std::pair<size_t, size_t>> regions;
			for (size_t i = 0; i < lines.size(); ++i) {
				if (!is_switch_line(lines[i], "off")) {
					continue;
				}
				size_t end = i + 1;
				while (end < lines.size() && !is_switch_line(lines[end], "on")) {
					++end;
				}
				regions.emplace_back(i + 1, end);
				i = end;
			}
			return regions;
		}

		/*
		 * text with the lines between each // hemera-format: off and the next // hemera-format: on, or the end of
		 * the file, as they are in source: the same code, kept as written. The k-th region in text is the k-th in
		 * source, as formatting keeps every comment in order.
		 */
		std::string keep_unformatted(const std::string& text, std::string_view source, std::string_view newline) {
			const std::vector<std::string_view> source_lines = lines_of(source);
			const std::vector<std::pair<size_t, size_t>> source_regions = unformatted_regions(source_lines);
			if (source_regions.empty()) {
				return text;
			}
			const std::vector<std::string_view> lines = lines_of(text);
			const std::vector<std::pair<size_t, size_t>> regions = unformatted_regions(lines);
			if (regions.size() != source_regions.size()) {
				return text;
			}
			std::string out;
			size_t next = 0;
			for (size_t k = 0; k < regions.size(); ++k) {
				for (; next < regions[k].first; ++next) {
					out.append(lines[next]).append(newline);
				}
				for (size_t i = source_regions[k].first; i < source_regions[k].second; ++i) {
					out.append(source_lines[i]).append(newline);
				}
				next = regions[k].second;
			}
			for (; next < lines.size(); ++next) {
				out.append(lines[next]).append(newline);
			}
			return out;
		}
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
		result.text = keep_unformatted(wrap_comments(d.render(printer.file(file), width, newline), width, newline), source, newline);
		for (size_t i = 0; i < comments.size(); ++i) {
			if (!printer.comments_printed[i]) {
				result.lost_comments.push_back(comments[i].offset);
			}
		}
		return result;
	}

	// The width code text is laid out within, as the formatter does (L2)
	static constexpr size_t CODE_WIDTH = 120;

	std::string source_of(const Node* node, const QuoteTable* quotes) {
		if (node == nullptr) {
			return "";
		}
		layout::Document d;
		Printer printer(d);
		printer.quote_table = quotes;
		if (NodeType::FILE == node->node_type) {
			return d.render(printer.file(node), CODE_WIDTH);
		}
		Doc contents = printer.named_contents(node);
		return d.render(contents != EMPTY ? contents : printer.statement(node), CODE_WIDTH);
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
		return d.render(out.doc(), CODE_WIDTH);
	}

}
