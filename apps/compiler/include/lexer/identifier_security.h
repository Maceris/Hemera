#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

/*
 * UTS #39's checks of names (docs/formatting.md, Identifiers), which the front end warns with: names that look alike,
 * names that mix scripts, and names with characters that aren't for everyday text. Each takes a name the lexer read,
 * so UTF-8 in NFKC, and an ASCII name never draws any of them on its own.
 */
namespace hemera::lexer {

	/*
	 * name's skeleton (UTS #39 §4): each character replaced by the one it's most easily mistaken for, so two names that
	 * look alike, like "сount" with a Cyrillic с and "count", have the same skeleton. Only for comparing: it's often
	 * not a name itself.
	 */
	std::string identifier_skeleton(std::string_view name);

	/*
	 * The scripts name mixes, by name, like { "Latin", "Cyrillic" }, if it mixes them more than UTS #39's Highly
	 * Restrictive level allows; empty if it doesn't. That level allows one script, or Latin with Han, Hiragana and
	 * Katakana, with Han and Bopomofo, or with Han and Hangul. Digits, _ and combining marks that go with any script
	 * count as every one's.
	 */
	std::vector<std::string_view> mixed_scripts(std::string_view name);

	// The first code point in name that UTS #39 doesn't allow in identifiers (Identifier_Status), or 0 if there's none
	uint32_t uncommon_code_point(std::string_view name);

	// The name of code_point's script, or of its first one when it's used by several, or "Common" for one of any script
	std::string_view script_name(uint32_t code_point);
}
