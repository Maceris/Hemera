#include "front_end/format_spec.h"

/*
 * Options in format strings (docs/format_strings.md), the same as base/runtime/format.hsc reads them,
 * for the compile-time formatter and for checking constant format strings.
 */
namespace hemera {
	namespace {
		bool is_alignment(char character) {
			return character == '<' || character == '>' || character == '^';
		}

		bool is_kind(char character) {
			return character == 'd' || character == 'x' || character == 'X' || character == 'b' || character == 'o';
		}

		bool is_digit(char character) {
			return character >= '0' && character <= '9';
		}
	}

	bool FormatSpec::plain() const {
		return width == 0 && kind == 0 && !plus && !prefix && !has_precision;
	}

	bool parse_format_spec(std::string_view format, size_t start, FormatSpec& spec, size_t& next) {
		spec = FormatSpec{};
		next = start;
		if (start >= format.size() || format[start] != '{') {
			return true;
		}
		size_t index = start + 1;
		if (index + 1 < format.size() && is_alignment(format[index + 1])) {
			spec.fill = format[index];
			spec.align = format[index + 1];
			index += 2;
		}
		else if (index < format.size() && is_alignment(format[index])) {
			spec.align = format[index];
			index += 1;
		}
		if (index < format.size() && format[index] == '+') {
			spec.plus = true;
			++index;
		}
		if (index < format.size() && format[index] == '#') {
			spec.prefix = true;
			++index;
		}
		if (index < format.size() && format[index] == '0') {
			spec.zeros = true;
			++index;
		}
		while (index < format.size() && is_digit(format[index])) {
			spec.width = spec.width * 10 + static_cast<size_t>(format[index] - '0');
			++index;
		}
		bool valid = true;
		if (index < format.size() && format[index] == '.') {
			++index;
			spec.has_precision = true;
			valid = index < format.size() && is_digit(format[index]);
			while (index < format.size() && is_digit(format[index])) {
				spec.precision = spec.precision * 10 + static_cast<size_t>(format[index] - '0');
				++index;
			}
		}
		if (index < format.size() && is_kind(format[index])) {
			spec.kind = format[index];
			++index;
		}
		if (valid && index < format.size() && format[index] == '}') {
			next = index + 1;
			return true;
		}
		// Not well formed: what follows is after the closing brace
		while (index < format.size()) {
			++index;
			if (format[index - 1] == '}') {
				break;
			}
		}
		next = index;
		return false;
	}

	std::string format_padded(const FormatSpec& spec, std::string_view sign, std::string_view prefix, std::string_view body,
		bool numeric) {

		const size_t length = sign.size() + prefix.size() + body.size();
		const size_t padding = spec.width > length ? spec.width - length : 0;
		std::string out;
		if (numeric && spec.zeros && spec.align == 0) {
			out.append(sign).append(prefix).append(padding, '0').append(body);
			return out;
		}
		const char align = spec.align != 0 ? spec.align : numeric ? '>' : '<';
		const size_t before = align == '>' ? padding : align == '^' ? padding / 2 : 0;
		out.append(before, spec.fill).append(sign).append(prefix).append(body).append(padding - before, spec.fill);
		return out;
	}

	std::string format_integer(const FormatSpec& spec, bool negative, uint64_t magnitude) {
		const uint64_t base = spec.kind == 'x' || spec.kind == 'X' ? 16 : spec.kind == 'b' ? 2 : spec.kind == 'o' ? 8 : 10;
		const char* digits = spec.kind == 'X' ? "0123456789ABCDEF" : "0123456789abcdef";
		std::string body;
		do {
			body.insert(body.begin(), digits[magnitude % base]);
			magnitude /= base;
		} while (magnitude != 0);
		const std::string_view sign = negative ? "-" : spec.plus ? "+" : "";
		const std::string_view prefix = !spec.prefix || base == 10 ? "" : base == 16 ? "0x" : base == 2 ? "0b" : "0o";
		return format_padded(spec, sign, prefix, body, true);
	}

	std::string format_text(const FormatSpec& spec, std::string_view text) {
		if (spec.has_precision && spec.precision < text.size()) {
			text = text.substr(0, spec.precision);
		}
		return format_padded(spec, "", "", text, false);
	}

	std::vector<FormatPlaceholder> format_placeholders(std::string_view format) {
		std::vector<FormatPlaceholder> result;
		size_t next = 0;
		for (size_t i = 0; i < format.size(); ++i) {
			if (format[i] != '%') {
				continue;
			}
			if (i + 1 < format.size() && format[i + 1] == '%') {
				++i;
				continue;
			}
			FormatPlaceholder placeholder;
			placeholder.offset = i;
			size_t number = 0;
			bool numbered = false;
			while (i + 1 < format.size() && is_digit(format[i + 1])) {
				number = number * 10 + static_cast<size_t>(format[i + 1] - '0');
				numbered = true;
				++i;
			}
			size_t after = i + 1;
			placeholder.valid = parse_format_spec(format, i + 1, placeholder.spec, after);
			i = after - 1;
			placeholder.length = after - placeholder.offset;
			placeholder.numbered_zero = numbered && number == 0;
			placeholder.value = numbered ? (number > 0 ? number - 1 : 0) : next++;
			result.push_back(placeholder);
		}
		return result;
	}
}
