#include "lexer/identifiers.h"

#include <algorithm>
#include <iterator>

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
		return !keyword(text).has_value();
	}
}
