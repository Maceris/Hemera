#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

#include "lexer/token.h"

/*
 * What a name is (docs/formatting.md): UAX #31's default identifiers, a code point with XID_Start, so a letter of any
 * script but not a digit or _, then any with XID_Continue, which adds digits, _ and combining marks. Default ignorable
 * code points, which can't be seen, are in neither. The lexer, and everything else that checks a name, like
 * compiler.name, go by these.
 */
namespace hemera::lexer {

	// Whether code_point can start a name
	bool is_identifier_start(uint32_t code_point);

	// Whether code_point can be in a name after its first
	bool is_identifier_continue(uint32_t code_point);

	/*
	 * The length in bytes of the character at text[at] if it can be a name's first (first) or a later one (!first),
	 * or 0 if it can't, isn't UTF-8, or at is text's end or past it. code_point, when given, gets the code point there,
	 * when it's UTF-8 at all.
	 */
	size_t identifier_character(std::string_view text, size_t at, bool first, uint32_t* code_point = nullptr);

	// The keyword text spells, or none for one that isn't a keyword
	std::optional<TokenType> keyword(std::string_view text);

	/*
	 * text, a name's characters, in Unicode's Normalization Form KC (UAX #15): with compatibility characters, like ﬁ
	 * or a full-width Ａ, written as what they stand for (fi, A), and combining marks composed onto what they mark where
	 * there's one character for both. A name must already be in it, so there's one spelling, in bytes, of every name.
	 * Only code points a name can have are decomposed; text that isn't UTF-8 is given back as it is.
	 */
	std::string identifier_nfkc(std::string_view text);

	// Whether text is a whole name: as the lexer reads one, in NFKC, and not a keyword
	bool is_identifier(std::string_view text);
}
