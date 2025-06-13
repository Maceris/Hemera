#include <cstdint>
#include <format>
#include <tuple>
#include <vector>

#include "gtest/gtest.h"

#include "lexer/lexer.h"
#include "lexer/token.h"
#include "error/reporting.h"

using hemera::Allocator;
using hemera::MyVector;
using hemera::Token;
using hemera::TokenType;

TEST(SingleSimpleTokenTest, OptionsWithoutArgs)
{
	auto reporting = hemera::DisableReportingForBlock();

	Allocator<> alloc;
	MyVector<Token> output;

	std::vector<std::tuple<std::string, TokenType>> inputs;

	inputs.push_back(std::make_tuple("+", TokenType::OPERATOR_PLUS));
	inputs.push_back(std::make_tuple("-", TokenType::OPERATOR_MINUS));
	inputs.push_back(std::make_tuple("*", TokenType::OPERATOR_MULTIPLY));
	inputs.push_back(std::make_tuple("/", TokenType::OPERATOR_DIVIDE));
	inputs.push_back(std::make_tuple("%", TokenType::OPERATOR_MODULUS));
	inputs.push_back(std::make_tuple("&", TokenType::SYM_AMPERSAND));
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
	inputs.push_back(std::make_tuple("..", TokenType::OPERATOR_RANGE_ARRAY));
	inputs.push_back(std::make_tuple("..<", TokenType::OPERATOR_RANGE_EXCLUSIVE));
	inputs.push_back(std::make_tuple("..=", TokenType::OPERATOR_RANGE_INCLUSIVE));
	inputs.push_back(std::make_tuple("...", TokenType::SYM_ELLIPSIS));

	inputs.push_back(std::make_tuple("alias", TokenType::KEYWORD_ALIAS));
	inputs.push_back(std::make_tuple("all", TokenType::KEYWORD_ALL));
	inputs.push_back(std::make_tuple("as", TokenType::KEYWORD_AS));
	inputs.push_back(std::make_tuple("auto_cast", TokenType::KEYWORD_AUTO_CAST));
	inputs.push_back(std::make_tuple("bit_cast", TokenType::KEYWORD_BIT_CAST));
	inputs.push_back(std::make_tuple("break", TokenType::KEYWORD_BREAK));
	inputs.push_back(std::make_tuple("case", TokenType::KEYWORD_CASE));
	inputs.push_back(std::make_tuple("cast", TokenType::KEYWORD_CAST));
	inputs.push_back(std::make_tuple("context", TokenType::KEYWORD_CONTEXT));
	inputs.push_back(std::make_tuple("continue", TokenType::KEYWORD_CONTINUE));
	inputs.push_back(std::make_tuple("defer", TokenType::KEYWORD_DEFER));
	inputs.push_back(std::make_tuple("distinct", TokenType::KEYWORD_DISTINCT));
	inputs.push_back(std::make_tuple("else", TokenType::KEYWORD_ELSE));
	inputs.push_back(std::make_tuple("enum", TokenType::KEYWORD_ENUM));
	inputs.push_back(std::make_tuple("false", TokenType::KEYWORD_FALSE));
	inputs.push_back(std::make_tuple("fn", TokenType::KEYWORD_FN));
	inputs.push_back(std::make_tuple("for", TokenType::KEYWORD_FOR));
	inputs.push_back(std::make_tuple("from", TokenType::KEYWORD_FROM));
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
	inputs.push_back(std::make_tuple("push_context", TokenType::KEYWORD_PUSH_CONTEXT));
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

		hemera::lexer::lex(input_stream, output, alloc, __FILE__);

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
	auto reporting = hemera::DisableReportingForBlock();
	Allocator<> alloc;
	MyVector<Token> output;

	std::vector<std::tuple<std::string, TokenType>> inputs;

	inputs.push_back(std::make_tuple("@example", TokenType::ANNOTATION));
	inputs.push_back(std::make_tuple("#if", TokenType::DIRECTIVE));
	inputs.push_back(std::make_tuple("#at_least_once", TokenType::DIRECTIVE));
	inputs.push_back(std::make_tuple("example", TokenType::IDENTIFIER));
	inputs.push_back(std::make_tuple("'a'", TokenType::LITERAL_CHAR));
	inputs.push_back(std::make_tuple("\"foo bar\"", TokenType::LITERAL_STRING));
	inputs.push_back(std::make_tuple("$1", TokenType::PIPE_REORDER_IDENTIFIER));
	inputs.push_back(std::make_tuple("1234", TokenType::LITERAL_INTEGER));
	inputs.push_back(std::make_tuple("0xa", TokenType::LITERAL_INTEGER));
	inputs.push_back(std::make_tuple("0xfedc_ba09_8765_4321", TokenType::LITERAL_INTEGER));
	inputs.push_back(std::make_tuple("0xFEDC_BA09_8765_4321", TokenType::LITERAL_INTEGER));
	inputs.push_back(std::make_tuple("0b1", TokenType::LITERAL_INTEGER));
	inputs.push_back(std::make_tuple("0b0101_0001", TokenType::LITERAL_INTEGER));
	inputs.push_back(std::make_tuple("0o7", TokenType::LITERAL_INTEGER));
	inputs.push_back(std::make_tuple("0o1234_5607", TokenType::LITERAL_INTEGER));
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

		hemera::lexer::lex(input_stream, output, alloc, __FILE__);

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

TEST(ManyTokenTest, OptionsWithoutArgs)
{
	auto reporting = hemera::DisableReportingForBlock();
	Allocator<> alloc;
	MyVector<Token> output;

	const char* code = R"CONTENTS(
	/*
	 * This is a nested comment
	 * /* example
	 *  * of a comment
	 *  */
     * isn't that neat?
     */
	foo :: fn(x: int, y: u32) -> ptr<f32>? {
		bar : f32 = 4.3
		// This is a comment
		if bar <= 3.0 && bar > 0.1 {
			return null
		}
		return &bar
	}
	)CONTENTS";

	std::vector<std::tuple<TokenType, const char*>> expected_tokens;
	expected_tokens.push_back(std::make_tuple(TokenType::COMMENT_BLOCK, 
		R"CONTENTS(/*
	 * This is a nested comment
	 * /* example
	 *  * of a comment
	 *  */
     * isn't that neat?
     */)CONTENTS"));
	expected_tokens.push_back(std::make_tuple(TokenType::IDENTIFIER, "foo"));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_COLON, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_COLON, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::KEYWORD_FN, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_LPAREN, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::IDENTIFIER, "x"));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_COLON, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::IDENTIFIER, "int"));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_COMMA, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::IDENTIFIER, "y"));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_COLON, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::IDENTIFIER, "u32"));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_RPAREN, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_ARROW_SINGLE, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::IDENTIFIER, "ptr"));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_LT, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::IDENTIFIER, "f32"));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_GT, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_QUESTION, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_LBRACE, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::IDENTIFIER, "bar"));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_COLON, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::IDENTIFIER, "f32"));
	expected_tokens.push_back(std::make_tuple(TokenType::OPERATOR_ASSIGN, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::LITERAL_FLOATING_POINT, "4.3"));
	expected_tokens.push_back(std::make_tuple(TokenType::COMMENT_LINE, "// This is a comment"));
	expected_tokens.push_back(std::make_tuple(TokenType::KEYWORD_IF, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::IDENTIFIER, "bar"));
	expected_tokens.push_back(std::make_tuple(TokenType::OPERATOR_LESS_THAN_OR_EQUAL, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::LITERAL_FLOATING_POINT, "3.0"));
	expected_tokens.push_back(std::make_tuple(TokenType::OPERATOR_AND, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::IDENTIFIER, "bar"));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_GT, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::LITERAL_FLOATING_POINT, "0.1"));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_LBRACE, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::KEYWORD_RETURN, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::KEYWORD_NULL, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_RBRACE, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::KEYWORD_RETURN, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_AMPERSAND, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::IDENTIFIER, "bar"));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_RBRACE, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::END_OF_FILE, nullptr));

	std::istringstream input_stream(code);

	hemera::lexer::lex(input_stream, output, alloc, __FILE__, true);

	ASSERT_EQ(output.size(), expected_tokens.size());

	for (size_t i = 0; i < output.size(); ++i) {
		ASSERT_EQ(output[i].type, std::get<0>(expected_tokens[i]));

		const char* expected = std::get<1>(expected_tokens[i]);

		if (expected) {
			ASSERT_EQ(strncmp(output[i].value->c_str(), expected,
				strlen(expected)), 0)
				<< std::format("Failed to find string '{}' in '{}'", expected, 
					output[i].value->c_str());
		} else {
			EXPECT_EQ(output[i].value, nullptr);
		}

		if (output[i].value) {
			delete output[i].value;
			output[i].value = nullptr;
		}
	}

}

static std::string sanitize(const std::string& input) {
	std::string output;
	for (char c : input) {
		if (c >= 32 && c <= 126) {
			output += c;
		}
		else {
			output += std::format("{:#0x}", c);
		}
	}
	return output;
}

TEST(InvalidTokenTest, OptionsWithoutArgs)
{
	auto reporting = hemera::DisableReportingForBlock();
	Allocator<> alloc;
	MyVector<Token> output;

	std::vector<std::tuple<std::string, std::vector<TokenType>>> inputs;

	int invalid_chars[] = {
		0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0b, 0x0c,
		0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
		0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x7f
	};

	inputs.push_back(std::make_tuple("私", 
		std::vector<TokenType>{ TokenType::INVALID, TokenType::INVALID, TokenType::INVALID, TokenType::END_OF_FILE }));
	inputs.push_back(std::make_tuple("'\n", 
		std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));
	inputs.push_back(std::make_tuple("\"\n", 
		std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));
	inputs.push_back(std::make_tuple("\\\\\r", 
		std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));
	for (int invalid : invalid_chars) {
		inputs.push_back(std::make_tuple(std::format("'{}'", (char)invalid),
			std::vector<TokenType>{ TokenType::INVALID, TokenType::INVALID, TokenType::END_OF_FILE }));
		inputs.push_back(std::make_tuple(std::format("\"{}\"", (char)invalid),
			std::vector<TokenType>{ TokenType::INVALID, TokenType::INVALID, TokenType::END_OF_FILE }));
		inputs.push_back(std::make_tuple(std::format("'\\{}'", (char)invalid),
			std::vector<TokenType>{ TokenType::INVALID, TokenType::INVALID, TokenType::END_OF_FILE }));
		inputs.push_back(std::make_tuple(std::format("\"\\{}\"", (char)invalid),
			std::vector<TokenType>{ TokenType::INVALID, TokenType::INVALID, TokenType::END_OF_FILE }));
		inputs.push_back(std::make_tuple(std::format("\\\\{}", (char)invalid),
			std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));
	}
	
	inputs.push_back(std::make_tuple("\\\n", std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));
	inputs.push_back(std::make_tuple("\\", std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));
	inputs.push_back(std::make_tuple("\r", std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));

	int entry = 0;
	for (const auto& input : inputs) {
		output.clear();

		const auto& text = std::get<0>(input);

		std::istringstream input_stream(text);

		hemera::lexer::lex(input_stream, output, alloc, __FILE__);

		const std::vector<TokenType>& expected = std::get<1>(input);

		EXPECT_EQ(output.size(), expected.size())
			<< std::format("Incorrect number of tokens for {:}", sanitize(text));
		
		if (output.size() != expected.size()) {
			entry++;
			continue;
		}

		for (size_t i = 0; i < output.size(); ++i) {
			EXPECT_EQ(output[i].type, expected[i])
				<< std::format("Incorrect type for {:}", sanitize(text));
			EXPECT_EQ(output[i].value, nullptr)
				<< std::format("Incorrect string contents for {:}", sanitize(text));
		}
		entry++;
	}

}