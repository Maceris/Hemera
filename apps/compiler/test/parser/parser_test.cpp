#include <filesystem>
#include <format>
#include <fstream>
#include <vector>

#include "gtest/gtest.h"

#include "hemera_errors.h"
#include "error/reporting.h"
#include "lexer/lexer.h"
#include "lexer/token.h"
#include "../string_cache_guard.h"
#include "parser/parser.h"

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
