#include "lexer/identifier_security.h"

#include <algorithm>
#include <array>
#include <bitset>
#include <iterator>

#include "lexer/identifiers.h"
#include "util/utf8.h"
#include "identifier_security_tables.h"

namespace hemera::lexer {

	static std::vector<uint32_t> code_points_of(std::string_view text) {
		std::vector<uint32_t> points;
		for (size_t at = 0; at < text.size();) {
			uint32_t code_point = 0;
			const size_t length = utf8::decode(text, at, code_point);
			if (length == 0) {
				code_point = static_cast<uint8_t>(text[at]);
			}
			points.push_back(code_point);
			at += std::max<size_t>(length, 1);
		}
		return points;
	}

	std::string identifier_skeleton(std::string_view name) {
		std::vector<uint32_t> mapped;
		for (const uint32_t point : identifier_nfkd(code_points_of(name))) {
			const Prototype* found = std::lower_bound(std::begin(PROTOTYPES), std::end(PROTOTYPES), point,
				[](const Prototype& entry, uint32_t code_point) { return entry.code_point < code_point; });
			if (found != std::end(PROTOTYPES) && found->code_point == point) {
				mapped.insert(mapped.end(), PROTOTYPE_POINTS + found->start, PROTOTYPE_POINTS + found->start + found->length);
			}
			else {
				mapped.push_back(point);
			}
		}
		std::string skeleton;
		for (const uint32_t point : identifier_nfkd(mapped)) {
			utf8::encode(point, skeleton);
		}
		return skeleton;
	}

	// The scripts a code point is used with, as indexes into SCRIPT_NAMES; none for Common and Inherited ones
	static std::pair<const uint8_t*, const uint8_t*> scripts_of(uint32_t code_point) {
		const ScriptRun* found = std::upper_bound(std::begin(SCRIPT_RUNS), std::end(SCRIPT_RUNS), code_point,
			[](uint32_t point, const ScriptRun& run) { return point < run.first; });
		if (code_point < 0x80 || found == std::begin(SCRIPT_RUNS) || code_point > (found - 1)->last) {
			// ASCII letters are Latin; the rest of ASCII a name can have, digits and _, go with any script
			static const uint8_t latin = static_cast<uint8_t>(std::find(std::begin(SCRIPT_CODES), std::end(SCRIPT_CODES),
				std::string_view("Latn")) - std::begin(SCRIPT_CODES));
			const bool letter = (code_point >= 'a' && code_point <= 'z') || (code_point >= 'A' && code_point <= 'Z');
			return letter ? std::make_pair(&latin, &latin + 1) : std::make_pair(&latin, &latin);
		}
		const ScriptRun& run = *(found - 1);
		return { SCRIPT_SETS + run.start, SCRIPT_SETS + run.start + run.count };
	}

	static uint8_t script_index(std::string_view code) {
		return static_cast<uint8_t>(std::find(std::begin(SCRIPT_CODES), std::end(SCRIPT_CODES), code) - std::begin(SCRIPT_CODES));
	}

	std::vector<std::string_view> mixed_scripts(std::string_view name) {
		using Scripts = std::bitset<256>;
		static const uint8_t LATIN = script_index("Latn"), HAN = script_index("Hani"), HIRAGANA = script_index("Hira"),
			KATAKANA = script_index("Kana"), BOPOMOFO = script_index("Bopo"), HANGUL = script_index("Hang");
		// UTS #39's combinations of scripts that Highly Restrictive allows
		static const std::array<Scripts, 3> ALLOWED = [] {
			std::array<Scripts, 3> sets;
			for (Scripts& set : sets) {
				set.set(LATIN).set(HAN);
			}
			sets[0].set(HIRAGANA).set(KATAKANA);
			sets[1].set(BOPOMOFO);
			sets[2].set(HANGUL);
			return sets;
		}();

		std::vector<Scripts> characters;
		Scripts together;
		together.set();
		for (const uint32_t point : code_points_of(name)) {
			const auto [first, last] = scripts_of(point);
			if (first == last) {
				continue;
			}
			Scripts scripts;
			for (const uint8_t* script = first; script != last; ++script) {
				scripts.set(*script);
			}
			characters.push_back(scripts);
			together &= scripts;
		}
		// One script, which every character is of
		if (characters.empty() || together.any()) {
			return {};
		}
		for (const Scripts& allowed : ALLOWED) {
			if (std::all_of(characters.begin(), characters.end(), [&](const Scripts& scripts) { return (scripts & allowed).any(); })) {
				return {};
			}
		}
		// Each script in the order it's first used, by the first of each character's
		std::vector<std::string_view> names;
		for (const uint32_t point : code_points_of(name)) {
			const auto [first, last] = scripts_of(point);
			if (first != last && std::find(names.begin(), names.end(), SCRIPT_NAMES[*first]) == names.end()) {
				names.push_back(SCRIPT_NAMES[*first]);
			}
		}
		return names;
	}

	uint32_t uncommon_code_point(std::string_view name) {
		for (const uint32_t point : code_points_of(name)) {
			if (point < 0x80) {
				continue;
			}
			const AllowedRun* found = std::upper_bound(std::begin(ALLOWED_RUNS), std::end(ALLOWED_RUNS), point,
				[](uint32_t code_point, const AllowedRun& run) { return code_point < run.first; });
			if (found == std::begin(ALLOWED_RUNS) || point > (found - 1)->last) {
				return point;
			}
		}
		return 0;
	}

	std::string_view script_name(uint32_t code_point) {
		const auto [first, last] = scripts_of(code_point);
		return first == last ? std::string_view("Common") : std::string_view(SCRIPT_NAMES[*first]);
	}
}
