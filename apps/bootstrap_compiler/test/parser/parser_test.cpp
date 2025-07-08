#include <filesystem>
#include <format>
#include <fstream>
#include <vector>

#include "gtest/gtest.h"

#include "errors.h"
#include "error/reporting.h"
#include "lexer/lexer.h"
#include "lexer/token.h"
#include "parser/parser.h"

using hemera::Allocator;
using hemera::MyVector;
using hemera::Token;

static std::optional<hemera::ErrorCode> find_error(std::string_view name) {
	for (const auto& entry : hemera::ErrorInfoMap) {
		if (name.compare(entry.second.string_value) == 0) {
			return entry.first;
		}
	}
	return {};
}

TEST(ParserSmoke, SmokeTest)
{
	hemera::reset_reporting_storage();

	Allocator<> alloc;
	MyVector<Token> tokens;
	std::filesystem::path dir_path = std::filesystem::path(__FILE__).remove_filename();

	std::string file_path = dir_path.append("smoke_test.hsc").generic_string();

	std::ifstream file(file_path);

	if (!file.is_open()) {
		FAIL();
		return;
	}

	hemera::lexer::lex(file, tokens, alloc, file_path);
	EXPECT_FALSE(tokens.empty());

	Allocator<> node_alloc;

	hemera::ast::Node* ast = hemera::parser::file(file_path, tokens, node_alloc);

	EXPECT_NE(ast, nullptr);
	EXPECT_EQ(hemera::error_count(), 0);
}

TEST(ParserSmoke, ErrorScenarios)
{
	hemera::disable_reporting_printing();

	std::filesystem::path dir_path = std::filesystem::path(__FILE__).remove_filename().append("error_scenarios");

	if (!std::filesystem::exists(dir_path) || !std::filesystem::is_directory(dir_path)) {
		FAIL();
		return;
	}

	for (const auto& file : std::filesystem::directory_iterator(dir_path)) {
		hemera::reset_reporting_storage();

		std::string file_path = file.path().generic_string();
		std::string file_name = file.path().filename().generic_string();
		std::string error_code = file_name.substr(0, 5);
		std::optional<hemera::ErrorCode> maybe_code = find_error(error_code);
		if (!maybe_code) {
			FAIL();
			return;
		}
		hemera::ErrorCode actual_code = maybe_code.value();

		Allocator<> alloc;
		MyVector<Token> tokens;

		std::ifstream file(file_path);

		if (!file.is_open()) {
			FAIL();
			return;
		}

		hemera::lexer::lex(file, tokens, alloc, file_path);
		EXPECT_FALSE(tokens.empty());
		
		Allocator<> node_alloc;
		
		hemera::ast::Node* ast = hemera::parser::file(file_path, tokens, node_alloc);

		//TODO(ches) E3024_01.hsc - did not get an error
		//TODO(ches) E3028_02.hsc - got E3017: Unexpected token
		//TODO(ches) E3029_01.hsc - got E3017: Unexpected token
		//TODO(ches) E3029_02.hsc - got E3017: Unexpected token

		EXPECT_EQ(hemera::error_count(), 1) 
			<< std::format("Incorrect number of errors for {}", file_name);
		if (hemera::error_count() == 0) {
			continue;
		}
		
		const hemera::ErrorInfo& actual_info = hemera::ErrorInfoMap.find(hemera::error_list()[0])->second;

		EXPECT_EQ(hemera::error_list()[0], actual_code)
			<< std::format("Incorrect error code for {}, got {}: {}", file_name, actual_info.string_value, actual_info.message);
	}

	

}