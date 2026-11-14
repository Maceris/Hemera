#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace hemera::utf8 {

	/*
	 * Decodes the UTF-8 sequence starting at text[at], putting its code point in code_point. Returns the sequence's length
	 * in bytes, 1 to 4, or 0 if the bytes there aren't one (RFC 3629): a continuation byte with no lead, a sequence cut
	 * short by the text's end or by another lead, an overlong form, a surrogate (U+D800 to U+DFFF) or a code point past
	 * U+10FFFF. code_point is left as it was when 0 is returned. at must be less than text.size().
	 */
	inline size_t decode(std::string_view text, size_t at, uint32_t& code_point) {
		const uint8_t lead = static_cast<uint8_t>(text[at]);
		if (lead < 0x80) {
			code_point = lead;
			return 1;
		}
		size_t length = 0;
		uint8_t lowest = 0x80; // The second byte's range, which rules out overlong forms, surrogates and past U+10FFFF
		uint8_t highest = 0xbf;
		uint32_t value = 0;
		if (lead >= 0xc2 && lead <= 0xdf) {
			length = 2;
			value = lead & 0x1fu;
		}
		else if (lead >= 0xe0 && lead <= 0xef) {
			length = 3;
			value = lead & 0x0fu;
			lowest = lead == 0xe0 ? 0xa0 : 0x80;
			highest = lead == 0xed ? 0x9f : 0xbf;
		}
		else if (lead >= 0xf0 && lead <= 0xf4) {
			length = 4;
			value = lead & 0x07u;
			lowest = lead == 0xf0 ? 0x90 : 0x80;
			highest = lead == 0xf4 ? 0x8f : 0xbf;
		}
		else {
			return 0;
		}
		if (at + length > text.size()) {
			return 0;
		}
		for (size_t i = 1; i < length; ++i) {
			const uint8_t byte = static_cast<uint8_t>(text[at + i]);
			if (byte < (i == 1 ? lowest : 0x80) || byte > (i == 1 ? highest : 0xbf)) {
				return 0;
			}
			value = (value << 6) | (byte & 0x3fu);
		}
		code_point = value;
		return length;
	}

	/*
	 * Appends code_point's UTF-8 encoding, 1 to 4 bytes, to out. code_point must be at most U+10FFFF and not a surrogate;
	 * one that is gets the bytes its bits give, which aren't valid UTF-8.
	 */
	inline void encode(uint32_t code_point, std::string& out) {
		if (code_point < 0x80) {
			out += static_cast<char>(code_point);
		}
		else if (code_point < 0x800) {
			out += static_cast<char>(0xc0 | (code_point >> 6));
			out += static_cast<char>(0x80 | (code_point & 0x3f));
		}
		else if (code_point < 0x10000) {
			out += static_cast<char>(0xe0 | (code_point >> 12));
			out += static_cast<char>(0x80 | ((code_point >> 6) & 0x3f));
			out += static_cast<char>(0x80 | (code_point & 0x3f));
		}
		else {
			out += static_cast<char>(0xf0 | (code_point >> 18));
			out += static_cast<char>(0x80 | ((code_point >> 12) & 0x3f));
			out += static_cast<char>(0x80 | ((code_point >> 6) & 0x3f));
			out += static_cast<char>(0x80 | (code_point & 0x3f));
		}
	}

	/*
	 * Whether code_point changes the order text is displayed in without being seen itself (Unicode's Bidi_Control
	 * property): U+061C, U+200E, U+200F, U+202A to U+202E and U+2066 to U+2069. In source they can make code read
	 * differently from how it compiles ("Trojan Source", CVE-2021-42574), so they're only allowed written as escapes.
	 */
	inline bool is_bidirectional_control(uint32_t code_point) {
		return code_point == 0x061c || code_point == 0x200e || code_point == 0x200f
			|| (code_point >= 0x202a && code_point <= 0x202e) || (code_point >= 0x2066 && code_point <= 0x2069);
	}
}
