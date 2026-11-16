#include <string>

#include "gtest/gtest.h"

#include "documents.h"

using hemera::lsp::Documents;
using hemera::lsp::Encoding;
using hemera::lsp::LineIndex;

TEST(LineIndex, SplitsAtEveryLineEnd) {
	const LineIndex index("one\ntwo\r\nthree\rfour");

	ASSERT_EQ(4u, index.line_count());
	EXPECT_EQ("one", index.line(0));
	EXPECT_EQ("two", index.line(1));
	EXPECT_EQ("three", index.line(2));
	EXPECT_EQ("four", index.line(3));
	EXPECT_EQ("", index.line(4));
}

TEST(LineIndex, CountsALastEmptyLine) {
	EXPECT_EQ(1u, LineIndex("").line_count());
	EXPECT_EQ(2u, LineIndex("a\n").line_count());
}

TEST(LineIndex, Utf8IsBytes) {
	const LineIndex index("x := \"\xC3\xA9\"");

	EXPECT_EQ(7u, index.character(0, 7, Encoding::UTF8));
}

TEST(LineIndex, Utf16CountsCodeUnits) {
	// a, é (2 bytes, 1 unit), € (3 bytes, 1 unit), 𝄞 (4 bytes, 2 units), b
	const LineIndex index("a\xC3\xA9\xE2\x82\xAC\xF0\x9D\x84\x9E" "b");

	EXPECT_EQ(1u, index.character(0, 1, Encoding::UTF16));
	EXPECT_EQ(2u, index.character(0, 3, Encoding::UTF16));
	EXPECT_EQ(3u, index.character(0, 6, Encoding::UTF16));
	EXPECT_EQ(5u, index.character(0, 10, Encoding::UTF16));
	EXPECT_EQ(6u, index.character(0, 11, Encoding::UTF16));
}

TEST(LineIndex, PastTheEndIsTheEnd) {
	const LineIndex index("ab\ncd");

	EXPECT_EQ(2u, index.character(0, 9, Encoding::UTF16));
	EXPECT_EQ(0u, index.character(5, 3, Encoding::UTF16));
}

TEST(LineIndex, BrokenBytesCountOneEach) {
	// A lead byte without its continuation, then a stray continuation
	const LineIndex index("\xE2" "a\x80" "b");

	EXPECT_EQ(4u, index.character(0, 4, Encoding::UTF16));
}

TEST(Documents, FindsByUriAndByPath) {
	Documents documents;
	documents.open("file:///d%3A/project/main.hsc", "text", 1);

	ASSERT_NE(nullptr, documents.find_uri("file:///d%3A/project/main.hsc"));
	EXPECT_EQ("d:/project/main.hsc", documents.find_uri("file:///d%3A/project/main.hsc")->path);
	EXPECT_NE(nullptr, documents.find_path("d:/project/main.hsc"));
#ifdef _WIN32
	EXPECT_NE(nullptr, documents.find_path("D:\\project\\main.hsc"));
#endif
	EXPECT_EQ(nullptr, documents.find_path("d:/project/other.hsc"));
}

TEST(Documents, ChangesReplaceTheText) {
	Documents documents;
	documents.open("file:///d%3A/main.hsc", "old", 1);
	documents.change("file:///d%3A/main.hsc", "new", 2);

	EXPECT_EQ("new", documents.find_uri("file:///d%3A/main.hsc")->text);
	EXPECT_EQ(2, documents.find_uri("file:///d%3A/main.hsc")->version);
}

TEST(Documents, ClosedAreForgotten) {
	Documents documents;
	documents.open("file:///d%3A/main.hsc", "text", 1);
	documents.close("file:///d%3A/main.hsc");

	EXPECT_EQ(nullptr, documents.find_uri("file:///d%3A/main.hsc"));
	EXPECT_TRUE(documents.all().empty());
}

TEST(Documents, KeepsOtherSchemesWithoutAPath) {
	Documents documents;
	documents.open("untitled:Untitled-1", "text", 1);

	ASSERT_NE(nullptr, documents.find_uri("untitled:Untitled-1"));
	EXPECT_EQ("", documents.find_uri("untitled:Untitled-1")->path);
}
