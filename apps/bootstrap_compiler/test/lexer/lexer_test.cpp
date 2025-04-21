#include <format>

#include "gtest/gtest.h"

#include "lexer/lexer.h"
#include "lexer/token.h"

using hemera::Allocator;
using hemera::MyVector;
using hemera::Token;
using hemera::TokenType;

TEST(SingleTokenTest, OptionsWithoutArgs)
{
	Allocator<> alloc;
	MyVector<Token> output;
	
	std::istringstream plus("+");

	hemera::lexer::lex(plus, output, alloc);

	EXPECT_EQ(output.size(), 2);
	EXPECT_EQ(output[0].type, TokenType::OPERATOR_PLUS);
	EXPECT_EQ(output[0].line_number, 1);
	EXPECT_EQ(output[0].column_number, 0);
	EXPECT_EQ(output[0].value, nullptr);
	
	EXPECT_EQ(output[1].type, TokenType::END_OF_FILE);
	EXPECT_EQ(output[1].line_number, 1);
	EXPECT_EQ(output[1].column_number, 1);
	EXPECT_EQ(output[1].value, nullptr);
}
