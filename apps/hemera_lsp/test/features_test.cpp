#include <string>

#include "gtest/gtest.h"

#include "features.h"

using hemera::lsp::changed_span;

TEST(ChangedSpan, SameTextIsNoChange) {
	EXPECT_FALSE(changed_span("abc", "abc").has_value());
}

TEST(ChangedSpan, CoversOnlyWhatDiffers) {
	const auto change = changed_span("f(a,b) {}", "f(a, b) {}");

	ASSERT_TRUE(change.has_value());
	EXPECT_EQ(4u, change->start);
	EXPECT_EQ(4u, change->end);
	EXPECT_EQ(" ", change->text);
}

TEST(ChangedSpan, Deletions) {
	const auto change = changed_span("a  b", "a b");

	ASSERT_TRUE(change.has_value());
	EXPECT_TRUE(change->text.empty());
	EXPECT_EQ("a b", std::string("a  b").replace(change->start, change->end - change->start, change->text));
}

TEST(ChangedSpan, NeverSplitsACharacter) {
	// é and è share their first byte, 0xC3
	const auto change = changed_span("x\xC3\xA9y", "x\xC3\xA8y");

	ASSERT_TRUE(change.has_value());
	EXPECT_EQ(1u, change->start);
	EXPECT_EQ(3u, change->end);
	EXPECT_EQ("\xC3\xA8", change->text);
}

TEST(ChangedSpan, NeverSplitsALineEnd) {
	// \r stays, and a \n is added after it: the change starts before the \r
	const auto change = changed_span("a\rb", "a\r\nb");

	ASSERT_TRUE(change.has_value());
	EXPECT_EQ("a\r\nb", std::string("a\rb").replace(change->start, change->end - change->start, change->text));
	EXPECT_LE(change->start, 1u);
}

TEST(ChangedSpan, RepeatedTextAtTheEdges) {
	// The common start and end overlap: "aa" to "aaa" adds one a
	const auto change = changed_span("aa", "aaa");

	ASSERT_TRUE(change.has_value());
	EXPECT_EQ("aaa", std::string("aa").replace(change->start, change->end - change->start, change->text));
}
