#include <algorithm>
#include <cstdlib>
#include <format>
#include <functional>
#include <limits>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "error/reporting.h"
#include "front_end/bounds.h"

/*
 * docs/types.md, Bounds Checking. At each point in a body, what's known about integers is a set of
 * facts a - b <= c between terms: integer locals, the counts of local arrays and views, the counts
 * of paths like p.items, and zero. An index i into something with count n is in bounds when the
 * facts give 0 <= i and i <= n - 1; facts are combined like shortest paths in a graph.
 *
 * Facts come from definitions and assignments, the conditions of ifs and while loops (and what
 * follows an if whose other branch doesn't), for loops, runtime.assert, and types (unsigned, narrow,
 * enums). Assigning a local forgets what's known about it; a call or a store through a pointer
 * forgets what's known about paths through pointers, and about locals whose address was taken,
 * since either may have changed them. Where paths meet, what both imply is kept.
 *
 * A loop's head keeps what holds every time around: starting from everything known before it, it
 * goes around quietly, keeping what coming back around still gives (loosened a few times, like
 * i <= n - 1 to i <= n, then dropped if it keeps loosening), until that settles; then once more,
 * reporting.
 *
 * Integers wrap, so i + 1 is only known to be one more than i, and a comparison of i + 1 only says
 * something about i, when i is bounded by a count or a constant already.
 */

namespace hemera {

	namespace {

		bool is_text(InternedString value, std::string_view text) {
			return value != nullptr && std::string_view(*value) == text;
		}

		std::string text_of(InternedString value) {
			return value != nullptr ? std::string(std::string_view(*value)) : std::string("_");
		}

		bool is_assign(const ast::Node* node) {
			return TokenType::OPERATOR_ASSIGN == node->value.type;
		}

		bool is_compound_assignment(TokenType op) {
			const TokenType operators[] = {
				TokenType::OPERATOR_ASSIGN_ADD, TokenType::OPERATOR_ASSIGN_SUB, TokenType::OPERATOR_ASSIGN_MUL,
				TokenType::OPERATOR_ASSIGN_DIV, TokenType::OPERATOR_ASSIGN_MOD, TokenType::OPERATOR_ASSIGN_REMAINDER,
				TokenType::OPERATOR_ASSIGN_BITWISE_AND, TokenType::OPERATOR_ASSIGN_BITWISE_OR,
				TokenType::OPERATOR_ASSIGN_BITWISE_XOR, TokenType::OPERATOR_ASSIGN_LEFT_SHIFT,
				TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC, TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL,
				TokenType::OPERATOR_ASSIGN_AND, TokenType::OPERATOR_ASSIGN_OR,
			};
			return std::find(std::begin(operators), std::end(operators), op) != std::end(operators);
		}

		bool is_assignment(const ast::Node* node) {
			return ast::NodeType::BINARY_OPERATOR == node->node_type && node->children.size() == 2
				&& (is_assign(node) || is_compound_assignment(node->value.type));
		}

		bool is_wildcard(const ast::Node* node) {
			return ast::NodeType::UNDERSCORE == node->node_type;
		}

		bool is_postfix_marker(const ast::Node* node) {
			return ast::NodeType::DOT_ACCESS == node->node_type
				|| ast::NodeType::PAREN_GROUP == node->node_type
				|| ast::NodeType::ARRAY_DIMENSION == node->node_type
				|| (ast::NodeType::UNARY_OPERATOR == node->node_type && TokenType::OPERATOR_DEREFERENCE == node->value.type);
		}

		bool is_range(const ast::Node* node) {
			return ast::NodeType::BINARY_OPERATOR == node->node_type
				&& (TokenType::OPERATOR_RANGE_EXCLUSIVE == node->value.type || TokenType::OPERATOR_RANGE_INCLUSIVE == node->value.type);
		}

		TypeInfo const* base(TypeInfo const* type) {
			return type != nullptr ? get_base_type(type) : nullptr;
		}

		bool is_variant(TypeInfo const* type, TypeInfoVariant variant) {
			type = base(type);
			return type != nullptr && variant == type->variant;
		}

		bool is_unsigned(TypeInfo const* type) {
			type = base(type);
			return type != nullptr && TypeInfoVariant::INTEGER == type->variant && !static_cast<TypeInfoInteger const*>(type)->is_signed;
		}

		// An array's or string's elements: static arrays have a count that's a constant.
		bool is_indexable(TypeInfo const* type) {
			type = base(type);
			return type != nullptr && (TypeInfoVariant::ARRAY == type->variant
				|| (TypeInfoVariant::STRING == type->variant && !static_cast<TypeInfoString const*>(type)->is_raw));
		}

		std::optional<int64_t> static_count(TypeInfo const* type) {
			type = base(type);
			if (type != nullptr && TypeInfoVariant::ARRAY == type->variant
				&& ArrayType::STATIC == static_cast<TypeInfoArray const*>(type)->array_type) {
				return static_cast<int64_t>(static_cast<TypeInfoArray const*>(type)->count);
			}
			return std::nullopt;
		}

		// The largest of an enum's values, which a value of it can be at most: it's one of its members.
		std::optional<int64_t> enum_maximum(TypeInfo const* type) {
			type = base(type);
			if (type == nullptr || TypeInfoVariant::ENUM != type->variant) {
				return std::nullopt;
			}
			auto enumeration = static_cast<TypeInfoEnum const*>(type);
			uint64_t largest = 0;
			for (uint64_t value : enumeration->values) {
				largest = std::max(largest, value);
			}
			if (enumeration->values.empty() || largest > static_cast<uint64_t>(std::numeric_limits<int64_t>::max() / 4)) {
				return std::nullopt;
			}
			return static_cast<int64_t>(largest);
		}

		std::optional<int64_t> enum_value(TypeInfo const* type, InternedString member) {
			type = base(type);
			if (type == nullptr || TypeInfoVariant::ENUM != type->variant || member == nullptr) {
				return std::nullopt;
			}
			auto enumeration = static_cast<TypeInfoEnum const*>(type);
			for (size_t i = 0; i < enumeration->members.size() && i < enumeration->values.size(); ++i) {
				if (*enumeration->members[i] == *member
					&& enumeration->values[i] <= static_cast<uint64_t>(std::numeric_limits<int64_t>::max())) {
					return static_cast<int64_t>(enumeration->values[i]);
				}
			}
			return std::nullopt;
		}

		// A string literal's length in bytes, each escape one byte, as the generator writes it.
		int64_t literal_length(InternedString literal) {
			std::string text = text_of(literal);
			if (text.size() >= 2 && (text.front() == '"' || text.front() == '\'')) {
				text = text.substr(1, text.size() - 2);
			}
			int64_t length = 0;
			for (size_t i = 0; i < text.size(); ++i) {
				if (text[i] == '\\' && i + 1 < text.size()) {
					++i;
				}
				++length;
			}
			return length;
		}

		bool parse_integer(std::string_view text, int64_t& value) {
			std::string digits;
			for (char c : text) {
				if (c != '_') {
					digits.push_back(c);
				}
			}
			int radix = 10;
			size_t start = 0;
			if (digits.size() > 2 && digits[0] == '0' && (digits[1] == 'x' || digits[1] == 'X')) {
				radix = 16;
				start = 2;
			}
			else if (digits.size() > 2 && digits[0] == '0' && (digits[1] == 'b' || digits[1] == 'B')) {
				radix = 2;
				start = 2;
			}
			if (start >= digits.size()) {
				return false;
			}
			char* end = nullptr;
			const unsigned long long parsed = std::strtoull(digits.c_str() + start, &end, radix);
			if (end == nullptr || *end != '\0' || parsed > static_cast<unsigned long long>(std::numeric_limits<int64_t>::max())) {
				return false;
			}
			value = static_cast<int64_t>(parsed);
			return true;
		}

		// What's big enough to stand for no bound at all, with room to add to it.
		constexpr int64_t UNBOUNDED = std::numeric_limits<int64_t>::max() / 4;
		// Counts are at most this, since what they count is in memory
		constexpr int64_t LARGEST_COUNT = int64_t{ 1 } << 60;

		// ---------------------------------------------------------------------------------------------
		// Facts

		using Term = size_t;
		// The term that's always zero, which facts about constants are relative to
		constexpr Term ZERO = 0;

		enum class TermKind : uint8_t {
			ZERO,
			// An integer local
			LOCAL,
			// A local array's, view's or string's count
			COUNT,
			// A count through members or a pointer, like p.items.count
			PATH,
		};

		struct TermInfo {
			TermKind kind = TermKind::ZERO;
			// The local it's about, or a path's first
			const void* local = nullptr;
			bool nonnegative = false;
			// A path through a pointer, which anything that writes memory may change
			bool through_pointer = false;
			// A count of elements, which is at most LARGEST_COUNT; an integer field isn't
			bool is_count = false;
			// The most its type holds, for an unsigned type narrower than 64 bits
			std::optional<int64_t> maximum;
		};

		// What's known: a - b <= c for each (a, b). Unreachable code knows everything.
		struct Facts {
			bool reachable = true;
			std::map<std::pair<Term, Term>, int64_t> bounds;
		};

		Facts unreachable() {
			Facts facts;
			facts.reachable = false;
			return facts;
		}

		void add(Facts& facts, Term a, Term b, int64_t c) {
			if (a == b || c >= UNBOUNDED || c <= -UNBOUNDED) {
				return;
			}
			auto iter = facts.bounds.find({ a, b });
			if (iter == facts.bounds.end() || c < iter->second) {
				facts.bounds[{ a, b }] = c;
			}
		}

		struct Value {
			// term + offset, or with no term, offset alone; or not known at all
			bool known = false;
			Term term = ZERO;
			int64_t offset = 0;
			// Up to this much more than term + offset, like i + k with k from 0 to 2
			int64_t spread = 0;
			// What's known even when the value isn't, like x & 15 being at most 15
			std::optional<int64_t> at_most;
			bool nonnegative = false;
		};

		Value constant(int64_t c) {
			Value value;
			value.known = true;
			value.offset = c;
			return value;
		}

		Value of_term(Term term) {
			Value value;
			value.known = true;
			value.term = term;
			return value;
		}

		// A loop, or a switch, which break leaves: what's known where each break and continue is.
		struct LoopFrame {
			std::vector<Facts> breaks;
			std::vector<Facts> continues;
			bool is_switch = false;
		};

		struct Analysis {
			const CheckedBody& checked;
			TypeInfoFunction const* function;
			const std::string& file_path;
			std::vector<TermInfo> terms{ TermInfo{} };
			std::map<std::pair<TermKind, std::string>, Term> term_keys;
			// Locals whose address is taken somewhere, so anything that writes memory may change them
			std::unordered_set<const void*> address_taken;
			std::vector<LoopFrame> loops;
			size_t errors = 0;
			std::unordered_set<const ast::Node*> reported;
			// While working out what holds each time around a loop: report nothing
			size_t quiet = 0;
		};

		void report(Analysis& analysis, const ast::Node* where, const std::string& details) {
			if (analysis.quiet > 0 || !analysis.reported.insert(where).second) {
				return;
			}
			report_error(ErrorCode::E4031, analysis.file_path, where->value.line_number, where->value.column_number, details);
			++analysis.errors;
		}

		const CheckedNode* found_at(const Analysis& analysis, const ast::Node* node) {
			auto iter = analysis.checked.nodes.find(node);
			return iter == analysis.checked.nodes.end() ? nullptr : &iter->second;
		}

		const CheckedNode* head_of(const Analysis& analysis, const ast::Node* node) {
			auto iter = analysis.checked.heads.find(node);
			return iter == analysis.checked.heads.end() ? nullptr : &iter->second;
		}

		Term term_for(Analysis& analysis, TermKind kind, const void* local, const std::string& path, bool nonnegative) {
			const std::string key = std::format("{}:{}", static_cast<const void*>(local), path);
			auto iter = analysis.term_keys.find({ kind, key });
			if (iter != analysis.term_keys.end()) {
				return iter->second;
			}
			const Term term = analysis.terms.size();
			const bool is_count = TermKind::COUNT == kind || (TermKind::PATH == kind && !path.ends_with('#'));
			analysis.terms.push_back(TermInfo{ kind, local, nonnegative || is_count,
				TermKind::PATH == kind && path.find('^') != std::string::npos, is_count, std::nullopt });
			analysis.term_keys[{ kind, key }] = term;
			return term;
		}

		// A term for an integer of type: at most what the type holds, when that's unsigned and narrower than 64 bits.
		Term bounded_by_type(Analysis& analysis, Term term, TypeInfo const* type) {
			TypeInfo const* integer = base(type);
			if (is_unsigned(type) && integer->size < 8) {
				analysis.terms[term].maximum = (int64_t{ 1 } << (8 * integer->size)) - 1;
			}
			return term;
		}

		Term local_term(Analysis& analysis, const void* local, TypeInfo const* type) {
			return bounded_by_type(analysis, term_for(analysis, TermKind::LOCAL, local, "", is_unsigned(type)), type);
		}

		// The shortest-path closure of the facts: dist[a][b] is the least c known for b - a <= c.
		struct Closure {
			std::vector<Term> terms;
			std::unordered_map<Term, size_t> index;
			std::vector<std::vector<int64_t>> distance;
			bool contradiction = false;
		};

		Closure close(const Analysis& analysis, const Facts& facts, const std::vector<Term>& wanted) {
			Closure closure;
			auto include = [&](Term term) {
				if (closure.index.emplace(term, closure.terms.size()).second) {
					closure.terms.push_back(term);
				}
			};
			include(ZERO);
			for (Term term : wanted) {
				include(term);
			}
			for (const auto& [pair, c] : facts.bounds) {
				include(pair.first);
				include(pair.second);
			}
			const size_t n = closure.terms.size();
			closure.distance.assign(n, std::vector<int64_t>(n, UNBOUNDED));
			for (size_t i = 0; i < n; ++i) {
				closure.distance[i][i] = 0;
				// Unsigned locals and counts are at least zero: 0 - t <= 0
				if (analysis.terms[closure.terms[i]].nonnegative) {
					closure.distance[i][closure.index[ZERO]] = 0;
				}
				// And a narrow one at most its type's largest: t - 0 <= maximum
				if (const auto& maximum = analysis.terms[closure.terms[i]].maximum) {
					int64_t& edge = closure.distance[closure.index[ZERO]][i];
					edge = std::min(edge, *maximum);
				}
			}
			for (const auto& [pair, c] : facts.bounds) {
				// a - b <= c: an edge from b to a
				int64_t& edge = closure.distance[closure.index[pair.second]][closure.index[pair.first]];
				edge = std::min(edge, c);
			}
			for (size_t k = 0; k < n; ++k) {
				for (size_t i = 0; i < n; ++i) {
					if (closure.distance[i][k] >= UNBOUNDED) {
						continue;
					}
					for (size_t j = 0; j < n; ++j) {
						if (closure.distance[k][j] >= UNBOUNDED) {
							continue;
						}
						const int64_t through = closure.distance[i][k] + closure.distance[k][j];
						if (through < closure.distance[i][j]) {
							closure.distance[i][j] = std::max(through, -UNBOUNDED);
						}
					}
				}
			}
			for (size_t i = 0; i < n; ++i) {
				if (closure.distance[i][i] < 0) {
					closure.contradiction = true;
				}
			}
			return closure;
		}

		/*
		 * What's known on both paths to a point: each bound either path implies, at the looser of the
		 * two. Comparing what they imply, not only what's written, keeps i + 1 <= n on one path and
		 * start <= n on the other as start <= n.
		 */
		Facts join(const Analysis& analysis, const Facts& x, const Facts& y) {
			if (!x.reachable) {
				return y;
			}
			if (!y.reachable) {
				return x;
			}
			std::vector<Term> terms;
			for (const Facts* each : { &x, &y }) {
				for (const auto& [pair, c] : each->bounds) {
					terms.push_back(pair.first);
					terms.push_back(pair.second);
				}
			}
			const Closure left = close(analysis, x, terms);
			const Closure right = close(analysis, y, terms);
			if (left.contradiction) {
				return y;
			}
			if (right.contradiction) {
				return x;
			}
			Facts result;
			for (size_t i = 0; i < left.terms.size(); ++i) {
				for (size_t j = 0; j < left.terms.size(); ++j) {
					if (i == j) {
						continue;
					}
					const Term from = left.terms[i];
					const Term to = left.terms[j];
					auto from_right = right.index.find(from);
					auto to_right = right.index.find(to);
					if (from_right == right.index.end() || to_right == right.index.end()) {
						continue;
					}
					const int64_t a = left.distance[i][j];
					const int64_t b = right.distance[from_right->second][to_right->second];
					// to - from <= the looser
					if (a < UNBOUNDED && b < UNBOUNDED) {
						add(result, to, from, std::max(a, b));
					}
				}
			}
			return result;
		}

		// Whether the facts give a - b <= c.
		bool proves(const Analysis& analysis, const Facts& facts, Term a, Term b, int64_t c) {
			if (!facts.reachable) {
				return true;
			}
			if (a == b) {
				return 0 <= c;
			}
			const Closure closure = close(analysis, facts, { a, b });
			if (closure.contradiction) {
				return true;
			}
			return closure.distance[closure.index.at(b)][closure.index.at(a)] <= c;
		}

		// Whether a value is at most what a count or a constant is, so adding to it can't wrap.
		bool is_bounded(const Analysis& analysis, const Facts& facts, Term term) {
			if (ZERO == term || analysis.terms[term].is_count) {
				return true;
			}
			const Closure closure = close(analysis, facts, { term });
			for (size_t j = 0; j < closure.terms.size(); ++j) {
				const TermInfo& other = analysis.terms[closure.terms[j]];
				// term - other <= c, with other a count or zero and c not too large
				const int64_t c = closure.distance[j][closure.index.at(term)];
				if ((TermKind::ZERO == other.kind || other.is_count) && c < LARGEST_COUNT) {
					return true;
				}
			}
			return false;
		}

		// a == b + c
		void add_equal(Facts& facts, Term a, Term b, int64_t c) {
			add(facts, a, b, c);
			add(facts, b, a, -c);
		}

		void add_value_equal(const Analysis& analysis, Facts& facts, Term term, const Value& value) {
			if (value.known) {
				if (value.term == term) {
					return;
				}
				// term == value.term + offset (up to spread more), which only holds if computing it didn't wrap
				if (value.offset + value.spread > 0 && !is_bounded(analysis, facts, value.term)) {
					return;
				}
				add(facts, term, value.term, value.offset + value.spread);
				add(facts, value.term, term, -value.offset);
				return;
			}
			if (value.at_most.has_value()) {
				add(facts, term, ZERO, *value.at_most);
			}
			if (value.nonnegative) {
				add(facts, ZERO, term, 0);
			}
		}

		void forget(Facts& facts, const std::function<bool(Term)>& which) {
			for (auto iter = facts.bounds.begin(); iter != facts.bounds.end();) {
				if (which(iter->first.first) || which(iter->first.second)) {
					iter = facts.bounds.erase(iter);
				}
				else {
					++iter;
				}
			}
		}

		// A local assigned: what's known about it and its count, and paths through it.
		void forget_local(Analysis& analysis, Facts& facts, const void* local) {
			forget(facts, [&](Term term) { return term != ZERO && analysis.terms[term].local == local; });
		}

		// Something wrote memory, or called a function that may have.
		void forget_memory(Analysis& analysis, Facts& facts) {
			forget(facts, [&](Term term) {
				const TermInfo& info = analysis.terms[term];
				return info.through_pointer || (info.local != nullptr && analysis.address_taken.contains(info.local));
			});
		}

		// x = x + by: what was known about x, moved by by.
		void shift(Analysis& analysis, Facts& facts, Term term, int64_t by) {
			// Counting an unsigned value down past zero wraps, and counting up past a bound may
			const bool wraps_down = by < 0 && analysis.terms[term].nonnegative && !proves(analysis, facts, ZERO, term, by);
			if (wraps_down || (by > 0 && !is_bounded(analysis, facts, term))) {
				forget(facts, [&](Term each) { return each == term; });
				return;
			}
			std::map<std::pair<Term, Term>, int64_t> moved;
			for (const auto& [pair, c] : facts.bounds) {
				const int64_t adjusted = pair.first == term ? c + by : pair.second == term ? c - by : c;
				moved[pair] = adjusted;
			}
			facts.bounds = std::move(moved);
		}

		// ---------------------------------------------------------------------------------------------
		// Constants

		ast::Node* definition_value(ast::Node* definition) {
			for (size_t i = 1; i < definition->children.size(); ++i) {
				ast::Node* child = definition->children[i];
				if (ast::NodeType::COLON == child->node_type || (ast::NodeType::IDENTIFIER == child->node_type && is_assign(child))) {
					return i + 1 < definition->children.size() ? definition->children[i + 1] : nullptr;
				}
			}
			return nullptr;
		}

		// An integer constant's value, from literals, arithmetic and named constants.
		std::optional<int64_t> constant_value(const CheckedBody* checked, const ast::Node* node, int depth) {
			if (node == nullptr || depth > 32) {
				return std::nullopt;
			}
			const ast::NodeType type = node->node_type;
			if (ast::NodeType::LITERAL == type) {
				int64_t value = 0;
				if (TokenType::LITERAL_INTEGER == node->value.type && parse_integer(text_of(node->value.value), value)) {
					return value;
				}
				return std::nullopt;
			}
			if (ast::NodeType::PAREN_GROUP == type && node->children.size() == 1) {
				return constant_value(checked, node->children[0], depth + 1);
			}
			if (ast::NodeType::UNARY_OPERATOR == type && TokenType::OPERATOR_MINUS == node->value.type && node->children.size() == 1) {
				auto operand = constant_value(checked, node->children[0], depth + 1);
				return operand.has_value() ? std::optional<int64_t>(-*operand) : std::nullopt;
			}
			if (ast::NodeType::CAST == type && node->children.size() == 2) {
				return constant_value(checked, node->children[1], depth + 1);
			}
			if (ast::NodeType::BINARY_OPERATOR == type && node->children.size() == 2) {
				auto left = constant_value(checked, node->children[0], depth + 1);
				auto right = constant_value(checked, node->children[1], depth + 1);
				if (!left.has_value() || !right.has_value()) {
					return std::nullopt;
				}
				const int64_t a = *left;
				const int64_t b = *right;
				const int64_t limit = int64_t{ 1 } << 61;
				if (std::abs(a) >= limit || std::abs(b) >= limit) {
					return std::nullopt;
				}
				const TokenType op = node->value.type;
				if (TokenType::OPERATOR_PLUS == op) {
					return a + b;
				}
				if (TokenType::OPERATOR_MINUS == op) {
					return a - b;
				}
				if (TokenType::OPERATOR_MULTIPLY == op && (a == 0 || std::abs(b) < limit / std::max<int64_t>(std::abs(a), 1))) {
					return a * b;
				}
				if (TokenType::OPERATOR_DIVIDE == op && b != 0) {
					return a / b;
				}
				if (TokenType::OPERATOR_LEFT_SHIFT == op && b >= 0 && b < 61 && a >= 0 && a < (limit >> b)) {
					return a << b;
				}
				if ((TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL == op || TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC == op) && b >= 0 && b < 63 && a >= 0) {
					return a >> b;
				}
				if (TokenType::SYM_AMPERSAND == op && a >= 0 && b >= 0) {
					return a & b;
				}
				if (TokenType::OPERATOR_BITWISE_OR == op && a >= 0 && b >= 0) {
					return a | b;
				}
				return std::nullopt;
			}
			if (ast::NodeType::IDENTIFIER == type && node->children.empty() && checked != nullptr) {
				auto iter = checked->nodes.find(node);
				if (iter == checked->nodes.end() || iter->second.declaration == nullptr) {
					return std::nullopt;
				}
				Declaration* declaration = iter->second.declaration;
				if (DeclarationKind::VALUE != declaration->kind || declaration->externally_initialized || declaration->node == nullptr) {
					return std::nullopt;
				}
				return constant_value(declaration->checked.get(), definition_value(declaration->node), depth + 1);
			}
			return std::nullopt;
		}

		// ---------------------------------------------------------------------------------------------
		// Expressions

		/*
		 * What a chain is so far: its type, and the count of what it is if that's known: a static
		 * array's, or a term for a local's or a path's. path is how the chain's local is reached.
		 */
		struct Chain {
			TypeInfo* type = nullptr;
			ValueKind kind = ValueKind::NOTHING;
			const void* local = nullptr;
			std::string path;
			// Whether it went through a call or an element, after which there's no path
			bool pathless = false;
			// What its count is, when that's known another way: a slice's, or view_of's
			std::optional<Value> count;
			Value value;
			bool never_returns = false;
		};

		Value evaluate(Analysis& analysis, Facts& facts, ast::Node* node);
		void walk_statement(Analysis& analysis, Facts& facts, ast::Node* statement);
		void walk_block(Analysis& analysis, Facts& facts, ast::Node* block);
		std::pair<Facts, Facts> condition(Analysis& analysis, const Facts& facts, ast::Node* node);

		// The count of what a chain is, as a value: a constant, a term, or unknown.
		Value count_of(Analysis& analysis, const Chain& chain) {
			if (auto fixed = static_count(chain.type)) {
				return constant(*fixed);
			}
			if (chain.count.has_value()) {
				return *chain.count;
			}
			if (chain.local == nullptr || chain.pathless) {
				return Value{};
			}
			if (chain.path.empty()) {
				return of_term(term_for(analysis, TermKind::COUNT, chain.local, "", true));
			}
			return of_term(term_for(analysis, TermKind::PATH, chain.local, chain.path, true));
		}

		// Whether value <= limit - 1 and 0 <= value, for value and limit as known.
		bool below(Analysis& analysis, const Facts& facts, const Value& value, const Value& limit, int64_t slack) {
			if (!facts.reachable) {
				return true;
			}
			// value - limit <= slack, for the most value can be and the least limit can be
			if (value.known && limit.known) {
				return proves(analysis, facts, value.term, limit.term, limit.offset - value.offset - value.spread + slack);
			}
			if (!value.known && value.at_most.has_value() && limit.known) {
				// limit >= at_most - slack: 0 - limit.term <= limit.offset - at_most + slack
				return proves(analysis, facts, ZERO, limit.term, limit.offset - *value.at_most + slack);
			}
			return false;
		}

		bool at_least_zero(Analysis& analysis, const Facts& facts, const Value& value) {
			if (!facts.reachable) {
				return true;
			}
			if (value.known) {
				// 0 - term <= offset
				return proves(analysis, facts, ZERO, value.term, value.offset);
			}
			return value.nonnegative;
		}

		void check_index(Analysis& analysis, const Facts& facts, const Chain& collection, ast::Node* index, const Value& value) {
			const Value count = count_of(analysis, collection);
			if (!at_least_zero(analysis, facts, value) || !below(analysis, facts, value, count, -1)) {
				report(analysis, index, "this index isn't proven to be in bounds: check it against the count first, "
					"or loop over the elements (docs/types.md, Bounds Checking)");
			}
		}

		// Checks a slice's bounds, and gives its count when that's a known value.
		std::optional<Value> check_slice(Analysis& analysis, Facts& facts, const Chain& collection, ast::Node* index) {
			const Value count = count_of(analysis, collection);
			Value low = constant(0);
			Value high = count;
			bool inclusive = false;
			if (is_range(index) && index->children.size() == 2) {
				inclusive = TokenType::OPERATOR_RANGE_INCLUSIVE == index->value.type;
				if (ast::NodeType::RANGE_ARRAY != index->children[0]->node_type) {
					low = evaluate(analysis, facts, index->children[0]);
				}
				if (ast::NodeType::RANGE_ARRAY != index->children[1]->node_type) {
					high = evaluate(analysis, facts, index->children[1]);
					if (inclusive && high.known) {
						high.offset += 1;
					}
					else if (inclusive) {
						high = Value{};
					}
				}
			}
			// 0 <= low <= high <= count
			const bool fits = at_least_zero(analysis, facts, low) && below(analysis, facts, low, high, 0)
				&& below(analysis, facts, high, count, 0);
			if (!fits) {
				report(analysis, index, "this slice isn't proven to be in bounds: its start must be at least 0, at most its end, "
					"and its end at most the count (docs/types.md, Bounds Checking)");
			}
			if (high.known && low.known && ZERO == low.term && 0 == high.spread) {
				Value sliced = high;
				sliced.offset -= low.offset;
				return sliced;
			}
			return std::nullopt;
		}

		Chain evaluate_name(Analysis& analysis, ast::Node* node, const CheckedNode* found) {
			Chain chain;
			if (found == nullptr || ValueKind::POISONED == found->kind) {
				chain.pathless = true;
				return chain;
			}
			chain.kind = found->kind;
			chain.type = found->type;
			if (found->local != nullptr) {
				chain.local = found->local;
				if (is_variant(found->type, TypeInfoVariant::INTEGER) || (found->type == nullptr && ValueKind::UNTYPED_INTEGER == found->kind)) {
					chain.value = of_term(local_term(analysis, found->local, found->type));
				}
				return chain;
			}
			chain.pathless = true;
			if (auto value = constant_value(&analysis.checked, node, 0)) {
				chain.value = constant(*value);
			}
			// A constant string's count is its literal's length
			Declaration* declaration = found->declaration;
			if (declaration != nullptr && DeclarationKind::VALUE == declaration->kind && declaration->node != nullptr
				&& is_variant(found->type, TypeInfoVariant::STRING)) {
				ast::Node* value = definition_value(declaration->node);
				if (value != nullptr && ast::NodeType::LITERAL == value->node_type && TokenType::LITERAL_STRING == value->value.type) {
					chain.count = constant(literal_length(value->value.value));
				}
			}
			return chain;
		}

		std::vector<Value> evaluate_arguments(Analysis& analysis, Facts& facts, const std::vector<ast::Node*>& arguments) {
			std::vector<Value> values;
			for (ast::Node* argument : arguments) {
				if (ast::NodeType::BINARY_OPERATOR == argument->node_type && is_assign(argument) && argument->children.size() == 2) {
					values.push_back(evaluate(analysis, facts, argument->children[1]));
				}
				else {
					values.push_back(evaluate(analysis, facts, argument));
				}
			}
			return values;
		}

		bool is_runtime_assert(const CheckedNode* found) {
			Declaration* called = found != nullptr ? found->called_declaration : nullptr;
			return called != nullptr && is_text(called->name, "assert") && called->package_path != nullptr
				&& std::string_view(*called->package_path).ends_with("runtime");
		}

		Chain evaluate_steps(Analysis& analysis, Facts& facts, ast::Node* node, size_t start, Chain current) {
			for (size_t i = start; i < node->children.size(); ++i) {
				ast::Node* child = node->children[i];
				std::vector<ast::Node*> arguments;
				while (i + 1 < node->children.size() && !is_postfix_marker(node->children[i + 1])) {
					arguments.push_back(node->children[++i]);
				}
				const ast::NodeType type = child->node_type;
				if (ast::NodeType::PAREN_GROUP == type && arguments.empty() && !child->children.empty()) {
					arguments.assign(child->children.begin(), child->children.end());
				}
				ast::Node* where = ast::NodeType::DOT_ACCESS == type && !arguments.empty() ? arguments[0] : child;
				const CheckedNode* found = found_at(analysis, where);
				if (found == nullptr || ValueKind::POISONED == found->kind) {
					Chain unknown;
					unknown.pathless = true;
					return unknown;
				}
				Chain next;
				next.kind = found->kind;
				next.type = found->type;
				if (ast::NodeType::DOT_ACCESS == type) {
					if (ValueKind::PACKAGE == current.kind) {
						next = evaluate_name(analysis, arguments[0], found);
					}
					else if (ValueKind::TYPE == current.kind) {
						// An enum's member
						next.pathless = true;
						if (auto value = enum_value(found->type, arguments[0]->value.value)) {
							next.value = constant(*value);
						}
					}
					else {
						const std::string member = text_of(arguments[0]->value.value);
						next.local = current.local;
						next.pathless = current.pathless;
						// Through a pointer, what it points to
						next.path = current.path + (is_variant(current.type, TypeInfoVariant::POINTER) ? "^." : ".") + member;
						if (member == "count" && is_indexable(current.type)) {
							next.value = count_of(analysis, current);
						}
						// An integer field reached from a local, like text.count: a path of its own
						else if (is_variant(found->type, TypeInfoVariant::INTEGER) && next.local != nullptr && !next.pathless) {
							next.value = of_term(bounded_by_type(analysis, term_for(analysis, TermKind::PATH, next.local,
								next.path + "#", is_unsigned(found->type)), found->type));
						}
					}
				}
				else if (ast::NodeType::PAREN_GROUP == type) {
					const bool asserts = is_runtime_assert(found);
					std::vector<Value> values;
					if (asserts && !arguments.empty()) {
						auto [holds, fails] = condition(analysis, facts, arguments[0]);
						evaluate_arguments(analysis, holds, { arguments.begin() + 1, arguments.end() });
						facts = holds;
					}
					else {
						values = evaluate_arguments(analysis, facts, arguments);
					}
					// What the call may have written; runtime.assert writes nothing when it returns
					if (ValueKind::BUILTIN_FUNCTION != current.kind && !asserts) {
						forget_memory(analysis, facts);
					}
					next.pathless = true;
					// view_of(pointer, count) and string_of(pointer, count) have that count
					Declaration* called = found->called_declaration;
					if (called != nullptr && called->generic != nullptr) {
						called = called->generic;
					}
					if (called != nullptr && (is_text(called->name, "view_of") || is_text(called->name, "string_of"))
						&& values.size() == 2) {
						next.count = values[1];
					}
					next.never_returns = (found->called != nullptr && found->called->never_returns)
						|| (ValueKind::BUILTIN_FUNCTION == current.kind && current.never_returns);
				}
				else if (ast::NodeType::ARRAY_DIMENSION == type) {
					if (ValueKind::GENERIC_FUNCTION == current.kind || ValueKind::TYPE == current.kind || arguments.empty()) {
						next = current;
						next.kind = found->kind;
						next.type = found->type;
					}
					else {
						Chain collection = current;
						// Through a pointer to an array, the array
						if (is_variant(collection.type, TypeInfoVariant::POINTER)) {
							collection.type = static_cast<TypeInfoPointer const*>(base(collection.type))->base_type;
							collection.path += "^";
						}
						ast::Node* index = arguments[0];
						if (is_indexable(collection.type)) {
							if (is_range(index) || ast::NodeType::RANGE_ARRAY == index->node_type) {
								next.count = check_slice(analysis, facts, collection, index);
							}
							else {
								check_index(analysis, facts, collection, index, evaluate(analysis, facts, index));
							}
						}
						else {
							evaluate(analysis, facts, index);
						}
						next.pathless = true;
					}
				}
				else {
					// ^: what a pointer points to
					next.local = current.local;
					next.pathless = current.pathless;
					next.path = current.path + "^";
				}
				current = next;
			}
			return current;
		}

		Chain evaluate_chain(Analysis& analysis, Facts& facts, ast::Node* node) {
			const CheckedNode* whole = found_at(analysis, node);
			if (whole != nullptr && ValueKind::TYPE == whole->kind) {
				Chain type;
				type.kind = ValueKind::TYPE;
				type.pathless = true;
				return type;
			}
			const CheckedNode* head = head_of(analysis, node);
			if (node->children.empty() || head == nullptr) {
				Chain chain = evaluate_name(analysis, node, head != nullptr ? head : whole);
				if (ValueKind::BUILTIN_FUNCTION == chain.kind && is_text(node->value.value, "todo")) {
					chain.never_returns = true;
				}
				return chain;
			}
			ast::Node* name = head->next > 0 ? node->children[head->next - 1] : node;
			Chain current = evaluate_name(analysis, name, head);
			if (ValueKind::BUILTIN_FUNCTION == current.kind && is_text(name->value.value, "todo")) {
				current.never_returns = true;
			}
			return evaluate_steps(analysis, facts, node, head->next, current);
		}

		// Whether an expression statement ends what follows it, like a call to a #never_returns function.
		bool ends(Analysis& analysis, Facts& facts, ast::Node* node) {
			if (ast::NodeType::IDENTIFIER == node->node_type) {
				return evaluate_chain(analysis, facts, node).never_returns;
			}
			evaluate(analysis, facts, node);
			return false;
		}

		// The most a term can be, from the facts: term - 0 <= c.
		std::optional<int64_t> upper_bound(const Analysis& analysis, const Facts& facts, Term term) {
			const Closure closure = close(analysis, facts, { term });
			const int64_t c = closure.distance[closure.index.at(ZERO)][closure.index.at(term)];
			return c < UNBOUNDED ? std::optional<int64_t>(c) : std::nullopt;
		}

		// The least a term can be, from the facts: 0 - term <= c.
		std::optional<int64_t> lower_bound(const Analysis& analysis, const Facts& facts, Term term) {
			const Closure closure = close(analysis, facts, { term });
			const int64_t c = closure.distance[closure.index.at(term)][closure.index.at(ZERO)];
			return c < UNBOUNDED ? std::optional<int64_t>(-c) : std::nullopt;
		}

		Value combine(const Analysis& analysis, const Facts& facts, TokenType op, Value left, Value right) {
			// Addition either way around: the term on the left
			if (TokenType::OPERATOR_PLUS == op && !(left.known && ZERO != left.term) && right.known && ZERO != right.term) {
				std::swap(left, right);
			}
			// A bounded term times a positive constant: a bound
			if (TokenType::OPERATOR_MULTIPLY == op && left.known && ZERO != left.term && right.known && ZERO == right.term
				&& right.offset > 0 && right.offset < (int64_t{ 1 } << 20) && proves(analysis, facts, ZERO, left.term, left.offset)) {
				if (auto most = upper_bound(analysis, facts, left.term); most.has_value() && *most + left.offset + left.spread < (int64_t{ 1 } << 40)) {
					Value product;
					product.at_most = (*most + left.offset + left.spread) * right.offset;
					product.nonnegative = true;
					return product;
				}
			}
			// A term plus something with a small known range: the term, spread over that range
			if (TokenType::OPERATOR_PLUS == op && left.known && ZERO != left.term) {
				std::optional<std::pair<int64_t, int64_t>> range;
				if (right.known && ZERO != right.term) {
					auto least = lower_bound(analysis, facts, right.term);
					auto most = upper_bound(analysis, facts, right.term);
					if (least.has_value() && most.has_value() && *most - *least < LARGEST_COUNT) {
						range = std::make_pair(*least + right.offset, *most + right.offset + right.spread);
					}
				}
				else if (!right.known && right.at_most.has_value() && right.nonnegative) {
					range = std::make_pair(int64_t{ 0 }, *right.at_most);
				}
				if (range.has_value()) {
					Value sum = left;
					sum.offset += range->first;
					sum.spread += range->second - range->first;
					return sum;
				}
			}
			// A term divided or shifted: what's known of its range, as a bound
			if (left.known && ZERO != left.term && right.known && ZERO == right.term
				&& (TokenType::OPERATOR_DIVIDE == op || TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL == op)
				&& proves(analysis, facts, ZERO, left.term, left.offset)) {
				if (auto most = upper_bound(analysis, facts, left.term)) {
					Value bounded;
					bounded.at_most = *most + left.offset;
					bounded.nonnegative = true;
					left = bounded;
				}
			}
			// Whether a value is known not to be negative: an unsigned term, or a bound that says so
			auto nonnegative = [&](const Value& value) {
				return value.nonnegative || (value.known && value.offset >= 0 && analysis.terms[value.term].nonnegative);
			};
			if (TokenType::OPERATOR_PLUS == op) {
				if (left.known && right.known && (ZERO == left.term || ZERO == right.term)) {
					Value sum = constant(left.offset + right.offset);
					sum.term = ZERO == left.term ? right.term : left.term;
					return sum;
				}
			}
			if (TokenType::OPERATOR_MINUS == op && left.known && right.known && ZERO == right.term) {
				Value difference = left;
				difference.offset -= right.offset;
				return difference;
			}
			if (left.known && right.known && ZERO == left.term && ZERO == right.term) {
				const int64_t a = left.offset;
				const int64_t b = right.offset;
				if (TokenType::OPERATOR_MULTIPLY == op && std::abs(a) < (int64_t{ 1 } << 30) && std::abs(b) < (int64_t{ 1 } << 30)) {
					return constant(a * b);
				}
				if (TokenType::OPERATOR_DIVIDE == op && b != 0) {
					return constant(a / b);
				}
			}
			Value result;
			// x & mask is at most mask, and x % m less than m, for a constant that isn't negative
			if (TokenType::SYM_AMPERSAND == op && right.known && ZERO == right.term && right.offset >= 0) {
				result.at_most = right.offset;
				result.nonnegative = true;
			}
			if (TokenType::SYM_AMPERSAND == op && left.known && ZERO == left.term && left.offset >= 0) {
				result.at_most = left.offset;
				result.nonnegative = true;
			}
			if ((TokenType::OPERATOR_MODULUS == op || TokenType::OPERATOR_REMAINDER == op) && right.known && ZERO == right.term
				&& right.offset > 0 && nonnegative(left)) {
				result.at_most = right.offset - 1;
				result.nonnegative = true;
			}
			// x % m for a variable m that's bounded: less than its most
			if ((TokenType::OPERATOR_MODULUS == op || TokenType::OPERATOR_REMAINDER == op) && right.known && ZERO != right.term
				&& nonnegative(left) && proves(analysis, facts, ZERO, right.term, right.offset - 1)) {
				if (auto most = upper_bound(analysis, facts, right.term)) {
					result.at_most = *most + right.offset + right.spread - 1;
					result.nonnegative = true;
				}
			}
			// A bounded value divided by a positive constant, or shifted right
			if ((TokenType::OPERATOR_DIVIDE == op || TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL == op) && !left.known
				&& left.at_most.has_value() && left.nonnegative && right.known && ZERO == right.term && right.offset > 0
				&& (TokenType::OPERATOR_DIVIDE == op || right.offset < 63)) {
				result.at_most = TokenType::OPERATOR_DIVIDE == op ? *left.at_most / right.offset : *left.at_most >> right.offset;
				result.nonnegative = true;
			}
			return result;
		}

		bool is_comparison(TokenType op) {
			return TokenType::OPERATOR_EQUAL == op || TokenType::OPERATOR_NOT_EQUAL == op
				|| TokenType::SYM_LT == op || TokenType::SYM_GT == op
				|| TokenType::OPERATOR_LESS_THAN_OR_EQUAL == op || TokenType::OPERATOR_GREATER_THAN_OR_EQUAL == op;
		}

		Value evaluate(Analysis& analysis, Facts& facts, ast::Node* node) {
			const ast::NodeType type = node->node_type;
			if (ast::NodeType::LITERAL == type) {
				int64_t value = 0;
				if (TokenType::LITERAL_INTEGER == node->value.type && parse_integer(text_of(node->value.value), value)) {
					return constant(value);
				}
				return Value{};
			}
			if (ast::NodeType::IDENTIFIER == type) {
				Chain chain = evaluate_chain(analysis, facts, node);
				Value value = chain.value;
				if (!value.known && is_unsigned(chain.type)) {
					value.nonnegative = true;
				}
				if (!value.known) {
					if (auto largest = enum_maximum(chain.type)) {
						value.at_most = *largest;
						value.nonnegative = true;
					}
				}
				return value;
			}
			if (ast::NodeType::PAREN_GROUP == type && node->children.size() == 1) {
				return evaluate(analysis, facts, node->children[0]);
			}
			if (ast::NodeType::UNARY_OPERATOR == type) {
				if (TokenType::OPERATOR_MINUS == node->value.type && !node->children.empty()) {
					Value operand = evaluate(analysis, facts, node->children[0]);
					return operand.known && ZERO == operand.term ? constant(-operand.offset) : Value{};
				}
				for (ast::Node* child : node->children) {
					evaluate(analysis, facts, child);
				}
				return Value{};
			}
			if (ast::NodeType::BINARY_OPERATOR == type && node->children.size() == 2) {
				const TokenType op = node->value.type;
				if (TokenType::OPERATOR_AND == op || TokenType::OPERATOR_OR == op || is_comparison(op)) {
					condition(analysis, facts, node);
					return Value{};
				}
				if (TokenType::OPERATOR_PIPE == op) {
					evaluate(analysis, facts, node->children[0]);
					Chain right = evaluate_chain(analysis, facts, node->children[1]);
					evaluate_steps(analysis, facts, node, 2, right);
					forget_memory(analysis, facts);
					return Value{};
				}
				if (TokenType::KEYWORD_OR_ELSE == op || TokenType::KEYWORD_OR_RETURN == op) {
					evaluate(analysis, facts, node->children[0]);
					Facts otherwise = facts;
					evaluate(analysis, otherwise, node->children[1]);
					facts = join(analysis, facts, otherwise);
					return Value{};
				}
				Value left = evaluate(analysis, facts, node->children[0]);
				Value right = evaluate(analysis, facts, node->children[1]);
				return combine(analysis, facts, op, left, right);
			}
			if (ast::NodeType::CAST == type) {
				const bool automatic = TokenType::KEYWORD_AUTO_CAST == node->value.type;
				const size_t value_index = automatic ? 0 : 1;
				if (node->children.size() <= value_index) {
					return Value{};
				}
				Value value = evaluate(analysis, facts, node->children[value_index]);
				const CheckedNode* head = head_of(analysis, node);
				// An integer cast keeps the value: a negative one fails being at least 0 anyway
				const bool integer = head != nullptr && is_variant(head->type, TypeInfoVariant::INTEGER);
				Chain chain;
				chain.type = head != nullptr ? head->type : nullptr;
				chain.pathless = true;
				chain.value = integer ? value : Value{};
				return evaluate_steps(analysis, facts, node, automatic ? 1 : 2, chain).value;
			}
			if (ast::NodeType::IF == type) {
				walk_statement(analysis, facts, node);
				return Value{};
			}
			if (ast::NodeType::MATCH == type) {
				walk_statement(analysis, facts, node);
				return Value{};
			}
			if (ast::NodeType::DIRECTIVE == type) {
				return Value{};
			}
			if (ast::NodeType::ENUM_SHORTHAND == type) {
				const CheckedNode* found = found_at(analysis, node);
				if (found != nullptr) {
					if (auto value = enum_value(found->type, node->value.value)) {
						return constant(*value);
					}
				}
				return Value{};
			}
			if (ast::NodeType::STRUCT_LITERAL == type || ast::NodeType::ARRAY_LITERAL == type) {
				for (ast::Node* child : node->children) {
					if (ast::NodeType::LIST != child->node_type) {
						continue;
					}
					for (ast::Node* element : child->children) {
						const bool named = ast::NodeType::BINARY_OPERATOR == element->node_type && is_assign(element)
							&& element->children.size() == 2;
						evaluate(analysis, facts, named ? element->children[1] : element);
					}
				}
			}
			return Value{};
		}

		// ---------------------------------------------------------------------------------------------
		// Conditions

		// x <= y + k, for every value x and y can be: x at its most, y at its least.
		void at_most(Facts& facts, const Value& x, const Value& y, int64_t k) {
			add(facts, x.term, y.term, y.offset + k - x.offset - x.spread);
		}

		// From x op y: what holds of their terms. A value spread over a range gives what holds for all of it.
		void compare(Analysis& analysis, Facts& facts, TokenType op, const Value& left, const Value& right) {
			// x + c wraps for x near the top of its range, so it only says something about a bounded x
			if ((left.known && left.offset + left.spread > 0 && !is_bounded(analysis, facts, left.term))
				|| (right.known && right.offset + right.spread > 0 && !is_bounded(analysis, facts, right.term))) {
				return;
			}
			if (!left.known || !right.known) {
				// Still something: x < limit, when only x is known
				if (left.known && !right.known && right.at_most.has_value()
					&& (TokenType::SYM_LT == op || TokenType::OPERATOR_LESS_THAN_OR_EQUAL == op)) {
					at_most(facts, left, constant(*right.at_most), TokenType::SYM_LT == op ? -1 : 0);
				}
				return;
			}
			// left < right: left at its least is below right at its most, so left.term + l <= right.term + r + spread - 1
			auto least = [](Value value) {
				value.spread = 0;
				return value;
			};
			auto most = [](Value value) {
				value.offset += value.spread;
				value.spread = 0;
				return value;
			};
			if (TokenType::SYM_LT == op) {
				at_most(facts, least(left), most(right), -1);
			}
			else if (TokenType::OPERATOR_LESS_THAN_OR_EQUAL == op) {
				at_most(facts, least(left), most(right), 0);
			}
			else if (TokenType::SYM_GT == op) {
				at_most(facts, least(right), most(left), -1);
			}
			else if (TokenType::OPERATOR_GREATER_THAN_OR_EQUAL == op) {
				at_most(facts, least(right), most(left), 0);
			}
			else if (TokenType::OPERATOR_EQUAL == op) {
				at_most(facts, least(left), most(right), 0);
				at_most(facts, least(right), most(left), 0);
			}
			else if (TokenType::OPERATOR_NOT_EQUAL == op && 0 == left.spread && 0 == right.spread) {
				// Not equal, and known to be at least (or at most) the other: past it
				const int64_t l = left.offset;
				const int64_t r = right.offset;
				const Term a = left.term;
				const Term b = right.term;
				if (proves(analysis, facts, b, a, l - r)) {
					add(facts, b, a, l - r - 1);
				}
				else if (proves(analysis, facts, a, b, r - l)) {
					add(facts, a, b, r - l - 1);
				}
			}
		}

		TokenType negated(TokenType op) {
			if (TokenType::SYM_LT == op) {
				return TokenType::OPERATOR_GREATER_THAN_OR_EQUAL;
			}
			if (TokenType::OPERATOR_LESS_THAN_OR_EQUAL == op) {
				return TokenType::SYM_GT;
			}
			if (TokenType::SYM_GT == op) {
				return TokenType::OPERATOR_LESS_THAN_OR_EQUAL;
			}
			if (TokenType::OPERATOR_GREATER_THAN_OR_EQUAL == op) {
				return TokenType::SYM_LT;
			}
			if (TokenType::OPERATOR_EQUAL == op) {
				return TokenType::OPERATOR_NOT_EQUAL;
			}
			return TokenType::OPERATOR_EQUAL;
		}

		// What's known where a condition is true, and where it's false.
		std::pair<Facts, Facts> condition(Analysis& analysis, const Facts& facts, ast::Node* node) {
			if (ast::NodeType::PAREN_GROUP == node->node_type && node->children.size() == 1) {
				return condition(analysis, facts, node->children[0]);
			}
			if (ast::NodeType::UNARY_OPERATOR == node->node_type && TokenType::OPERATOR_NOT == node->value.type && !node->children.empty()) {
				auto [when_true, when_false] = condition(analysis, facts, node->children[0]);
				return { when_false, when_true };
			}
			if (ast::NodeType::BINARY_OPERATOR == node->node_type && node->children.size() == 2) {
				const TokenType op = node->value.type;
				if (TokenType::OPERATOR_AND == op) {
					auto [left_true, left_false] = condition(analysis, facts, node->children[0]);
					auto [right_true, right_false] = condition(analysis, left_true, node->children[1]);
					return { right_true, join(analysis, left_false, right_false) };
				}
				if (TokenType::OPERATOR_OR == op) {
					auto [left_true, left_false] = condition(analysis, facts, node->children[0]);
					auto [right_true, right_false] = condition(analysis, left_false, node->children[1]);
					return { join(analysis, left_true, right_true), right_false };
				}
				if (is_comparison(op)) {
					Facts after = facts;
					const Value left = evaluate(analysis, after, node->children[0]);
					const Value right = evaluate(analysis, after, node->children[1]);
					Facts when_true = after;
					Facts when_false = after;
					compare(analysis, when_true, op, left, right);
					compare(analysis, when_false, negated(op), left, right);
					return { when_true, when_false };
				}
			}
			Facts after = facts;
			evaluate(analysis, after, node);
			return { after, after };
		}

		// ---------------------------------------------------------------------------------------------
		// Statements

		// The locals a statement assigns anywhere in it, and whether it writes memory or calls.
		// What a loop's body may change.
		struct Changes {
			std::unordered_set<const void*> locals;
			bool writes_memory = false;
		};

		// The locals a statement assigns anywhere in it, and whether it writes memory or calls.
		void assigned_in(Analysis& analysis, ast::Node* node, Changes& changed) {
			if (is_assignment(node)) {
				std::vector<ast::Node*> targets;
				ast::Node* left = node->children[0];
				if (ast::NodeType::LIST == left->node_type) {
					targets.assign(left->children.begin(), left->children.end());
				}
				else {
					targets.push_back(left);
				}
				for (ast::Node* target : targets) {
					const CheckedNode* head = head_of(analysis, target);
					const CheckedNode* found = head != nullptr ? head : found_at(analysis, target);
					// An element or field through a view, a pointer or a string is memory elsewhere, not the local
					const bool elsewhere = found != nullptr && !target->children.empty()
						&& (is_variant(found->type, TypeInfoVariant::POINTER) || is_variant(found->type, TypeInfoVariant::STRING)
							|| (is_variant(found->type, TypeInfoVariant::ARRAY) && !static_count(found->type).has_value()));
					if (found != nullptr && found->local != nullptr && !elsewhere) {
						changed.locals.insert(found->local);
					}
					if (!target->children.empty()) {
						changed.writes_memory = true;
					}
				}
			}
			// A call, which the checker recorded with what it calls
			if (ast::NodeType::PAREN_GROUP == node->node_type) {
				const CheckedNode* found = found_at(analysis, node);
				if (found != nullptr && found->called != nullptr) {
					changed.writes_memory = true;
				}
			}
			for (ast::Node* child : node->children) {
				assigned_in(analysis, child, changed);
			}
		}

		bool changes(const Analysis& analysis, const Changes& changed, Term term) {
			const TermInfo& info = analysis.terms[term];
			if (ZERO == term) {
				return false;
			}
			return changed.locals.contains(info.local)
				|| (changed.writes_memory && (info.through_pointer || analysis.address_taken.contains(info.local)));
		}

		/*
		 * What still holds at a loop's head after going around once more: each fact the head had that
		 * coming back around (back) gives at least as tightly. Facts are only ever dropped, so going
		 * around again and again ends.
		 */
		Facts widen(const Analysis& analysis, const Facts& head, const Facts& back, bool loosen) {
			if (!back.reachable) {
				return head;
			}
			std::vector<Term> terms;
			for (const auto& [pair, c] : head.bounds) {
				terms.push_back(pair.first);
				terms.push_back(pair.second);
			}
			const Closure closure = close(analysis, back, terms);
			if (closure.contradiction) {
				return head;
			}
			Facts result;
			result.reachable = head.reachable;
			for (const auto& [pair, c] : head.bounds) {
				// a - b <= c holds coming back around at most as loosely as again
				const int64_t again = closure.distance[closure.index.at(pair.second)][closure.index.at(pair.first)];
				if (again <= c) {
					result.bounds[pair] = c;
				}
				// The first few times, a bound that comes back looser is loosened to that, like i <= n - 1
				// becoming i <= n; after that, one that keeps loosening is dropped
				else if (loosen && again < UNBOUNDED) {
					result.bounds[pair] = again;
				}
			}
			return result;
		}

		/*
		 * Walks a loop: around(head, breaks) goes around once from what's known at its head, and gives
		 * what's known coming back to it. First, quietly, what holds every time around; then once more,
		 * reporting, from that. Gives that head, with breaks set from the last time around.
		 */
		Facts walk_around(Analysis& analysis, const Facts& before,
			const std::function<Facts(const Facts& head, std::vector<Facts>& breaks)>& around, std::vector<Facts>& breaks) {

			// Everything the facts before imply, written out, so what still holds can be kept: in terms of
			// everything the loop mentions, which going around once quietly makes terms for
			Facts head = before;
			if (head.reachable) {
				std::vector<Facts> ignored;
				++analysis.quiet;
				around(before, ignored);
				--analysis.quiet;
				std::vector<Term> every;
				for (Term term = 1; term < analysis.terms.size(); ++term) {
					every.push_back(term);
				}
				const Closure closure = close(analysis, before, every);
				if (!closure.contradiction) {
					for (size_t i = 0; i < closure.terms.size(); ++i) {
						for (size_t j = 0; j < closure.terms.size(); ++j) {
							if (i != j && closure.distance[i][j] < UNBOUNDED) {
								add(head, closure.terms[j], closure.terms[i], closure.distance[i][j]);
							}
						}
					}
				}
			}
			for (size_t times = 0; times < 64 && head.reachable; ++times) {
				std::vector<Facts> ignored;
				++analysis.quiet;
				const Facts back = around(head, ignored);
				--analysis.quiet;
				Facts next = widen(analysis, head, back, times < 4);
				if (next.bounds == head.bounds) {
					break;
				}
				head = std::move(next);
			}
			around(head, breaks);
			return head;
		}

		void walk_definition(Analysis& analysis, Facts& facts, ast::Node* definition) {
			std::vector<ast::Node*> names;
			ast::Node* names_node = definition->children[0];
			if (ast::NodeType::LIST == names_node->node_type) {
				names.assign(names_node->children.begin(), names_node->children.end());
			}
			else {
				names.push_back(names_node);
			}
			ast::Node* value_node = definition_value(definition);
			if (value_node != nullptr && ast::NodeType::FUNCTION == value_node->node_type) {
				return;
			}
			Value value;
			Chain chain;
			if (value_node != nullptr && ast::NodeType::UNINITIALIZED != value_node->node_type) {
				if (ast::NodeType::IDENTIFIER == value_node->node_type) {
					chain = evaluate_chain(analysis, facts, value_node);
					value = chain.value;
				}
				else {
					value = evaluate(analysis, facts, value_node);
				}
			}
			else if (names.size() == 1) {
				// A variable without a value starts at zero
				value = constant(0);
			}
			if (names.size() != 1 || is_wildcard(names[0])) {
				return;
			}
			const CheckedNode* found = found_at(analysis, names[0]);
			if (found == nullptr) {
				return;
			}
			forget_local(analysis, facts, names[0]);
			if (is_variant(found->type, TypeInfoVariant::INTEGER) || ValueKind::UNTYPED_INTEGER == found->kind) {
				const Term term = local_term(analysis, names[0], found->type);
				add_value_equal(analysis, facts, term, value);
			}
			else if (is_indexable(found->type) && !static_count(found->type).has_value() && value_node != nullptr
				&& ast::NodeType::IDENTIFIER == value_node->node_type && is_indexable(chain.type)) {
				// A copy of an array or view: the same count
				const Term count = term_for(analysis, TermKind::COUNT, names[0], "", true);
				const Value from = count_of(analysis, chain);
				if (from.known && 0 == from.spread) {
					add_equal(facts, count, from.term, from.offset);
				}
			}
		}

		void walk_assignment(Analysis& analysis, Facts& facts, ast::Node* node) {
			ast::Node* left = node->children[0];
			ast::Node* right = node->children[1];
			if (is_assignment(right)) {
				walk_assignment(analysis, facts, right);
				right = right->children[0];
			}
			std::vector<ast::Node*> targets;
			if (ast::NodeType::LIST == left->node_type) {
				targets.assign(left->children.begin(), left->children.end());
			}
			else {
				targets.push_back(left);
			}
			const Value value = evaluate(analysis, facts, right);
			const TokenType op = node->value.type;
			for (ast::Node* target : targets) {
				if (is_wildcard(target)) {
					continue;
				}
				const CheckedNode* head = head_of(analysis, target);
				const CheckedNode* found = head != nullptr ? head : found_at(analysis, target);
				const bool plain_local = target->children.empty() && found != nullptr && found->local != nullptr;
				if (!plain_local) {
					// A field, an element or through a pointer: the target's indexes are checked
					evaluate_chain(analysis, facts, target);
					if (found != nullptr && found->local != nullptr) {
						forget(facts, [&](Term term) {
							return TermKind::PATH == analysis.terms[term].kind && analysis.terms[term].local == found->local;
						});
					}
					forget_memory(analysis, facts);
					continue;
				}
				const void* local = found->local;
				const bool integer = is_variant(found->type, TypeInfoVariant::INTEGER);
				const Term term = local_term(analysis, local, found->type);
				const bool single = targets.size() == 1;
				if (integer && single && (TokenType::OPERATOR_ASSIGN_ADD == op || TokenType::OPERATOR_ASSIGN_SUB == op)
					&& value.known && ZERO == value.term) {
					shift(analysis, facts, term, TokenType::OPERATOR_ASSIGN_ADD == op ? value.offset : -value.offset);
					continue;
				}
				if (integer && single && is_assign(node) && value.known && value.term == term && 0 == value.spread) {
					shift(analysis, facts, term, value.offset);
					continue;
				}
				forget_local(analysis, facts, local);
				if (integer && single && is_assign(node)) {
					add_value_equal(analysis, facts, term, value);
				}
			}
		}

		void walk_for(Analysis& analysis, Facts& facts, ast::Node* node) {
			std::vector<ast::Node*> names;
			ast::Node* iterable = nullptr;
			ast::Node* body = nullptr;
			bool after_in = false;
			for (ast::Node* child : node->children) {
				const ast::NodeType type = child->node_type;
				if (ast::NodeType::IN == type) {
					after_in = true;
				}
				else if (!after_in) {
					names.push_back(child);
				}
				else if (ast::NodeType::BLOCK == type) {
					body = child;
				}
				else if (ast::NodeType::DIRECTIVE != type && iterable == nullptr) {
					iterable = child;
				}
			}
			if (iterable == nullptr || body == nullptr) {
				return;
			}
			Value low = constant(0);
			Value high;
			bool inclusive = false;
			if (is_range(iterable)) {
				inclusive = TokenType::OPERATOR_RANGE_INCLUSIVE == iterable->value.type;
				low = evaluate(analysis, facts, iterable->children[0]);
				high = evaluate(analysis, facts, iterable->children[1]);
			}
			else {
				Chain collection = ast::NodeType::IDENTIFIER == iterable->node_type ? evaluate_chain(analysis, facts, iterable) : Chain{};
				if (ast::NodeType::IDENTIFIER != iterable->node_type) {
					evaluate(analysis, facts, iterable);
					collection.pathless = true;
				}
				if (is_variant(collection.type, TypeInfoVariant::POINTER)) {
					collection.type = static_cast<TypeInfoPointer const*>(base(collection.type))->base_type;
					collection.path += "^";
				}
				high = count_of(analysis, collection);
			}
			Changes changed;
			assigned_in(analysis, body, changed);
			// The index: from low, below high (or at most it), unless the body changes what they're made of
			ast::Node* index_name = is_range(iterable) ? (names.empty() ? nullptr : names[0]) : (names.size() > 1 ? names[1] : nullptr);
			const CheckedNode* index_found = index_name != nullptr && !is_wildcard(index_name) ? found_at(analysis, index_name) : nullptr;
			std::optional<Term> index;
			if (index_found != nullptr) {
				TypeInfo* index_type = is_range(iterable) ? index_found->type : BUILTIN_usize;
				index = local_term(analysis, index_name, index_type);
			}
			// The bounds are worked out once, before the loop: a term the body changes isn't one any more
			auto unchanged = [&](const Value& bound) {
				return bound.known && 0 == bound.spread && !changes(analysis, changed, bound.term);
			};
			Facts before = facts;
			if (index.has_value()) {
				forget(before, [&](Term term) { return term == *index; });
			}
			auto around = [&](const Facts& head, std::vector<Facts>& breaks) {
				Facts entry = head;
				if (index.has_value()) {
					if (unchanged(low)) {
						add(entry, low.term, *index, -low.offset);
					}
					if (unchanged(high)) {
						add(entry, *index, high.term, high.offset - (inclusive ? 0 : 1));
					}
					else if (!high.known && high.at_most.has_value()) {
						add(entry, *index, ZERO, *high.at_most - (inclusive ? 0 : 1));
					}
				}
				analysis.loops.push_back(LoopFrame{});
				walk_block(analysis, entry, body);
				LoopFrame frame = std::move(analysis.loops.back());
				analysis.loops.pop_back();
				breaks = std::move(frame.breaks);
				Facts back = entry;
				for (const Facts& each : frame.continues) {
					back = join(analysis, back, each);
				}
				// The index is the next one's next time
				if (index.has_value()) {
					forget(back, [&](Term term) { return term == *index; });
				}
				return back;
			};
			std::vector<Facts> breaks;
			Facts after = walk_around(analysis, before, around, breaks);
			for (const Facts& each : breaks) {
				after = join(analysis, after, each);
			}
			facts = after;
		}

		void walk_loop(Analysis& analysis, Facts& facts, ast::Node* node) {
			for (ast::Node* child : node->children) {
				if (ast::NodeType::WITH_CLAUSE == child->node_type) {
					for (ast::Node* list : child->children) {
						for (ast::Node* statement : list->children) {
							walk_statement(analysis, facts, statement);
						}
					}
				}
			}
			ast::Node* condition_node = nullptr;
			ast::Node* body = nullptr;
			for (ast::Node* child : node->children) {
				if (ast::NodeType::WHILE_CLAUSE == child->node_type && !child->children.empty()) {
					condition_node = child->children[0];
				}
				else if (ast::NodeType::BLOCK == child->node_type) {
					body = child;
				}
			}
			// The condition is checked before each time around
			Facts exit = unreachable();
			auto around = [&](const Facts& head, std::vector<Facts>& breaks) {
				Facts entry = head;
				exit = unreachable();
				if (condition_node != nullptr) {
					auto [when_true, when_false] = condition(analysis, head, condition_node);
					entry = when_true;
					exit = when_false;
				}
				analysis.loops.push_back(LoopFrame{});
				if (body != nullptr) {
					walk_block(analysis, entry, body);
				}
				LoopFrame frame = std::move(analysis.loops.back());
				analysis.loops.pop_back();
				breaks = std::move(frame.breaks);
				Facts back = entry;
				for (const Facts& each : frame.continues) {
					back = join(analysis, back, each);
				}
				return back;
			};
			std::vector<Facts> breaks;
			walk_around(analysis, facts, around, breaks);
			for (const Facts& each : breaks) {
				exit = join(analysis, exit, each);
			}
			facts = exit;
		}

		ast::Node* else_of(ast::Node* if_node) {
			ast::Node* otherwise = if_node->children.size() > 2 ? if_node->children[2] : nullptr;
			if (otherwise != nullptr && ast::NodeType::ELSE == otherwise->node_type && !otherwise->children.empty()) {
				otherwise = otherwise->children[0];
			}
			return otherwise;
		}

		void walk_if(Analysis& analysis, Facts& facts, ast::Node* node) {
			auto [when_true, when_false] = condition(analysis, facts, node->children[0]);
			walk_block(analysis, when_true, node->children[1]);
			ast::Node* otherwise = else_of(node);
			if (otherwise != nullptr) {
				if (ast::NodeType::IF == otherwise->node_type) {
					walk_if(analysis, when_false, otherwise);
				}
				else {
					walk_block(analysis, when_false, otherwise);
				}
			}
			facts = join(analysis, when_true, when_false);
		}

		std::vector<ast::Node*> entries_of(ast::Node* node, bool cases) {
			std::vector<ast::Node*> result;
			for (ast::Node* list : node->children) {
				if (ast::NodeType::LIST != list->node_type) {
					continue;
				}
				for (ast::Node* entry : list->children) {
					if (!entry->children.empty() && (!cases || ast::NodeType::SWITCH_CASE == entry->node_type)) {
						result.push_back(entry);
					}
				}
			}
			return result;
		}

		void walk_match(Analysis& analysis, Facts& facts, ast::Node* node, bool cases) {
			evaluate(analysis, facts, node->children[0]);
			Facts after = unreachable();
			if (cases) {
				LoopFrame frame;
				frame.is_switch = true;
				analysis.loops.push_back(frame);
			}
			for (ast::Node* entry : entries_of(node, cases)) {
				Facts arm = facts;
				for (size_t i = 0; i + 1 < entry->children.size(); ++i) {
					ast::Node* pattern = entry->children[i];
					if (ast::NodeType::IDENTIFIER != pattern->node_type && ast::NodeType::ENUM_SHORTHAND != pattern->node_type
						&& !is_wildcard(pattern)) {
						evaluate(analysis, arm, pattern);
					}
				}
				ast::Node* outcome = entry->children.back();
				if (ast::NodeType::BLOCK == outcome->node_type) {
					walk_block(analysis, arm, outcome);
				}
				else {
					walk_statement(analysis, arm, outcome);
				}
				after = join(analysis, after, arm);
			}
			if (cases) {
				LoopFrame frame = std::move(analysis.loops.back());
				analysis.loops.pop_back();
				for (const Facts& each : frame.breaks) {
					after = join(analysis, after, each);
				}
				// A continue in a switch is the loop's around it
				for (Facts& each : frame.continues) {
					for (auto outer = analysis.loops.rbegin(); outer != analysis.loops.rend(); ++outer) {
						if (!outer->is_switch) {
							outer->continues.push_back(std::move(each));
							break;
						}
					}
				}
				// A switch with no case that matches goes on
				after = join(analysis, after, facts);
			}
			facts = after;
		}

		void walk_statement(Analysis& analysis, Facts& facts, ast::Node* statement) {
			if (!facts.reachable) {
				// Nothing here runs: what it indexes doesn't matter
				return;
			}
			const ast::NodeType type = statement->node_type;
			if (ast::NodeType::DEFINITION == type) {
				walk_definition(analysis, facts, statement);
			}
			else if (is_assignment(statement)) {
				walk_assignment(analysis, facts, statement);
			}
			else if (ast::NodeType::RETURN == type) {
				for (ast::Node* child : statement->children) {
					if (ast::NodeType::LIST == child->node_type) {
						for (ast::Node* each : child->children) {
							evaluate(analysis, facts, each);
						}
					}
					else {
						evaluate(analysis, facts, child);
					}
				}
				facts = unreachable();
			}
			else if (ast::NodeType::BREAK == type) {
				size_t depth = 1;
				if (!statement->children.empty()) {
					const ast::Node* count = statement->children[0];
					depth = ast::NodeType::KEYWORD_ALL == count->node_type ? analysis.loops.size()
						: static_cast<size_t>(std::strtoull(text_of(count->value.value).c_str(), nullptr, 10));
				}
				if (depth >= 1 && depth <= analysis.loops.size()) {
					analysis.loops[analysis.loops.size() - depth].breaks.push_back(facts);
				}
				facts = unreachable();
			}
			else if (ast::NodeType::CONTINUE == type) {
				for (auto frame = analysis.loops.rbegin(); frame != analysis.loops.rend(); ++frame) {
					if (!frame->is_switch) {
						frame->continues.push_back(facts);
						break;
					}
				}
				facts = unreachable();
			}
			else if (ast::NodeType::IF == type) {
				walk_if(analysis, facts, statement);
			}
			else if (ast::NodeType::FOR_LOOP == type) {
				walk_for(analysis, facts, statement);
			}
			else if (ast::NodeType::LOOP == type) {
				walk_loop(analysis, facts, statement);
			}
			else if (ast::NodeType::DEFER == type) {
				// It runs when the block ends, when what's known now may not hold
				Facts later;
				for (ast::Node* deferred : statement->children) {
					walk_statement(analysis, later, deferred);
				}
			}
			else if (ast::NodeType::BLOCK == type) {
				walk_block(analysis, facts, statement);
			}
			else if (ast::NodeType::MATCH == type) {
				walk_match(analysis, facts, statement, false);
			}
			else if (ast::NodeType::SWITCH == type) {
				walk_match(analysis, facts, statement, true);
			}
			else if (ast::NodeType::PUSH_CONTEXT == type) {
				for (size_t i = 1; i + 1 < statement->children.size(); ++i) {
					ast::Node* part = statement->children[i];
					if (ast::NodeType::LIST == part->node_type) {
						for (ast::Node* field : part->children) {
							if (field->children.size() == 2) {
								evaluate(analysis, facts, field->children[1]);
							}
						}
					}
					else if (ast::NodeType::KEYWORD_FROM == part->node_type) {
						for (ast::Node* child : part->children) {
							evaluate(analysis, facts, child);
						}
					}
					else {
						evaluate(analysis, facts, part);
					}
				}
				ast::Node* body = statement->children.empty() ? nullptr : statement->children.back();
				if (body != nullptr && ast::NodeType::BLOCK == body->node_type) {
					walk_block(analysis, facts, body);
				}
			}
			else if (ast::NodeType::DIRECTIVE == type) {
				return;
			}
			else if (ends(analysis, facts, statement)) {
				facts = unreachable();
			}
		}

		void walk_block(Analysis& analysis, Facts& facts, ast::Node* block) {
			for (size_t i = 0; i < block->children.size(); ++i) {
				ast::Node* statement = block->children[i];
				if (ast::NodeType::DIRECTIVE == statement->node_type && is_text(statement->value.value, "#if")) {
					std::vector<ast::Node*> chain{ statement };
					while (i + 1 < block->children.size()
						&& ast::NodeType::DIRECTIVE == block->children[i + 1]->node_type
						&& (is_text(block->children[i + 1]->value.value, "#else_if")
							|| is_text(block->children[i + 1]->value.value, "#else"))) {
						chain.push_back(block->children[++i]);
						if (is_text(chain.back()->value.value, "#else")) {
							break;
						}
					}
					const CheckedNode* chosen = found_at(analysis, statement);
					if (chosen != nullptr && chosen->variant < chain.size() && !chain[chosen->variant]->children.empty()) {
						walk_block(analysis, facts, chain[chosen->variant]->children.back());
					}
					continue;
				}
				walk_statement(analysis, facts, statement);
			}
		}

		// Locals whose address is taken anywhere: &x, &x.field, &x[i].
		void find_address_taken(Analysis& analysis, ast::Node* node) {
			if (ast::NodeType::UNARY_OPERATOR == node->node_type && TokenType::SYM_AMPERSAND == node->value.type && !node->children.empty()) {
				ast::Node* operand = node->children[0];
				const CheckedNode* head = head_of(analysis, operand);
				const CheckedNode* found = head != nullptr ? head : found_at(analysis, operand);
				/*
				 * &x, or a part of x held in the local itself: a struct's field or a static array's
				 * element. Through a pointer, a view or a string, it's memory elsewhere.
				 */
				const bool elsewhere = found != nullptr && !operand->children.empty()
					&& (is_variant(found->type, TypeInfoVariant::POINTER) || is_variant(found->type, TypeInfoVariant::STRING)
						|| (is_variant(found->type, TypeInfoVariant::ARRAY) && !static_count(found->type).has_value()));
				if (found != nullptr && found->local != nullptr && !elsewhere) {
					analysis.address_taken.insert(found->local);
				}
			}
			for (ast::Node* child : node->children) {
				find_address_taken(analysis, child);
			}
		}

	}

	bool check_bounds(const CheckedBody& checked, ast::Node* body, TypeInfoFunction const* type, const std::string& file_path) {
		Analysis analysis{ checked, type, file_path, { TermInfo{} }, {}, {}, {}, 0, {}, 0 };
		find_address_taken(analysis, body);
		Facts facts;
		walk_block(analysis, facts, body);
		return analysis.errors == 0;
	}

}
