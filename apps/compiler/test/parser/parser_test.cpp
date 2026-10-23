#include <cstdlib>
#include <iostream>
#include <filesystem>
#include <format>
#include <fstream>
#include <sstream>
#include <vector>

#include "gtest/gtest.h"

#include "hemera_errors.h"
#include "error/reporting.h"
#include "lexer/lexer.h"
#include "lexer/token.h"
#include "../string_cache_guard.h"
#include "parser/parser.h"
#include "parser/printing.h"

using hemera::Allocator;
using hemera::MyVector;
using hemera::Token;

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
