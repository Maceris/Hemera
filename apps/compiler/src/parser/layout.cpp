#include "parser/layout.h"

#include <cstdint>
#include <limits>

namespace hemera::layout {

	namespace {
		// The parts every Document starts with, in this order after EMPTY, made once and shared
		constexpr Doc LINE = 1;
		constexpr Doc SOFT_LINE = 2;
		constexpr Doc HARD_LINE = 3;
		constexpr Doc LITERAL_LINE = 4;
		constexpr Doc BREAK_PARENT = 5;
	}

	size_t width_of(std::string_view text) {
		size_t width = 0;
		for (const char c : text) {
			// Every byte but a continuation byte starts a code point
			width += (static_cast<unsigned char>(c) & 0xC0) != 0x80 ? 1 : 0;
		}
		return width;
	}

	Document::Document() {
		parts.push_back(Part{ Kind::EMPTY, false, 0, 0, 0 });
		parts.push_back(Part{ Kind::LINE, false, 0, 0, 0 });
		parts.push_back(Part{ Kind::SOFT_LINE, false, 0, 0, 0 });
		parts.push_back(Part{ Kind::HARD_LINE, false, 0, 0, 0 });
		parts.push_back(Part{ Kind::LITERAL_LINE, false, 0, 0, 0 });
		parts.push_back(Part{ Kind::BREAK_PARENT, true, 0, 0, 0 });
	}

	Doc Document::add(Part part) {
		parts.push_back(part);
		return static_cast<Doc>(parts.size() - 1);
	}

	Doc Document::text(std::string_view text) {
		if (text.empty()) {
			return EMPTY;
		}
		const uint32_t first = static_cast<uint32_t>(texts.size());
		texts.append(text);
		return add(Part{ Kind::TEXT, false, first, static_cast<uint32_t>(text.size()), static_cast<uint32_t>(width_of(text)) });
	}

	Doc Document::line() {
		return LINE;
	}

	Doc Document::soft_line() {
		return SOFT_LINE;
	}

	Doc Document::hard_line() {
		return HARD_LINE;
	}

	Doc Document::literal_line() {
		return LITERAL_LINE;
	}

	Doc Document::break_parent() {
		return BREAK_PARENT;
	}

	Doc Document::line_suffix(Doc doc) {
		if (doc == EMPTY) {
			return EMPTY;
		}
		return add(Part{ Kind::LINE_SUFFIX, parts[doc].breaks, doc, 0, 0 });
	}

	Doc Document::concat(std::initializer_list<Doc> list) {
		size_t count = 0;
		Doc only = EMPTY;
		for (const Doc doc : list) {
			if (doc != EMPTY) {
				++count;
				only = doc;
			}
		}
		if (count <= 1) {
			return only;
		}
		const uint32_t first = static_cast<uint32_t>(children.size());
		bool breaks = false;
		for (const Doc doc : list) {
			if (doc != EMPTY) {
				children.push_back(doc);
				breaks = breaks || parts[doc].breaks;
			}
		}
		return add(Part{ Kind::CONCAT, breaks, first, static_cast<uint32_t>(count), 0 });
	}

	Doc Document::concat(const std::vector<Doc>& list) {
		size_t count = 0;
		Doc only = EMPTY;
		for (const Doc doc : list) {
			if (doc != EMPTY) {
				++count;
				only = doc;
			}
		}
		if (count <= 1) {
			return only;
		}
		const uint32_t first = static_cast<uint32_t>(children.size());
		bool breaks = false;
		for (const Doc doc : list) {
			if (doc != EMPTY) {
				children.push_back(doc);
				breaks = breaks || parts[doc].breaks;
			}
		}
		return add(Part{ Kind::CONCAT, breaks, first, static_cast<uint32_t>(count), 0 });
	}

	Doc Document::indent(Doc doc) {
		if (doc == EMPTY) {
			return EMPTY;
		}
		return add(Part{ Kind::INDENT, parts[doc].breaks, doc, 0, 0 });
	}

	Doc Document::group(Doc doc) {
		if (doc == EMPTY) {
			return EMPTY;
		}
		return add(Part{ Kind::GROUP, parts[doc].breaks, doc, 0, 0 });
	}

	Doc Document::if_break(Doc broken, Doc flat) {
		if (broken == EMPTY && flat == EMPTY) {
			return EMPTY;
		}
		return add(Part{ Kind::IF_BREAK, parts[broken].breaks || parts[flat].breaks, broken, flat, 0 });
	}

	Doc Document::fill(const std::vector<Doc>& list) {
		if (list.empty()) {
			return EMPTY;
		}
		// EMPTY items and separators are kept, so items and separators still alternate
		const uint32_t first = static_cast<uint32_t>(children.size());
		bool breaks = false;
		for (const Doc doc : list) {
			children.push_back(doc);
			breaks = breaks || parts[doc].breaks;
		}
		return add(Part{ Kind::FILL, breaks, first, static_cast<uint32_t>(list.size()), 0 });
	}

	Doc Document::isolate(Doc doc) {
		if (doc == EMPTY) {
			return EMPTY;
		}
		return add(Part{ Kind::ISOLATE, false, doc, 0, 0 });
	}

	Doc Document::flat(Doc doc) {
		if (doc == EMPTY) {
			return EMPTY;
		}
		// A line comment in it still needs the groups around it broken, to end its line
		return add(Part{ Kind::FLAT, parts[doc].breaks, doc, 0, 0 });
	}

	bool Document::breaks(Doc doc) const {
		return parts[doc].breaks;
	}

	size_t Document::flat_width(Doc doc) const {
		size_t width = 0;
		std::vector<Doc> stack{ doc };
		while (!stack.empty()) {
			const Part& part = parts[stack.back()];
			stack.pop_back();
			switch (part.kind) {
			case Kind::TEXT:
				width += part.width;
				break;
			case Kind::LINE:
				width += 1;
				break;
			case Kind::HARD_LINE:
			case Kind::LITERAL_LINE:
			case Kind::BREAK_PARENT:
				return SIZE_MAX;
			case Kind::CONCAT:
			case Kind::FILL:
				for (uint32_t i = 0; i < part.count; ++i) {
					stack.push_back(children[part.first + i]);
				}
				break;
			case Kind::GROUP:
				if (part.breaks) {
					return SIZE_MAX;
				}
				stack.push_back(part.first);
				break;
			case Kind::LINE_SUFFIX:
			case Kind::INDENT:
			case Kind::ISOLATE:
			case Kind::FLAT:
				stack.push_back(part.first);
				break;
			case Kind::IF_BREAK:
				stack.push_back(part.count);
				break;
			case Kind::EMPTY:
			case Kind::SOFT_LINE:
				break;
			}
		}
		return width;
	}

	/*
	 * Whether next fits in width columns, then rest (the commands printed after it, the next one last) up to
	 * the first line break: a flat line is a space, and a broken or hard one ends the measure. must_be_flat
	 * says a group that has to break doesn't fit, for an item of a fill.
	 */
	bool Document::fits(const std::vector<Command>& next, const std::vector<Command>& rest, int64_t width, bool must_be_flat) const {
		std::vector<Command> stack(next.rbegin(), next.rend());
		size_t rest_index = rest.size();
		while (width >= 0) {
			if (stack.empty()) {
				if (rest_index == 0) {
					return true;
				}
				stack.push_back(rest[--rest_index]);
				continue;
			}
			const Command command = stack.back();
			stack.pop_back();
			const Part& part = parts[command.doc];
			switch (part.kind) {
			case Kind::TEXT:
				width -= part.width;
				break;
			case Kind::CONCAT:
				for (uint32_t i = part.count; i > 0; --i) {
					stack.push_back(Command{ command.indent, command.flat, children[part.first + i - 1], 0, command.forced });
				}
				break;
			case Kind::FILL:
				for (uint32_t i = part.count; i > command.from; --i) {
					stack.push_back(Command{ command.indent, command.flat, children[part.first + i - 1], 0, command.forced });
				}
				break;
			case Kind::INDENT:
			case Kind::ISOLATE:
			case Kind::LINE_SUFFIX:
				stack.push_back(Command{ command.indent, command.flat, part.first, 0, command.forced });
				break;
			case Kind::FLAT:
				stack.push_back(Command{ command.indent, true, part.first, 0, true });
				break;
			case Kind::GROUP:
				if (must_be_flat && part.breaks && !command.forced) {
					return false;
				}
				/*
				 * A group not yet laid out counts as flat, even after this one in a broken group: a later group
				 * doesn't take this one's line break from it, so the first of two that don't fit breaks first
				 */
				stack.push_back(Command{ command.indent, command.forced || !part.breaks, part.first, 0, command.forced });
				break;
			case Kind::IF_BREAK:
				stack.push_back(Command{ command.indent, command.flat, command.flat ? part.count : part.first, 0, command.forced });
				break;
			case Kind::LINE:
				if (!command.flat) {
					return true;
				}
				width -= 1;
				break;
			case Kind::SOFT_LINE:
				if (!command.flat) {
					return true;
				}
				break;
			case Kind::HARD_LINE:
			case Kind::LITERAL_LINE:
				return true;
			case Kind::EMPTY:
			case Kind::BREAK_PARENT:
				break;
			}
		}
		return false;
	}

	std::string Document::render(Doc doc, size_t width, std::string_view newline) const {
		const bool unlimited = width == SIZE_MAX;
		std::string out;
		int64_t column = 0;
		/*
		 * The indent after a line break and a flat line's spaces are written only once text follows them, so
		 * a blank line or a line's end gets none.
		 */
		size_t pending_indent = 0;
		size_t pending_spaces = 0;
		std::vector<Command> stack{ Command{ 0, false, doc, 0 } };
		// Line suffixes waiting for the line's end, in the order they came
		std::vector<Command> suffixes;

		auto remaining = [&]() {
			return static_cast<int64_t>(width) - column;
		};

		while (!stack.empty() || !suffixes.empty()) {
			if (stack.empty()) {
				// The end of the layout ends the last line
				for (size_t i = suffixes.size(); i > 0; --i) {
					stack.push_back(suffixes[i - 1]);
				}
				suffixes.clear();
				continue;
			}
			const Command command = stack.back();
			stack.pop_back();
			const Part& part = parts[command.doc];
			switch (part.kind) {
			case Kind::TEXT:
				out.append(pending_indent, ' ');
				out.append(pending_spaces, ' ');
				pending_indent = 0;
				pending_spaces = 0;
				out.append(texts, part.first, part.count);
				column += part.width;
				break;
			case Kind::CONCAT:
				for (uint32_t i = part.count; i > 0; --i) {
					stack.push_back(Command{ command.indent, command.flat, children[part.first + i - 1], 0, command.forced });
				}
				break;
			case Kind::INDENT:
				stack.push_back(Command{ command.indent + INDENT_WIDTH, command.flat, part.first, 0, command.forced });
				break;
			case Kind::ISOLATE:
				stack.push_back(Command{ command.indent, command.flat, part.first, 0, command.forced });
				break;
			case Kind::FLAT:
				stack.push_back(Command{ command.indent, true, part.first, 0, true });
				break;
			case Kind::LINE_SUFFIX:
				suffixes.push_back(Command{ command.indent, command.flat, part.first, 0, command.forced });
				break;
			case Kind::GROUP: {
				/*
				 * Measured afresh even inside a flat group: what's flat up to a hard line can still have a
				 * group after it, on the next line, that doesn't fit.
				 */
				const Command flat{ command.indent, true, part.first, 0, command.forced };
				const bool flat_fits = command.forced || (!part.breaks && (unlimited || fits({ flat }, stack, remaining(), false)));
				stack.push_back(flat_fits ? flat : Command{ command.indent, false, part.first, 0, command.forced });
				break;
			}
			case Kind::IF_BREAK:
				stack.push_back(Command{ command.indent, command.flat, command.flat ? part.count : part.first, 0, command.forced });
				break;
			case Kind::FILL: {
				const uint32_t i = command.from;
				if (i >= part.count) {
					break;
				}
				const Doc item = children[part.first + i];
				const Command item_flat{ command.indent, true, item, 0, command.forced };
				const Command item_broken{ command.indent, false, item, 0, command.forced };
				const bool item_fits = unlimited || fits({ item_flat }, {}, remaining(), true);
				if (i + 1 >= part.count) {
					stack.push_back(item_fits ? item_flat : item_broken);
					break;
				}
				const Doc separator = children[part.first + i + 1];
				const Command separator_flat{ command.indent, true, separator, 0, command.forced };
				const Command separator_broken{ command.indent, false, separator, 0, command.forced };
				if (i + 2 >= part.count) {
					stack.push_back(item_fits && !parts[item].breaks ? separator_flat : separator_broken);
					stack.push_back(item_fits ? item_flat : item_broken);
					break;
				}
				/*
				 * Whether the next item fits after this one decides the separator between them, unless this one
				 * has a break_parent, like a line comment's, which ends its line
				 */
				const Command next_flat{ command.indent, true, children[part.first + i + 2], 0, command.forced };
				const bool both_fit = !parts[item].breaks
					&& (unlimited || fits({ item_flat, separator_flat, next_flat }, {}, remaining(), true));
				stack.push_back(Command{ command.indent, command.flat, command.doc, i + 2, command.forced });
				stack.push_back(both_fit ? separator_flat : separator_broken);
				stack.push_back(item_fits ? item_flat : item_broken);
				break;
			}
			case Kind::LINE:
			case Kind::SOFT_LINE:
			case Kind::HARD_LINE:
			case Kind::LITERAL_LINE: {
				const bool hard = part.kind == Kind::HARD_LINE || part.kind == Kind::LITERAL_LINE;
				if (command.flat && !hard) {
					if (part.kind == Kind::LINE) {
						pending_spaces += 1;
						column += 1;
					}
					break;
				}
				if (!suffixes.empty()) {
					// What waits for the line's end goes first, then this break again
					stack.push_back(command);
					for (size_t s = suffixes.size(); s > 0; --s) {
						stack.push_back(suffixes[s - 1]);
					}
					suffixes.clear();
					break;
				}
				out.append(newline);
				pending_spaces = 0;
				pending_indent = part.kind == Kind::LITERAL_LINE ? 0 : command.indent;
				column = static_cast<int64_t>(pending_indent);
				break;
			}
			case Kind::EMPTY:
			case Kind::BREAK_PARENT:
				break;
			}
		}
		return out;
	}

}
