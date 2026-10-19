#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace hemera {
	/// <summary>
	/// Options in a format string, like the 08x in %{08x} (docs/format_strings.md): what base's
	/// runtime.FormatSpec holds, for formatting at compile time and checking format strings.
	/// </summary>
	struct FormatSpec {
		char fill = ' ';
		/// <summary>
		/// &lt; &gt; or ^, or 0 for the value's own: numbers to the right, everything else to the left.
		/// </summary>
		char align = 0;
		bool plus = false;
		bool prefix = false;
		bool zeros = false;
		size_t width = 0;
		bool has_precision = false;
		size_t precision = 0;
		/// <summary>
		/// d x X b or o, or 0 for the value's own way.
		/// </summary>
		char kind = 0;

		/// <summary>
		/// Whether the options change anything about how a value is written.
		/// </summary>
		bool plain() const;
	};

	/// <summary>
	/// The options in format at start, just after a placeholder: {...}, or none. next is where the
	/// format goes on after them. False when they aren't well formed.
	/// </summary>
	bool parse_format_spec(std::string_view format, size_t start, FormatSpec& spec, size_t& next);

	/// <summary>
	/// sign, prefix and body, made spec's width: zeros after the sign and prefix for a number with 0 and
	/// no alignment, or the fill on the side its alignment says.
	/// </summary>
	std::string format_padded(const FormatSpec& spec, std::string_view sign, std::string_view prefix, std::string_view body,
		bool numeric);

	/// <summary>
	/// An integer of magnitude, negative or not, in the base spec's kind says, with its sign, prefix and padding.
	/// </summary>
	std::string format_integer(const FormatSpec& spec, bool negative, uint64_t magnitude);

	/// <summary>
	/// Text cut to spec's precision, if it has one, and padded.
	/// </summary>
	std::string format_text(const FormatSpec& spec, std::string_view text);

	/// <summary>
	/// One placeholder in a format string: the value it takes, by index, its options, whether they're well
	/// formed, and where it starts in the format.
	/// </summary>
	struct FormatPlaceholder {
		size_t value = 0;
		FormatSpec spec;
		bool valid = true;
		size_t offset = 0;
		size_t length = 1;
		/// <summary>
		/// %0, which names no value.
		/// </summary>
		bool numbered_zero = false;
	};

	/// <summary>
	/// Each placeholder in format, in order, as the formatters read them: % takes the next value, %1, %2
	/// and so on that one, and %% is a %.
	/// </summary>
	std::vector<FormatPlaceholder> format_placeholders(std::string_view format);
}
