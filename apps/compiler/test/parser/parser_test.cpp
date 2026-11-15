#include <cstdlib>
#include <iostream>
#include <filesystem>
#include <format>
#include <fstream>
#include <sstream>
#include <algorithm>
#include <map>
#include <optional>
#include <vector>

#include "gtest/gtest.h"

#include "hemera_errors.h"
#include "error/reporting.h"
#include "lexer/lexer.h"
#include "lexer/token.h"
#include "../string_cache_guard.h"
#include "parser/parser.h"
#include "parser/formatting.h"
#include "parser/printing.h"
#include "front_end/documentation.h"

using hemera::Allocator;
using hemera::MyVector;
using hemera::Token;
using hemera::TokenType;

static std::optional<hemera::ErrorCode> find_error(std::string_view name) {
	for (const auto& entry : *hemera::error_info_map) {
		if (name.compare(entry.second.string_value) == 0) {
			return entry.first;
		}
	}
	return {};
}

TEST(ParserSmoke, SmokeTest)
{
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;

	Allocator<> alloc;
	MyVector<Token> tokens;
	std::filesystem::path dir_path = std::filesystem::path(__FILE__).remove_filename();

	std::string file_path = dir_path.append("smoke_test.hsc").generic_string();

	std::ifstream file(file_path);

	if (!file.is_open()) {
		FAIL();
	}

	hemera::lexer::lex(file, tokens, alloc, file_path);
	EXPECT_FALSE(tokens.empty());

	Allocator<> node_alloc;

	hemera::ast::Node* ast = hemera::parser::file(file_path, tokens, node_alloc);

	EXPECT_NE(ast, nullptr);
	EXPECT_EQ(hemera::error_count(), 0);

}

/*
 * Every file in valid_scenarios should parse without errors.
 * Each one covers a feature of the grammar, so failures point at the feature.
 */
TEST(ParserSmoke, ValidScenarios)
{
	// Printed, so a failure shows where in the file it is
	hemera::enable_reporting_printing();
	StringCacheGuard string_cache;

	std::filesystem::path dir_path = std::filesystem::path(__FILE__).remove_filename().append("valid_scenarios");

	if (!std::filesystem::exists(dir_path) || !std::filesystem::is_directory(dir_path)) {
		FAIL();
	}

	for (const auto& file : std::filesystem::directory_iterator(dir_path)) {
		hemera::reset_reporting_storage();

		std::string file_path = file.path().generic_string();
		std::string file_name = file.path().filename().generic_string();

		Allocator<> alloc;
		MyVector<Token> tokens;

		std::ifstream file_stream(file_path);

		if (!file_stream.is_open()) {
			FAIL();
		}

		hemera::lexer::lex(file_stream, tokens, alloc, file_path);
		EXPECT_FALSE(tokens.empty());

		Allocator<> node_alloc;

		hemera::ast::Node* ast = hemera::parser::file(file_path, tokens, node_alloc);

		EXPECT_NE(ast, nullptr);

		if (hemera::error_count() != 0) {
			const hemera::ErrorInfo& info = hemera::error_info_map->find(hemera::error_list()->at(0))->second;
			ADD_FAILURE() << std::format("{} didn't parse, first error {}: {}",
				file_name, info.string_value, info.message);
		}
	}
}

/*
 * Every .hsc file in the repository's base and std folders should parse,
 * since they're the largest body of Hemera code there is.
 */
TEST(ParserSmoke, BaseAndStd)
{
	hemera::enable_reporting_printing();
	StringCacheGuard string_cache;

	// test/parser -> apps/compiler -> repository root
	std::filesystem::path root = std::filesystem::path(__FILE__).remove_filename()
		.append("..").append("..").append("..").append("..");

	size_t parsed_count = 0;
	for (const char* folder : { "base", "std" }) {
		std::filesystem::path dir_path = std::filesystem::path(root).append(folder);
		if (!std::filesystem::is_directory(dir_path)) {
			ADD_FAILURE() << std::format("Couldn't find {}", dir_path.generic_string());
			continue;
		}

		for (const auto& file : std::filesystem::recursive_directory_iterator(dir_path)) {
			if (!file.is_regular_file() || file.path().extension() != ".hsc") {
				continue;
			}
			// builtin declares the language's own keywords, like null :: null
			if (file.path().parent_path().filename() == "builtin") {
				continue;
			}
			hemera::reset_reporting_storage();

			std::string file_path = std::filesystem::canonical(file.path()).generic_string();

			Allocator<> alloc;
			MyVector<Token> tokens;

			std::ifstream file_stream(file_path);
			if (!file_stream.is_open()) {
				ADD_FAILURE() << std::format("Couldn't open {}", file_path);
				continue;
			}

			hemera::lexer::lex(file_stream, tokens, alloc, file_path);

			Allocator<> node_alloc;
			hemera::ast::Node* ast = hemera::parser::file(file_path, tokens, node_alloc);

			EXPECT_NE(ast, nullptr);
			EXPECT_EQ(hemera::error_count(), 0) << std::format("{} didn't parse", file_path);
			parsed_count += 1;
		}
	}
	EXPECT_GT(parsed_count, 0);
}

/*
 * Printing a parsed file gives Hemera that parses back into the same tree (parser/printing.h), for
 * every file the parser takes in base, std and the scenarios: the printer knows every shape the
 * parser makes. Files that don't parse, like the error scenarios, are left out.
 */
namespace {
	// The files formatting and printing are checked against: base, std and the scenarios.
	std::vector<std::filesystem::path> round_trip_files()
	{
		std::filesystem::path test_root = std::filesystem::path(__FILE__).remove_filename().append("..");
		std::filesystem::path root = std::filesystem::path(test_root).append("..").append("..").append("..");
		std::vector<std::filesystem::path> folders = {
			std::filesystem::path(root).append("base"),
			std::filesystem::path(root).append("std"),
			std::filesystem::path(test_root).append("parser").append("valid_scenarios"),
			std::filesystem::path(test_root).append("front_end").append("scenarios"),
			std::filesystem::path(test_root).append("back_end").append("scenarios"),
		};
		std::vector<std::filesystem::path> files;
		for (const std::filesystem::path& folder : folders) {
			for (const auto& file : std::filesystem::recursive_directory_iterator(folder)) {
				if (file.is_regular_file() && file.path().extension() == ".hsc") {
					files.push_back(std::filesystem::canonical(file.path()));
				}
			}
		}
		std::sort(files.begin(), files.end());
		return files;
	}

	/*
	 * A comment's words, in order, without its markers (the slashes and stars that open and close it, and each
	 * line's star): what formatting keeps,
	 * though it can make a run of line comments one block (C2), lay a block's lines out again (C3) and break them (C5).
	 */
	void comment_words(std::string_view text, std::vector<std::string>& words)
	{
		size_t start = 0;
		while (start <= text.size()) {
			size_t end = text.find('\n', start);
			if (end == std::string_view::npos) {
				end = text.size();
			}
			std::string_view line = text.substr(start, end - start);
			start = end + 1;
			auto trim = [&]() {
				while (!line.empty() && (line.front() == ' ' || line.front() == '\t')) {
					line.remove_prefix(1);
				}
				while (!line.empty() && (line.back() == ' ' || line.back() == '\t' || line.back() == '\r')) {
					line.remove_suffix(1);
				}
			};
			trim();
			for (std::string_view marker : { "//", "/**", "/*" }) {
				if (line.starts_with(marker)) {
					line.remove_prefix(marker.size());
					break;
				}
			}
			if (line.ends_with("*/")) {
				line.remove_suffix(2);
			}
			trim();
			if (line.starts_with("*")) {
				line.remove_prefix(1);
			}
			std::istringstream split{ std::string(line) };
			std::string word;
			while (split >> word) {
				words.push_back(word);
			}
		}
	}

	/*
	 * Puts the imports in a row at the top of a file's tree in an order of their own, as formatting and printing sort
	 * them (D2), so trees that differ only in that compare the same. Returns their trees in the order they were in.
	 */
	std::vector<std::string> sort_top_imports(hemera::ast::Node* ast)
	{
		auto& children = ast->children;
		auto first = std::find_if(children.begin(), children.end(),
			[](const hemera::ast::Node* child) { return hemera::ast::NodeType::IMPORT == child->node_type; });
		auto last = std::find_if(first, children.end(),
			[](const hemera::ast::Node* child) { return hemera::ast::NodeType::IMPORT != child->node_type; });
		std::vector<std::string> imports;
		for (auto import_node = first; import_node != last; ++import_node) {
			imports.push_back(hemera::ast::dump(*import_node));
		}
		std::stable_sort(first, last, [](const hemera::ast::Node* a, const hemera::ast::Node* b) {
			return hemera::ast::dump(a) < hemera::ast::dump(b);
		});
		return imports;
	}

	struct Lexed {
		std::vector<std::string> comments;
		std::string tree;
		// The top imports' trees, in the file's order
		std::vector<std::string> imports;
		bool parsed = false;
	};

	// Whether formatting kept the comments: in order, or in any order where it put the imports in an order of their own.
	bool same_comments(const Lexed& before, const Lexed& after) {
		if (before.imports == after.imports) {
			return before.comments == after.comments;
		}
		std::vector<std::string> sorted_before = before.comments;
		std::vector<std::string> sorted_after = after.comments;
		std::sort(sorted_before.begin(), sorted_before.end());
		std::sort(sorted_after.begin(), sorted_after.end());
		return sorted_before == sorted_after;
	}

	// source's comments' words, in order, and its tree as dump writes it.
	Lexed lex_and_parse(const std::string& source, const std::string& file_path)
	{
		Lexed lexed;
		hemera::reset_reporting_storage();
		Allocator<> alloc;
		MyVector<Token> all_tokens;
		std::istringstream stream(source);
		hemera::lexer::lex(stream, all_tokens, alloc, file_path, true);
		MyVector<Token> tokens;
		for (const Token& token : all_tokens) {
			if (TokenType::COMMENT_BLOCK == token.type || TokenType::COMMENT_LINE == token.type) {
				comment_words(source.substr(token.offset, token.length), lexed.comments);
			}
			else {
				tokens.push_back(token);
			}
		}
		Allocator<> node_alloc;
		hemera::ast::QuoteTable quotes;
		hemera::ast::Node* ast = hemera::parser::file(file_path, tokens, node_alloc, &quotes);
		lexed.parsed = ast != nullptr && hemera::error_count() == 0;
		if (lexed.parsed) {
			lexed.imports = sort_top_imports(ast);
			lexed.tree = hemera::ast::dump(ast);
		}
		return lexed;
	}
}

/*
 * Formatting a file (parser/formatting.h) keeps every comment, once each and in order, and the tree it parses to,
 * and formatting it again changes nothing, for every file the parser takes in base, std and the scenarios.
 */
TEST(ParserSmoke, FormattingKeepsCommentsAndTrees)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;

	size_t formatted_count = 0;
	size_t failures = 0;
	for (const std::filesystem::path& path : round_trip_files()) {
		const std::string file_path = path.generic_string();
		std::ifstream file_stream(path, std::ios::binary);
		const std::string source((std::istreambuf_iterator<char>(file_stream)), std::istreambuf_iterator<char>());
		const Lexed before = lex_and_parse(source, file_path);
		if (!before.parsed) {
			continue;
		}
		hemera::reset_reporting_storage();
		const hemera::formatting::Result result = hemera::formatting::format_source(source, file_path);
		formatted_count += 1;
		std::string problem;
		if (!result.parsed) {
			problem = "didn't format";
		}
		else if (!result.lost_comments.empty()) {
			problem = std::format("lost {} comments, the first at byte {}", result.lost_comments.size(), result.lost_comments[0]);
		}
		else {
			const Lexed after = lex_and_parse(result.text, file_path + " (formatted)");
			if (!after.parsed) {
				problem = "formatted as something that doesn't parse";
			}
			else if (after.tree != before.tree) {
				problem = "formatted as a different tree";
			}
			else if (!same_comments(before, after)) {
				size_t i = 0;
				while (i < before.comments.size() && i < after.comments.size() && before.comments[i] == after.comments[i]) {
					++i;
				}
				problem = std::format("has {} words in comments formatted, {} before; the {}th differs: {} formatted as {}",
					after.comments.size(), before.comments.size(), i + 1, i < before.comments.size() ? before.comments[i] : "",
					i < after.comments.size() ? after.comments[i] : "");
			}
			else {
				// Formatting what formatting made changes nothing
				hemera::reset_reporting_storage();
				const hemera::formatting::Result again = hemera::formatting::format_source(result.text, file_path + " (formatted)");
				if (!again.parsed || again.text != result.text) {
					problem = std::format("formats differently a second time:\n{}", again.text);
				}
			}
		}
		if (problem.empty()) {
			continue;
		}
		if (++failures <= 5) {
			ADD_FAILURE() << std::format("{} {}:\n{}", file_path, problem, result.text);
		}
		else {
			ADD_FAILURE() << std::format("{} {}", file_path, problem);
		}
	}
	EXPECT_GT(formatted_count, 100);
}

/*
 * Each file in test/format/scenarios formats to its .expected file beside it, which formats to itself: the style
 * rules' examples, a scenario for each group of them.
 */
TEST(Formatting, Scenarios)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;

	const std::filesystem::path folder = std::filesystem::path(__FILE__).remove_filename().append("..").append("format").append("scenarios");
	auto read = [](const std::filesystem::path& path) {
		std::ifstream stream(path, std::ios::binary);
		return std::string((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
	};
	size_t count = 0;
	for (const auto& file : std::filesystem::directory_iterator(folder)) {
		if (file.path().extension() != ".hsc") {
			continue;
		}
		std::filesystem::path expected_path = file.path();
		expected_path.replace_extension(".expected");
		const std::string expected = read(expected_path);
		ASSERT_FALSE(expected.empty()) << expected_path.generic_string();
		hemera::reset_reporting_storage();
		const hemera::formatting::Result result = hemera::formatting::format_source(read(file.path()), file.path().generic_string());
		EXPECT_TRUE(result.parsed && result.lost_comments.empty()) << file.path().generic_string();
		EXPECT_EQ(result.text, expected) << file.path().generic_string();
		hemera::reset_reporting_storage();
		const hemera::formatting::Result again = hemera::formatting::format_source(expected, expected_path.generic_string());
		EXPECT_EQ(again.text, expected) << expected_path.generic_string() << " formats to something else";
		count += 1;
	}
	EXPECT_GE(count, 3u);
}

TEST(ParserSmoke, PrintingRoundTrips)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;

	// test/parser -> apps/compiler -> repository root
	std::filesystem::path test_root = std::filesystem::path(__FILE__).remove_filename().append("..");
	std::filesystem::path root = std::filesystem::path(test_root).append("..").append("..").append("..");

	std::vector<std::filesystem::path> folders = {
		std::filesystem::path(root).append("base"),
		std::filesystem::path(root).append("std"),
		std::filesystem::path(test_root).append("parser").append("valid_scenarios"),
		std::filesystem::path(test_root).append("front_end").append("scenarios"),
		std::filesystem::path(test_root).append("back_end").append("scenarios"),
	};

	size_t printed_count = 0;
	size_t failures = 0;
	for (const std::filesystem::path& folder : folders) {
		ASSERT_TRUE(std::filesystem::is_directory(folder)) << folder.generic_string();
		for (const auto& file : std::filesystem::recursive_directory_iterator(folder)) {
			if (!file.is_regular_file() || file.path().extension() != ".hsc") {
				continue;
			}
			const std::string file_path = std::filesystem::canonical(file.path()).generic_string();
			hemera::reset_reporting_storage();
			Allocator<> alloc;
			MyVector<Token> tokens;
			std::ifstream file_stream(file_path);
			ASSERT_TRUE(file_stream.is_open()) << file_path;
			hemera::lexer::lex(file_stream, tokens, alloc, file_path);
			Allocator<> node_alloc;
			hemera::ast::QuoteTable quotes;
			hemera::ast::Node* ast = hemera::parser::file(file_path, tokens, node_alloc, &quotes);
			if (ast == nullptr || hemera::error_count() != 0) {
				continue;
			}
			const std::string printed = hemera::ast::source_of(ast, &quotes);

			hemera::reset_reporting_storage();
			MyVector<Token> printed_tokens;
			std::istringstream printed_stream(printed);
			hemera::lexer::lex(printed_stream, printed_tokens, alloc, file_path + " (printed)");
			hemera::ast::QuoteTable printed_quotes;
			hemera::ast::Node* reparsed = hemera::parser::file(file_path + " (printed)", printed_tokens, node_alloc, &printed_quotes);
			printed_count += 1;
			const bool parsed = reparsed != nullptr && hemera::error_count() == 0;
			if (parsed) {
				sort_top_imports(reparsed);
				sort_top_imports(ast);
			}
			if (parsed && hemera::ast::dump(reparsed) == hemera::ast::dump(ast)) {
				continue;
			}
			// The first few, in full, to find what differs
			if (++failures <= 3) {
				ADD_FAILURE() << std::format("{} printed as something {}:\n{}\n--- parsed\n{}\n--- reparsed\n{}", file_path,
					parsed ? "else" : "that doesn't parse", printed, hemera::ast::dump(ast),
					parsed ? hemera::ast::dump(reparsed) : std::string());
			}
			else {
				ADD_FAILURE() << std::format("{} doesn't round-trip", file_path);
			}
		}
	}
	EXPECT_GT(printed_count, 100);
}

/*
 * Every file in base and std keeps its comments, every one, in order, each span picking out its text in the file's
 * bytes, with none left among its tokens; and its documentation comments are kept where they were before comments were
 * kept, the documentation table placed as by the tokens with comments among them (keep_documentation's old way).
 */
TEST(ParserSmoke, KeepsCommentsAndDocumentation)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;
	std::filesystem::path root = std::filesystem::path(__FILE__).remove_filename().append("..").append("..").append("..").append("..");

	size_t files = 0;
	size_t comments_kept = 0;
	size_t documented = 0;
	for (const char* folder : { "base", "std" }) {
		for (const auto& entry : std::filesystem::recursive_directory_iterator(std::filesystem::path(root).append(folder))) {
			if (!entry.is_regular_file() || entry.path().extension() != ".hsc") {
				continue;
			}
			const std::string file_path = std::filesystem::canonical(entry.path()).generic_string();
			std::ifstream stream(file_path, std::ios::binary);
			const std::string bytes((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
			hemera::reset_reporting_storage();
			Allocator<> alloc;
			MyVector<Token> tokens;
			std::istringstream input(bytes);
			hemera::lexer::lex(input, tokens, alloc, file_path, true);
			const MyVector<Token> with_comments = tokens;
			auto is_comment = [](const Token& token) {
				return TokenType::COMMENT_BLOCK == token.type || TokenType::COMMENT_LINE == token.type;
			};

			// Where each documentation comment documents, found the old way, over the tokens with comments among them
			std::map<std::pair<uint32_t, uint16_t>, std::pair<uint32_t, uint16_t>> leading;
			std::map<uint32_t, std::pair<uint32_t, uint16_t>> trailing;
			for (size_t i = 0; i < with_comments.size(); ++i) {
				const Token& token = with_comments[i];
				if (TokenType::COMMENT_BLOCK != token.type || token.value == nullptr || !hemera::is_documentation(*token.value)) {
					continue;
				}
				const std::pair<uint32_t, uint16_t> at{ token.line_number, token.column_number };
				if (std::string_view(*token.value).starts_with("/**<")) {
					for (size_t before = i; before > 0; --before) {
						if (!is_comment(with_comments[before - 1])) {
							trailing[with_comments[before - 1].line_number] = at;
							break;
						}
					}
					continue;
				}
				size_t next = i + 1;
				while (next < with_comments.size() && is_comment(with_comments[next])) {
					next += 1;
				}
				if (next + 1 < with_comments.size() && TokenType::KEYWORD_USING == with_comments[next].type) {
					next += 1;
				}
				if (next < with_comments.size() && TokenType::IDENTIFIER == with_comments[next].type) {
					leading.try_emplace({ with_comments[next].line_number, with_comments[next].column_number }, at);
				}
			}

			MyVector<Token> comments;
			hemera::keep_documentation(file_path, tokens, comments, false);
			files += 1;

			// Every comment kept, in order, and none left among the tokens
			std::vector<uint32_t> expected;
			for (const Token& token : with_comments) {
				if (is_comment(token)) {
					expected.push_back(token.offset);
				}
			}
			std::vector<uint32_t> kept;
			for (const Token& comment : comments) {
				kept.push_back(comment.offset);
				// Its span is its text, as the file has it, but for CRs and a line comment's line ending
				std::string spanned = bytes.substr(comment.offset, comment.length);
				std::erase(spanned, '\r');
				std::string text(*comment.value);
				if (TokenType::COMMENT_LINE == comment.type && text.ends_with('\n')) {
					text.pop_back();
				}
				EXPECT_EQ(spanned, text) << file_path << " at " << comment.line_number;
			}
			EXPECT_EQ(kept, expected) << file_path;
			EXPECT_TRUE(std::none_of(tokens.begin(), tokens.end(), is_comment)) << file_path;
			comments_kept += comments.size();

			// Each documentation comment where it was
			for (const auto& [key, at] : leading) {
				const std::optional<hemera::Documentation> found = hemera::documentation_at(file_path, key.first, key.second);
				ASSERT_TRUE(found.has_value()) << file_path << " at " << key.first;
				EXPECT_EQ(std::make_pair(found->line, found->column), at) << file_path << " at " << key.first;
			}
			for (const auto& [line, at] : trailing) {
				// A column no token starts at, so only a trailing comment on the line answers
				const std::optional<hemera::Documentation> found = hemera::documentation_at(file_path, line, UINT16_MAX);
				ASSERT_TRUE(found.has_value()) << file_path << " at " << line;
				EXPECT_EQ(std::make_pair(found->line, found->column), at) << file_path << " at " << line;
			}
			documented += leading.size() + trailing.size();
		}
	}
	EXPECT_GT(files, 200u);
	EXPECT_GT(comments_kept, 5000u);
	EXPECT_GT(documented, 3000u);
}

TEST(ParserSmoke, ErrorScenarios)
{
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;

	std::filesystem::path dir_path = std::filesystem::path(__FILE__).remove_filename().append("error_scenarios");

	if (!std::filesystem::exists(dir_path) || !std::filesystem::is_directory(dir_path)) {
		FAIL();
	}

	for (const auto& file : std::filesystem::directory_iterator(dir_path)) {
		hemera::reset_reporting_storage();

		std::string file_path = file.path().generic_string();
		std::string file_name = file.path().filename().generic_string();
		std::string error_code = file_name.substr(0, 5);
		std::optional<hemera::ErrorCode> maybe_code = find_error(error_code);
		if (!maybe_code) {
			FAIL();
		}
		hemera::ErrorCode actual_code = maybe_code.value();

		Allocator<> alloc;
		MyVector<Token> tokens;

		std::ifstream file_stream(file_path);

		if (!file_stream.is_open()) {
			FAIL();
		}

		hemera::lexer::lex(file_stream, tokens, alloc, file_path);
		EXPECT_FALSE(tokens.empty());
		
		Allocator<> node_alloc;

		hemera::ast::Node* ast = hemera::parser::file(file_path, tokens, node_alloc);

		EXPECT_NE(ast, nullptr);

		EXPECT_EQ(hemera::error_count(), 1) 
			<< std::format("Incorrect number of errors for {}", file_name);
		if (hemera::error_count() == 0) {
			continue;
		}
		
		const hemera::ErrorInfo& actual_info = hemera::error_info_map->find(hemera::error_list()->at(0))->second;

		EXPECT_EQ(hemera::error_list()->at(0), actual_code)
			<< std::format("Incorrect error code for {}, got {}: {}", file_name, actual_info.string_value, actual_info.message);
	}

}

/*
 * Prints the tree of the file named by HEMERA_DUMP_AST, for looking at what the parser makes:
 * HemeraTest --gtest_also_run_disabled_tests --gtest_filter=*DumpAst
 */
/*
 * Prints the file HEMERA_PRINT_SOURCE names as the printer writes it (parser/printing.h), for finding
 * what doesn't round-trip. Run with --gtest_also_run_disabled_tests.
 */
TEST(ParserSmoke, DISABLED_PrintSource)
{
	const char* path = std::getenv("HEMERA_PRINT_SOURCE");
	ASSERT_NE(path, nullptr) << "Set HEMERA_PRINT_SOURCE to a file";
	hemera::enable_reporting_printing();
	StringCacheGuard string_cache;

	std::ifstream file_stream(path);
	ASSERT_TRUE(file_stream.is_open());
	Allocator<> alloc;
	MyVector<Token> tokens;
	hemera::lexer::lex(file_stream, tokens, alloc, path);
	Allocator<> node_alloc;
	hemera::ast::QuoteTable quotes;
	hemera::ast::Node* ast = hemera::parser::file(path, tokens, node_alloc, &quotes);
	std::cout << hemera::ast::source_of(ast, &quotes);
}

/*
 * Writes what formatting makes of every file FormattingKeepsCommentsAndTrees reads into the folder
 * HEMERA_FORMAT_ALL_TO names, each at its path under the repository root, for comparing with the files or
 * with another version's. HEMERA_FORMAT_WIDTH sets the width, 120 if it isn't set. Run with
 * --gtest_also_run_disabled_tests.
 */
TEST(ParserSmoke, DISABLED_FormatAll)
{
	const char* to = std::getenv("HEMERA_FORMAT_ALL_TO");
	ASSERT_NE(to, nullptr) << "Set HEMERA_FORMAT_ALL_TO to a folder";
	const char* width_text = std::getenv("HEMERA_FORMAT_WIDTH");
	const size_t width = width_text != nullptr ? std::stoull(width_text) : hemera::formatting::LINE_WIDTH;
	hemera::disable_reporting_printing();
	StringCacheGuard string_cache;

	const std::filesystem::path root = std::filesystem::canonical(
		std::filesystem::path(__FILE__).remove_filename().append("..").append("..").append("..").append(".."));
	for (const std::filesystem::path& path : round_trip_files()) {
		std::ifstream file_stream(path, std::ios::binary);
		const std::string source((std::istreambuf_iterator<char>(file_stream)), std::istreambuf_iterator<char>());
		hemera::reset_reporting_storage();
		const hemera::formatting::Result result = hemera::formatting::format_source(source, path.generic_string(), width);
		if (!result.parsed) {
			continue;
		}
		std::filesystem::path out_path = std::filesystem::path(to) / std::filesystem::relative(path, root);
		std::filesystem::create_directories(out_path.parent_path());
		std::ofstream out(out_path, std::ios::binary);
		out << result.text;
	}
}

TEST(ParserSmoke, DISABLED_DumpAst)
{
	const char* path = std::getenv("HEMERA_DUMP_AST");
	ASSERT_NE(path, nullptr) << "Set HEMERA_DUMP_AST to a file";
	hemera::enable_reporting_printing();
	StringCacheGuard string_cache;

	std::ifstream file_stream(path);
	ASSERT_TRUE(file_stream.is_open());
	Allocator<> alloc;
	MyVector<Token> tokens;
	hemera::lexer::lex(file_stream, tokens, alloc, path);
	Allocator<> node_alloc;
	hemera::ast::Node* ast = hemera::parser::file(path, tokens, node_alloc);
	std::cout << hemera::ast::dump(ast);
}
