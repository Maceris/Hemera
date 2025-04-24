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

	inputs.push_back(std::make_tuple("alias", TokenType::KEYWORD_ALIAS));
	inputs.push_back(std::make_tuple("all", TokenType::KEYWORD_ALL));
	inputs.push_back(std::make_tuple("as", TokenType::KEYWORD_AS));
	inputs.push_back(std::make_tuple("break", TokenType::KEYWORD_BREAK));
	inputs.push_back(std::make_tuple("case", TokenType::KEYWORD_CASE));
	inputs.push_back(std::make_tuple("context", TokenType::KEYWORD_CONTEXT));
	inputs.push_back(std::make_tuple("continue", TokenType::KEYWORD_CONTINUE));
	inputs.push_back(std::make_tuple("defer", TokenType::KEYWORD_DEFER));
	inputs.push_back(std::make_tuple("distinct", TokenType::KEYWORD_DISTINCT));
	inputs.push_back(std::make_tuple("do", TokenType::KEYWORD_DO));
	inputs.push_back(std::make_tuple("else", TokenType::KEYWORD_ELSE));
	inputs.push_back(std::make_tuple("enum", TokenType::KEYWORD_ENUM));
	inputs.push_back(std::make_tuple("false", TokenType::KEYWORD_FALSE));
	inputs.push_back(std::make_tuple("fn", TokenType::KEYWORD_FN));
	inputs.push_back(std::make_tuple("for", TokenType::KEYWORD_FOR));
	inputs.push_back(std::make_tuple("if", TokenType::KEYWORD_IF));
	inputs.push_back(std::make_tuple("import", TokenType::KEYWORD_IMPORT));
	inputs.push_back(std::make_tuple("in", TokenType::KEYWORD_IN));
	inputs.push_back(std::make_tuple("is_none", TokenType::KEYWORD_IS_NONE));
	inputs.push_back(std::make_tuple("is_some", TokenType::KEYWORD_IS_SOME));
	inputs.push_back(std::make_tuple("loop", TokenType::KEYWORD_LOOP));
	inputs.push_back(std::make_tuple("match", TokenType::KEYWORD_MATCH));
	inputs.push_back(std::make_tuple("mut", TokenType::KEYWORD_MUT));
	inputs.push_back(std::make_tuple("null", TokenType::KEYWORD_NULL));
	inputs.push_back(std::make_tuple("or_break", TokenType::KEYWORD_OR_BREAK));
	inputs.push_back(std::make_tuple("or_continue", TokenType::KEYWORD_OR_CONTINUE));
	inputs.push_back(std::make_tuple("or_else", TokenType::KEYWORD_OR_ELSE));
	inputs.push_back(std::make_tuple("or_return", TokenType::KEYWORD_OR_RETURN));
	inputs.push_back(std::make_tuple("package", TokenType::KEYWORD_PACKAGE));
	inputs.push_back(std::make_tuple("return", TokenType::KEYWORD_RETURN));
	inputs.push_back(std::make_tuple("struct", TokenType::KEYWORD_STRUCT));
	inputs.push_back(std::make_tuple("switch", TokenType::KEYWORD_SWITCH));
	inputs.push_back(std::make_tuple("true", TokenType::KEYWORD_TRUE));
	inputs.push_back(std::make_tuple("union", TokenType::KEYWORD_UNION));
	inputs.push_back(std::make_tuple("using", TokenType::KEYWORD_USING));
	inputs.push_back(std::make_tuple("void", TokenType::KEYWORD_VOID));
	inputs.push_back(std::make_tuple("while", TokenType::KEYWORD_WHILE));
	inputs.push_back(std::make_tuple("with", TokenType::KEYWORD_WITH));

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
