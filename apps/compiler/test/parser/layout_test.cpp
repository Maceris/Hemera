#include <cstdint>
#include <string>
#include <vector>

#include "gtest/gtest.h"

#include "parser/layout.h"

using hemera::layout::Doc;
using hemera::layout::Document;
using hemera::layout::EMPTY;

namespace {
	// f(a, b, c): items one to a line where they don't fit, with a comma after the last one then (D3)
	Doc call(Document& d, const std::vector<std::string>& items) {
		std::vector<Doc> inside;
		for (size_t i = 0; i < items.size(); ++i) {
			if (i > 0) {
				inside.push_back(d.text(","));
				inside.push_back(d.line());
			}
			inside.push_back(d.text(items[i]));
		}
		return d.group(d.concat({
			d.text("f("),
			d.indent(d.concat({ d.soft_line(), d.concat(inside), d.if_break(d.text(",")) })),
			d.soft_line(),
			d.text(")"),
		}));
	}
}

TEST(Layout, WidthCountsCodePoints)
{
	EXPECT_EQ(hemera::layout::width_of(""), 0u);
	EXPECT_EQ(hemera::layout::width_of("abc"), 3u);
	// é, 私 and an emoji: 2, 3 and 4 bytes, a column each
	EXPECT_EQ(hemera::layout::width_of("\xC3\xA9\xE7\xA7\x81\xF0\x9F\x98\x80"), 3u);
}

TEST(Layout, TextAndConcat)
{
	Document d;
	EXPECT_EQ(d.render(EMPTY, 120), "");
	EXPECT_EQ(d.text(""), EMPTY);
	EXPECT_EQ(d.concat({ EMPTY, EMPTY }), EMPTY);
	const Doc a = d.text("a");
	EXPECT_EQ(d.concat({ EMPTY, a, EMPTY }), a);
	EXPECT_EQ(d.render(d.concat({ a, d.text("bc"), d.text("d") }), 120), "abcd");
}

TEST(Layout, GroupIsFlatWhereItFits)
{
	Document d;
	const Doc doc = call(d, { "aaa", "bbb", "ccc" });
	EXPECT_EQ(d.render(doc, 120), "f(aaa, bbb, ccc)");
	// Exactly the width fits
	EXPECT_EQ(d.render(doc, 16), "f(aaa, bbb, ccc)");
	EXPECT_EQ(d.render(doc, 15), "f(\n    aaa,\n    bbb,\n    ccc,\n)");
}

TEST(Layout, OutsideAnyGroupLinesBreak)
{
	Document d;
	EXPECT_EQ(d.render(d.concat({ d.text("a"), d.line(), d.text("b") }), 120), "a\nb");
}

TEST(Layout, UnlimitedWidthIsFlat)
{
	Document d;
	EXPECT_EQ(d.render(call(d, { "aaa", "bbb" }), SIZE_MAX), "f(aaa, bbb)");
}

TEST(Layout, OuterGroupBreaksFirst)
{
	// f(g(1, 2), long): f's arguments break, g's stay together (B2)
	Document d;
	const Doc inner = call(d, { "1", "2" });
	const Doc outer = d.group(d.concat({
		d.text("h("),
		d.indent(d.concat({ d.soft_line(), inner, d.text(","), d.line(), d.text("long_argument"), d.if_break(d.text(",")) })),
		d.soft_line(),
		d.text(")"),
	}));
	EXPECT_EQ(d.render(outer, 120), "h(f(1, 2), long_argument)");
	EXPECT_EQ(d.render(outer, 20), "h(\n    f(1, 2),\n    long_argument,\n)");
	// Too narrow for the inner one too
	EXPECT_EQ(d.render(outer, 8), "h(\n    f(\n        1,\n        2,\n    ),\n    long_argument,\n)");
}

TEST(Layout, WhatFollowsAGroupCountsUpToTheLineEnd)
{
	// f(a, b) + tail: the group fits only if the text after it on the line does too
	Document d;
	const Doc doc = d.concat({ call(d, { "a", "b" }), d.text(" + tail"), d.hard_line(), d.text("next line is long") });
	EXPECT_EQ(d.render(doc, 14), "f(a, b) + tail\nnext line is long");
	EXPECT_EQ(d.render(doc, 13), "f(\n    a,\n    b,\n) + tail\nnext line is long");
}

TEST(Layout, FirstOfTwoGroupsBreaksFirst)
{
	// f(aaa, bbb) -> g(ccc): when the line doesn't fit, the parameters break, not the result after them
	Document d;
	const Doc doc = d.concat({ call(d, { "aaa", "bbb" }), d.text(" -> "), call(d, { "ccc" }) });
	EXPECT_EQ(d.render(doc, 120), "f(aaa, bbb) -> f(ccc)");
	EXPECT_EQ(d.render(doc, 18), "f(\n    aaa,\n    bbb,\n) -> f(ccc)");
}

TEST(Layout, FlatNeverBreaks)
{
	// name(x) :: f(aaa, bbb): the name is flat, so the call after it breaks however narrow the line
	Document d;
	const Doc doc = d.concat({ d.flat(call(d, { "x" })), d.text(" :: "), call(d, { "aaa", "bbb" }) });
	EXPECT_EQ(d.render(doc, 10), "f(x) :: f(\n    aaa,\n    bbb,\n)");
	// A hard line in it still breaks
	EXPECT_EQ(d.render(d.flat(d.concat({ d.text("a"), d.hard_line(), d.text("b") })), 120), "a\nb");
	EXPECT_EQ(d.flat(EMPTY), EMPTY);
}

TEST(Layout, HardLineDoesNotBreakItsGroup)
{
	/*
	 * run(fn() { body }): the call stays on the first line, as what comes before the block's break fits.
	 * The argument is indented only where the call breaks, or a flat call would indent the block's lines.
	 */
	Document d;
	const Doc block = d.concat({ d.text("fn() {"), d.indent(d.concat({ d.hard_line(), d.text("body") })), d.hard_line(), d.text("}") });
	const Doc doc = d.group(d.concat({ d.text("run("), d.if_break(d.indent(d.concat({ d.soft_line(), block })), block), d.soft_line(), d.text(")") }));
	EXPECT_EQ(d.render(doc, 20), "run(fn() {\n    body\n})");
	EXPECT_EQ(d.render(doc, 5), "run(\n    fn() {\n        body\n    }\n)");
}

TEST(Layout, GroupsAfterAHardLineAreMeasuredAgain)
{
	// In a flat group, a group on a later line still breaks if it doesn't fit there
	Document d;
	const Doc later = call(d, { "aaaa", "bbbb" });
	const Doc doc = d.group(d.concat({ d.text("x"), d.hard_line(), later }));
	EXPECT_EQ(d.render(doc, 12), "x\nf(\n    aaaa,\n    bbbb,\n)");
}

TEST(Layout, IfBreak)
{
	Document d;
	const Doc doc = d.group(d.concat({ d.text("a"), d.line(), d.if_break(d.text("broken"), d.text("flat")) }));
	EXPECT_EQ(d.render(doc, 120), "a flat");
	EXPECT_EQ(d.render(doc, 3), "a\nbroken");
	EXPECT_EQ(d.if_break(EMPTY, EMPTY), EMPTY);
}

TEST(Layout, FillPacksItems)
{
	// .[1, 22, 333, ...]: as many items to a line as fit (B8)
	Document d;
	std::vector<Doc> parts;
	const std::vector<std::string> items = { "1", "22", "333", "4", "55", "666", "7" };
	for (size_t i = 0; i < items.size(); ++i) {
		if (i > 0) {
			parts.push_back(d.line());
		}
		parts.push_back(d.text(items[i] + ","));
	}
	const Doc doc = d.concat({ d.text("["), d.indent(d.concat({ d.hard_line(), d.fill(parts) })), d.hard_line(), d.text("]") });
	EXPECT_EQ(d.render(doc, 120), "[\n    1, 22, 333, 4, 55, 666, 7,\n]");
	EXPECT_EQ(d.render(doc, 16), "[\n    1, 22, 333,\n    4, 55, 666,\n    7,\n]");
	EXPECT_EQ(d.render(doc, 15), "[\n    1, 22, 333,\n    4, 55, 666,\n    7,\n]");
	EXPECT_EQ(d.render(doc, 14), "[\n    1, 22,\n    333, 4,\n    55, 666,\n    7,\n]");
	// An item too long for any line is still written, on its own line
	EXPECT_EQ(d.render(doc, 5), "[\n    1,\n    22,\n    333,\n    4,\n    55,\n    666,\n    7,\n]");
}

TEST(Layout, FillItemWithALineCommentEndsItsLine)
{
	// 1, 2, // two \n 3: the comment stays the last thing on its line
	Document d;
	const Doc commented = d.concat({ d.text("2,"), d.line_suffix(d.text(" // two")), d.break_parent() });
	const Doc doc = d.fill({ d.text("1,"), d.line(), commented, d.line(), d.text("3,"), d.line(), d.text("4") });
	EXPECT_EQ(d.render(doc, 120), "1, 2, // two\n3, 4");
	// A comment on a line of its own before an item, which a hard line follows, doesn't take the line after it
	const Doc heading = d.concat({ d.text("// three"), d.hard_line(), d.break_parent(), d.text("3,") });
	const Doc table = d.fill({ d.text("1,"), d.line(), d.text("2,"), d.hard_line(), heading, d.line(), d.text("4") });
	EXPECT_EQ(d.render(table, 120), "1, 2,\n// three\n3, 4");
}

TEST(Layout, BreakParentBreaksOutToAnIsolate)
{
	Document d;
	const Doc inner = d.group(d.concat({ d.text("a"), d.line(), d.text("b"), d.break_parent() }));
	const Doc outer = d.group(d.concat({ d.text("x"), d.line(), inner }));
	EXPECT_TRUE(d.breaks(outer));
	EXPECT_EQ(d.render(outer, 120), "x\na\nb");
	const Doc isolated = d.group(d.concat({ d.text("x"), d.line(), d.isolate(inner) }));
	EXPECT_FALSE(d.breaks(isolated));
	EXPECT_EQ(d.render(isolated, 120), "x a\nb");
}

TEST(Layout, LineSuffixWaitsForTheLineEnd)
{
	// f(a, // about a \n b): the comment goes after the comma, and its line comment breaks the call
	Document d;
	const Doc comment = d.concat({ d.line_suffix(d.text(" // about a")), d.break_parent() });
	const Doc doc = d.group(d.concat({
		d.text("f("),
		d.indent(d.concat({ d.soft_line(), d.text("a"), comment, d.text(","), d.line(), d.text("b"), d.if_break(d.text(",")) })),
		d.soft_line(),
		d.text(")"),
	}));
	EXPECT_EQ(d.render(doc, 120), "f(\n    a, // about a\n    b,\n)");
	// At the end of the layout
	EXPECT_EQ(d.render(d.concat({ d.text("x"), d.line_suffix(d.text(" // end")) }), 120), "x // end");
}

TEST(Layout, NoTrailingSpaces)
{
	Document d;
	// A blank line in an indented block, and a flat line's space at a hard line
	const Doc doc = d.concat({
		d.text("{"),
		d.indent(d.concat({ d.hard_line(), d.text("a"), d.hard_line(), d.hard_line(), d.text("b") })),
		d.hard_line(),
		d.text("}"),
	});
	EXPECT_EQ(d.render(doc, 120), "{\n    a\n\n    b\n}");
	const Doc spaced = d.group(d.concat({ d.text("a"), d.line(), d.hard_line(), d.text("b") }));
	EXPECT_EQ(d.render(spaced, 120), "a\nb");
}

TEST(Layout, LiteralLineHasNoIndent)
{
	Document d;
	const Doc doc = d.indent(d.concat({ d.text("a"), d.literal_line(), d.text("  kept"), d.hard_line(), d.text("b") }));
	EXPECT_EQ(d.render(doc, 120), "a\n  kept\n    b");
}

TEST(Layout, NewlineIsTheCallers)
{
	Document d;
	EXPECT_EQ(d.render(d.concat({ d.text("a"), d.hard_line(), d.text("b") }), 120, "\r\n"), "a\r\nb");
}

TEST(Layout, FlatWidth)
{
	Document d;
	EXPECT_EQ(d.flat_width(call(d, { "aaa", "bbb" })), 11u);
	EXPECT_EQ(d.flat_width(d.concat({ d.text("a"), d.hard_line() })), SIZE_MAX);
	EXPECT_EQ(d.flat_width(d.concat({ d.text("a"), d.break_parent() })), SIZE_MAX);
	EXPECT_EQ(d.flat_width(EMPTY), 0u);
}
