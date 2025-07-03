#include <filesystem>
#include <fstream>
#include <vector>

#include "gtest/gtest.h"

#include "error/reporting.h"
#include "lexer/lexer.h"
#include "lexer/token.h"
#include "parser/parser.h"

using hemera::Allocator;
using hemera::MyVector;
using hemera::Token;

TEST(ParserSmoke, SmokeTest)
{
	Allocator<> alloc;
	MyVector<Token> tokens;
	std::filesystem::path dir_path = std::filesystem::path(__FILE__).remove_filename();

	std::string file_path = dir_path.append("smoke_test.hsc").generic_string();

	std::ifstream file(file_path);

	if (!file.is_open()) {
		FAIL();
		return;
	}

	hemera::lexer::lex(file, tokens, alloc, __FILE__);
	EXPECT_FALSE(tokens.empty());

	Allocator<> node_alloc;

	hemera::ast::Node* ast = hemera::parser::file(file_path, tokens, node_alloc);

	EXPECT_NE(ast, nullptr);
	EXPECT_EQ(hemera::error_count(), 0);
}