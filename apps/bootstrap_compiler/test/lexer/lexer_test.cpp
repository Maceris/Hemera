#include <format>
#include <tuple>
#include <vector>

#include "gtest/gtest.h"

#include "lexer/lexer.h"
#include "lexer/token.h"

using hemera::Allocator;
using hemera::MyVector;
using hemera::Token;
using hemera::TokenType;

TEST(SingleSimpleTokenTest, OptionsWithoutArgs)
{
	Allocator<> alloc;
	MyVector<Token> output;

	std::vector<std::tuple<std::string, TokenType>> inputs;

	inputs.push_back(std::make_tuple("+", TokenType::OPERATOR_PLUS));
	inputs.push_back(std::make_tuple("-", TokenType::OPERATOR_MINUS));
	inputs.push_back(std::make_tuple("*", TokenType::OPERATOR_MULTIPLY));
	inputs.push_back(std::make_tuple("/", TokenType::OPERATOR_DIVIDE));
	inputs.push_back(std::make_tuple("%", TokenType::OPERATOR_MODULUS));
	inputs.push_back(std::make_tuple("&", TokenType::OPERATOR_BITWISE_AND));
	inputs.push_back(std::make_tuple("|", TokenType::OPERATOR_BITWISE_OR));
	inputs.push_back(std::make_tuple("~", TokenType::OPERATOR_BITWISE_XOR));
	inputs.push_back(std::make_tuple("!", TokenType::OPERATOR_NOT));
	inputs.push_back(std::make_tuple("^", TokenType::OPERATOR_DEREFERENCE));
	inputs.push_back(std::make_tuple("=", TokenType::OPERATOR_ASSIGN));
	inputs.push_back(std::make_tuple(":", TokenType::SYM_COLON));
	inputs.push_back(std::make_tuple("?", TokenType::SYM_QUESTION));
	inputs.push_back(std::make_tuple("<", TokenType::SYM_LT));
	inputs.push_back(std::make_tuple(">", TokenType::SYM_GT));
	inputs.push_back(std::make_tuple(",", TokenType::SYM_COMMA));
	inputs.push_back(std::make_tuple(".", TokenType::SYM_DOT));
	inputs.push_back(std::make_tuple("[", TokenType::SYM_LBRACK));
	inputs.push_back(std::make_tuple("{", TokenType::SYM_LBRACE));
	inputs.push_back(std::make_tuple("(", TokenType::SYM_LPAREN));
	inputs.push_back(std::make_tuple("]", TokenType::SYM_RBRACK));
	inputs.push_back(std::make_tuple("}", TokenType::SYM_RBRACE));
	inputs.push_back(std::make_tuple(")", TokenType::SYM_RPAREN));
	inputs.push_back(std::make_tuple("_", TokenType::SYM_UNDERSCORE));
	inputs.push_back(std::make_tuple("=>", TokenType::SYM_ARROW_DOUBLE));
	inputs.push_back(std::make_tuple("->", TokenType::SYM_ARROW_SINGLE));
	inputs.push_back(std::make_tuple("%%", TokenType::OPERATOR_REMAINDER));
	inputs.push_back(std::make_tuple("<=", TokenType::OPERATOR_LESS_THAN_OR_EQUAL));
	inputs.push_back(std::make_tuple(">=", TokenType::OPERATOR_GREATER_THAN_OR_EQUAL));
	inputs.push_back(std::make_tuple("<<", TokenType::OPERATOR_LEFT_SHIFT));
	inputs.push_back(std::make_tuple(">>", TokenType::OPERATOR_RIGHT_SHIFT_ARITHMETIC));
	inputs.push_back(std::make_tuple(">>>", TokenType::OPERATOR_RIGHT_SHIFT_LOGICAL));
	inputs.push_back(std::make_tuple("&&", TokenType::OPERATOR_AND));
	inputs.push_back(std::make_tuple("||", TokenType::OPERATOR_OR));
	inputs.push_back(std::make_tuple("!=", TokenType::OPERATOR_NOT_EQUAL));
	inputs.push_back(std::make_tuple("+=", TokenType::OPERATOR_ASSIGN_ADD));
	inputs.push_back(std::make_tuple("&&=", TokenType::OPERATOR_ASSIGN_AND));
	inputs.push_back(std::make_tuple("&=", TokenType::OPERATOR_ASSIGN_BITWISE_AND));
	inputs.push_back(std::make_tuple("|=", TokenType::OPERATOR_ASSIGN_BITWISE_OR));
	inputs.push_back(std::make_tuple("~=", TokenType::OPERATOR_ASSIGN_BITWISE_XOR));
	inputs.push_back(std::make_tuple("/=", TokenType::OPERATOR_ASSIGN_DIV));
	inputs.push_back(std::make_tuple("<<=", TokenType::OPERATOR_ASSIGN_LEFT_SHIFT));
	inputs.push_back(std::make_tuple("%=", TokenType::OPERATOR_ASSIGN_MOD));
	inputs.push_back(std::make_tuple("*=", TokenType::OPERATOR_ASSIGN_MUL));
	inputs.push_back(std::make_tuple("||=", TokenType::OPERATOR_ASSIGN_OR));
	inputs.push_back(std::make_tuple("%%=", TokenType::OPERATOR_ASSIGN_REMAINDER));
	inputs.push_back(std::make_tuple(">>=", TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_ARITHMETIC));
	inputs.push_back(std::make_tuple(">>>=", TokenType::OPERATOR_ASSIGN_RIGHT_SHIFT_LOGICAL));
	inputs.push_back(std::make_tuple("-=", TokenType::OPERATOR_ASSIGN_SUB));
	inputs.push_back(std::make_tuple("|>", TokenType::OPERATOR_PIPE));
	inputs.push_back(std::make_tuple("..<", TokenType::OPERATOR_RANGE_EXCLUSIVE));
	inputs.push_back(std::make_tuple("..=", TokenType::OPERATOR_RANGE_INCLUSIVE));
	inputs.push_back(std::make_tuple("...", TokenType::SYM_ELLIPSIS));

	for (const auto& input : inputs) {
		output.clear();

		const auto& text = std::get<0>(input);

		std::istringstream input_stream(text);

		hemera::lexer::lex(input_stream, output, alloc);

		EXPECT_EQ(output.size(), 2)
			<< std::format("Incorrect number of tokens for {}", text);
		EXPECT_EQ(output[0].type, std::get<1>(input)) 
			<< std::format("Incorrect type for {}", text);
		EXPECT_EQ(output[0].line_number, 1)
			<< std::format("Incorrect line number for {}", text);
		EXPECT_EQ(output[0].column_number, 0)
			<< std::format("Incorrect column number for {}", text);
		EXPECT_EQ(output[0].value, nullptr)
			<< std::format("Incorrect string contents for {}", text);

		EXPECT_EQ(output[1].type, TokenType::END_OF_FILE)
			<< std::format("Incorrect type of EOF for {}", text);
		EXPECT_EQ(output[1].line_number, 1)
			<< std::format("Incorrect line number of EOF for {}", text);
		EXPECT_EQ(output[1].column_number, text.size())
			<< std::format("Incorrect column number of EOF for {}", text);
		EXPECT_EQ(output[1].value, nullptr)
			<< std::format("Incorrect string contents of EOF for {}", text);
	}
	
}

TEST(SingleComplexTokenTest, OptionsWithoutArgs)
{
	Allocator<> alloc;
	MyVector<Token> output;

	std::vector<std::tuple<std::string, TokenType>> inputs;

	inputs.push_back(std::make_tuple("@example", TokenType::ANNOTATION));
	inputs.push_back(std::make_tuple("example", TokenType::IDENTIFIER));
	inputs.push_back(std::make_tuple("'a'", TokenType::LITERAL_CHAR));
	inputs.push_back(std::make_tuple("\"foo bar\"", TokenType::LITERAL_STRING));
	inputs.push_back(std::make_tuple("$1", TokenType::PIPE_REORDER_IDENTIFIER));
	inputs.push_back(std::make_tuple("1234", TokenType::LITERAL_INTEGER));
	inputs.push_back(std::make_tuple("1_234", TokenType::LITERAL_INTEGER));
	inputs.push_back(std::make_tuple("1.", TokenType::LITERAL_FLOATING_POINT));
	inputs.push_back(std::make_tuple(".5", TokenType::LITERAL_FLOATING_POINT));
	inputs.push_back(std::make_tuple("0.", TokenType::LITERAL_FLOATING_POINT));
	inputs.push_back(std::make_tuple("1234.456", TokenType::LITERAL_FLOATING_POINT));
	inputs.push_back(std::make_tuple("1_234_567.456", TokenType::LITERAL_FLOATING_POINT));
	inputs.push_back(std::make_tuple("1e-5", TokenType::LITERAL_FLOATING_POINT));
	inputs.push_back(std::make_tuple("2E10", TokenType::LITERAL_FLOATING_POINT));

	for (const auto& input : inputs) {

		const std::string& text = std::get<0>(input);

		std::istringstream input_stream(text);

		hemera::lexer::lex(input_stream, output, alloc);

		EXPECT_EQ(output.size(), 2)
			<< std::format("Incorrect number of tokens for {}", text);
		EXPECT_EQ(output[0].type, std::get<1>(input))
			<< std::format("Incorrect type for {}", text);
		EXPECT_EQ(output[0].line_number, 1)
			<< std::format("Incorrect line number for {}", text);
		EXPECT_EQ(output[0].column_number, 0)
			<< std::format("Incorrect column number for {}", text);
		EXPECT_NE(output[0].value, nullptr) 
			<< std::format("Incorrect string contents for {}", text);
		EXPECT_EQ(strncmp(output[0].value->c_str(), text.c_str(),
			strlen(text.c_str())), 0
		) << std::format("Incorrect string contents for {}", text);

		EXPECT_EQ(output[1].type, TokenType::END_OF_FILE)
			<< std::format("Incorrect type of EOF for {}", text);
		EXPECT_EQ(output[1].line_number, 1)
			<< std::format("Incorrect line number of EOF for {}", text);
		EXPECT_EQ(output[1].column_number, text.size())
			<< std::format("Incorrect column number of EOF for {}", text);
		EXPECT_EQ(output[1].value, nullptr)
			<< std::format("Incorrect string contents of EOF for {}", text);

		alloc.delete_object(output[0].value);
		output.clear();
	}
}