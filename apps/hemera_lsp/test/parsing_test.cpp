#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

#include "gtest/gtest.h"

#include "parsing.h"

using hemera::lsp::parse_document;
using hemera::lsp::prepare_parsing;

TEST(Parsing, ParsesTextWithItsCommentsApart) {
	prepare_parsing();
	const auto parsed = parse_document("package main\n\n// A comment\nmain :: fn() -> int {\n    return 0 /* trailing */\n}\n", 3,
		"main.hsc");

	EXPECT_EQ(3, parsed->version);
	EXPECT_TRUE(parsed->lexed);
	EXPECT_NE(nullptr, parsed->tree);
	EXPECT_EQ(2u, parsed->comments.size());
	ASSERT_FALSE(parsed->tokens.empty());
	EXPECT_EQ(hemera::TokenType::END_OF_FILE, parsed->tokens.back().type);
}

TEST(Parsing, ASyntaxErrorLeavesTokensButNoTree) {
	prepare_parsing();
	const auto parsed = parse_document("package main\n\nmain :: fn( {\n", 1, "main.hsc");

	EXPECT_TRUE(parsed->lexed);
	EXPECT_EQ(nullptr, parsed->tree);
	EXPECT_FALSE(parsed->tokens.empty());
}

TEST(Parsing, ALexingErrorLeavesNothing) {
	prepare_parsing();
	const auto parsed = parse_document("package main\n\nx :: \"never closed\n", 1, "main.hsc");

	EXPECT_FALSE(parsed->lexed);
	EXPECT_EQ(nullptr, parsed->tree);
}

/*
 * How long the files in HEMERA_LSP_TIMED_FILES (separated by ;) take to lex and parse, printed; skipped without it.
 * Decision 6: requests are answered on the main thread if the largest files parse in tens of milliseconds.
 */
TEST(Parsing, Timing) {
	const char* files = std::getenv("HEMERA_LSP_TIMED_FILES");
	if (files == nullptr) {
		GTEST_SKIP() << "HEMERA_LSP_TIMED_FILES names no files";
	}
	prepare_parsing();
	std::string list(files);
	size_t start = 0;
	while (start < list.size()) {
		const size_t end = std::min(list.find(';', start), list.size());
		const std::string path = list.substr(start, end - start);
		start = end + 1;
		std::ifstream file(path, std::ios::binary);
		std::string text((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
		// The best of five, as the first warms the caches
		double best = 1e9;
		bool parsed = false;
		for (int run = 0; run < 5; ++run) {
			const auto before = std::chrono::steady_clock::now();
			const auto result = parse_document(text, 1, path);
			const auto after = std::chrono::steady_clock::now();
			best = std::min(best, std::chrono::duration<double, std::milli>(after - before).count());
			parsed = result->tree != nullptr;
		}
		std::cout << std::filesystem::path(path).filename().string() << ": " << text.size() << " bytes, " << best << " ms"
			<< (parsed ? "" : " (didn't parse)") << std::endl;
	}
}
