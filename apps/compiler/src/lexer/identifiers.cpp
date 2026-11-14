#include "lexer/identifiers.h"

#include <algorithm>
#include <iterator>
#include <utility>
#include <vector>

#include "util/utf8.h"
#include "identifier_tables.h"

namespace hemera::lexer {

	static bool in(const CodePointRange* first, const CodePointRange* last, uint32_t code_point) {
		const CodePointRange* found = std::upper_bound(first, last, code_point,
			[](uint32_t point, const CodePointRange& range) { return point < range.first; });
		return found != first && code_point <= (found - 1)->last;
	}

	bool is_identifier_start(uint32_t code_point) {
		if (code_point < 0x80) {
			return (code_point >= 'a' && code_point <= 'z') || (code_point >= 'A' && code_point <= 'Z');
		}
		return in(std::begin(IDENTIFIER_START), std::end(IDENTIFIER_START), code_point);
	}

	bool is_identifier_continue(uint32_t code_point) {
		if (code_point < 0x80) {
			return (code_point >= 'a' && code_point <= 'z') || (code_point >= 'A' && code_point <= 'Z')
				|| (code_point >= '0' && code_point <= '9') || code_point == '_';
		}
		return in(std::begin(IDENTIFIER_CONTINUE), std::end(IDENTIFIER_CONTINUE), code_point);
	}

	size_t identifier_character(std::string_view text, size_t at, bool first, uint32_t* code_point) {
		if (at >= text.size()) {
			return 0;
		}
		uint32_t point = 0;
		const size_t length = utf8::decode(text, at, point);
		if (length == 0) {
			return 0;
		}
		if (code_point != nullptr) {
			*code_point = point;
		}
		return (first ? is_identifier_start(point) : is_identifier_continue(point)) ? length : 0;
	}

	std::optional<TokenType> keyword(std::string_view identifier) {
		if (identifier.compare("auto_cast") == 0) {
			return TokenType::KEYWORD_AUTO_CAST;
		}
		if (identifier.compare("bit_cast") == 0) {
			return TokenType::KEYWORD_BIT_CAST;
		}
		if (identifier.compare("break") == 0) {
			return TokenType::KEYWORD_BREAK;
		}
		if (identifier.compare("case") == 0) {
			return TokenType::KEYWORD_CASE;
		}
		if (identifier.compare("cast") == 0) {
			return TokenType::KEYWORD_CAST;
		}
		if (identifier.compare("continue") == 0) {
			return TokenType::KEYWORD_CONTINUE;
		}
		if (identifier.compare("defer") == 0) {
			return TokenType::KEYWORD_DEFER;
		}
		if (identifier.compare("distinct") == 0) {
			return TokenType::KEYWORD_DISTINCT;
		}
		if (identifier.compare("else") == 0) {
			return TokenType::KEYWORD_ELSE;
		}
		if (identifier.compare("enum") == 0) {
			return TokenType::KEYWORD_ENUM;
		}
		if (identifier.compare("false") == 0) {
			return TokenType::KEYWORD_FALSE;
		}
		if (identifier.compare("fn") == 0) {
			return TokenType::KEYWORD_FN;
		}
		if (identifier.compare("for") == 0) {
			return TokenType::KEYWORD_FOR;
		}
		if (identifier.compare("if") == 0) {
			return TokenType::KEYWORD_IF;
		}
		if (identifier.compare("compute") == 0) {
			return TokenType::KEYWORD_COMPUTE;
		}
		if (identifier.compare("give") == 0) {
			return TokenType::KEYWORD_GIVE;
		}
		if (identifier.compare("is_error") == 0) {
			return TokenType::KEYWORD_IS_ERROR;
		}
		if (identifier.compare("is_none") == 0) {
			return TokenType::KEYWORD_IS_NONE;
		}
		if (identifier.compare("is_ok") == 0) {
			return TokenType::KEYWORD_IS_OK;
		}
		if (identifier.compare("is_some") == 0) {
			return TokenType::KEYWORD_IS_SOME;
		}
		if (identifier.compare("loop") == 0) {
			return TokenType::KEYWORD_LOOP;
		}
		if (identifier.compare("match") == 0) {
			return TokenType::KEYWORD_MATCH;
		}
		if (identifier.compare("mut") == 0) {
			return TokenType::KEYWORD_MUT;
		}
		if (identifier.compare("null") == 0) {
			return TokenType::KEYWORD_NULL;
		}
		if (identifier.compare("or_break") == 0) {
			return TokenType::KEYWORD_OR_BREAK;
		}
		if (identifier.compare("or_continue") == 0) {
			return TokenType::KEYWORD_OR_CONTINUE;
		}
		if (identifier.compare("or_else") == 0) {
			return TokenType::KEYWORD_OR_ELSE;
		}
		if (identifier.compare("or_return") == 0) {
			return TokenType::KEYWORD_OR_RETURN;
		}
		if (identifier.compare("push_context") == 0) {
			return TokenType::KEYWORD_PUSH_CONTEXT;
		}
		if (identifier.compare("return") == 0) {
			return TokenType::KEYWORD_RETURN;
		}
		if (identifier.compare("struct") == 0) {
			return TokenType::KEYWORD_STRUCT;
		}
		if (identifier.compare("switch") == 0) {
			return TokenType::KEYWORD_SWITCH;
		}
		if (identifier.compare("true") == 0) {
			return TokenType::KEYWORD_TRUE;
		}
		if (identifier.compare("union") == 0) {
			return TokenType::KEYWORD_UNION;
		}
		if (identifier.compare("using") == 0) {
			return TokenType::KEYWORD_USING;
		}
		if (identifier.compare("void") == 0) {
			return TokenType::KEYWORD_VOID;
		}
		if (identifier.compare("while") == 0) {
			return TokenType::KEYWORD_WHILE;
		}
		if (identifier.compare("with") == 0) {
			return TokenType::KEYWORD_WITH;
		}
		return {};
	}

	// Hangul syllables, which decompose and compose by arithmetic rather than by the tables (Unicode §3.12)
	constexpr uint32_t HANGUL_S = 0xac00, HANGUL_L = 0x1100, HANGUL_V = 0x1161, HANGUL_T = 0x11a7;
	constexpr uint32_t HANGUL_L_COUNT = 19, HANGUL_V_COUNT = 21, HANGUL_T_COUNT = 28;
	constexpr uint32_t HANGUL_N_COUNT = HANGUL_V_COUNT * HANGUL_T_COUNT, HANGUL_S_COUNT = HANGUL_L_COUNT * HANGUL_N_COUNT;

	static uint8_t combining_class(uint32_t code_point) {
		const CombiningClassRange* found = std::upper_bound(std::begin(COMBINING_CLASSES), std::end(COMBINING_CLASSES),
			code_point, [](uint32_t point, const CombiningClassRange& range) { return point < range.first; });
		if (found == std::begin(COMBINING_CLASSES) || code_point > (found - 1)->last) {
			return 0;
		}
		return (found - 1)->combining_class;
	}

	static void decompose(uint32_t code_point, std::vector<uint32_t>& out) {
		if (code_point >= HANGUL_S && code_point < HANGUL_S + HANGUL_S_COUNT) {
			const uint32_t index = code_point - HANGUL_S;
			out.push_back(HANGUL_L + index / HANGUL_N_COUNT);
			out.push_back(HANGUL_V + index % HANGUL_N_COUNT / HANGUL_T_COUNT);
			if (index % HANGUL_T_COUNT != 0) {
				out.push_back(HANGUL_T + index % HANGUL_T_COUNT);
			}
			return;
		}
		const Decomposition* found = std::lower_bound(std::begin(DECOMPOSITIONS), std::end(DECOMPOSITIONS), code_point,
			[](const Decomposition& entry, uint32_t point) { return entry.code_point < point; });
		if (found == std::end(DECOMPOSITIONS) || found->code_point != code_point) {
			out.push_back(code_point);
			return;
		}
		out.insert(out.end(), DECOMPOSED + found->start, DECOMPOSED + found->start + found->length);
	}

	// What first and second compose into canonically, or 0 if they don't
	static uint32_t compose(uint32_t first, uint32_t second) {
		if (first >= HANGUL_L && first < HANGUL_L + HANGUL_L_COUNT && second >= HANGUL_V && second < HANGUL_V + HANGUL_V_COUNT) {
			return HANGUL_S + ((first - HANGUL_L) * HANGUL_V_COUNT + second - HANGUL_V) * HANGUL_T_COUNT;
		}
		if (first >= HANGUL_S && first < HANGUL_S + HANGUL_S_COUNT && (first - HANGUL_S) % HANGUL_T_COUNT == 0
			&& second > HANGUL_T && second < HANGUL_T + HANGUL_T_COUNT) {
			return first + second - HANGUL_T;
		}
		const Composition* found = std::lower_bound(std::begin(COMPOSITIONS), std::end(COMPOSITIONS), std::make_pair(first, second),
			[](const Composition& entry, const std::pair<uint32_t, uint32_t>& pair) {
				return entry.first < pair.first || (entry.first == pair.first && entry.second < pair.second);
			});
		if (found == std::end(COMPOSITIONS) || found->first != first || found->second != second) {
			return 0;
		}
		return found->composed;
	}

	std::vector<uint32_t> identifier_nfkd(const std::vector<uint32_t>& code_points) {
		std::vector<uint32_t> points;
		for (const uint32_t code_point : code_points) {
			decompose(code_point, points);
		}
		// Each run of combining marks in order of their classes, keeping the order of those with the same class
		for (size_t i = 1; i < points.size(); ++i) {
			const uint8_t mark = combining_class(points[i]);
			for (size_t j = i; mark != 0 && j > 0 && combining_class(points[j - 1]) > mark; --j) {
				std::swap(points[j - 1], points[j]);
			}
		}
		return points;
	}

	std::string identifier_nfkc(std::string_view text) {
		std::vector<uint32_t> code_points;
		for (size_t at = 0; at < text.size();) {
			uint32_t code_point = 0;
			const size_t length = utf8::decode(text, at, code_point);
			if (length == 0) {
				return std::string(text);
			}
			code_points.push_back(code_point);
			at += length;
		}
		// Decomposed, compatibility decompositions too, and its marks in order
		const std::vector<uint32_t> points = identifier_nfkd(code_points);
		/*
		 * Composed: each code point onto the last starter, unless something between them has the same class or a
		 * starter's (blocked)
		 */
		std::vector<uint32_t> composed;
		size_t starter = 0;
		// The class of the last code point kept; 0 means it's the starter itself, and 256 that there's no starter yet
		int last_class = 256;
		for (const uint32_t point : points) {
			const int mark = combining_class(point);
			if (!composed.empty() && (last_class < mark || last_class == 0)) {
				const uint32_t together = compose(composed[starter], point);
				if (together != 0) {
					composed[starter] = together;
					continue;
				}
			}
			if (mark == 0) {
				starter = composed.size();
			}
			last_class = composed.empty() && mark != 0 ? 256 : mark;
			composed.push_back(point);
		}
		std::string result;
		for (const uint32_t point : composed) {
			utf8::encode(point, result);
		}
		return result;
	}

	bool is_identifier(std::string_view text) {
		size_t at = identifier_character(text, 0, true);
		if (at == 0) {
			return false;
		}
		while (at < text.size()) {
			const size_t length = identifier_character(text, at, false);
			if (length == 0) {
				return false;
			}
			at += length;
		}
		const bool ascii = std::all_of(text.begin(), text.end(), [](char c) { return static_cast<unsigned char>(c) < 0x80; });
		return !keyword(text).has_value() && (ascii || identifier_nfkc(text) == text);
	}
}
