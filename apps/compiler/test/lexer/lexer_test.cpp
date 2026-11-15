#include <cstdint>
#include <cctype>
#include <filesystem>
#include <format>
#include <fstream>
#include <optional>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>

#include "gtest/gtest.h"

#include "error/reporting.h"
#include "lexer/identifier_security.h"
#include "lexer/identifiers.h"
#include "lexer/lexer.h"
#include "lexer/token.h"
#include "parser/ast_types.h"
#include "util/utf8.h"
#include "../string_cache_guard.h"

using hemera::Allocator;
using hemera::MyVector;
using hemera::Token;
using hemera::TokenType;

TEST(LexerTests, SingleSimpleTokenTest)
{
	auto reporting = hemera::DisableReportingForBlock();
	StringCacheGuard string_cache;

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
	inputs.push_back(std::make_tuple("---", TokenType::SYM_UNINITIALIZED));

	inputs.push_back(std::make_tuple("alias", TokenType::IDENTIFIER));
	inputs.push_back(std::make_tuple("all", TokenType::IDENTIFIER));
	inputs.push_back(std::make_tuple("as", TokenType::IDENTIFIER));
	inputs.push_back(std::make_tuple("auto_cast", TokenType::KEYWORD_AUTO_CAST));
	inputs.push_back(std::make_tuple("bit_cast", TokenType::KEYWORD_BIT_CAST));
	inputs.push_back(std::make_tuple("break", TokenType::KEYWORD_BREAK));
	inputs.push_back(std::make_tuple("case", TokenType::KEYWORD_CASE));
	inputs.push_back(std::make_tuple("cast", TokenType::KEYWORD_CAST));
	inputs.push_back(std::make_tuple("continue", TokenType::KEYWORD_CONTINUE));
	inputs.push_back(std::make_tuple("defer", TokenType::KEYWORD_DEFER));
	inputs.push_back(std::make_tuple("distinct", TokenType::KEYWORD_DISTINCT));
	inputs.push_back(std::make_tuple("else", TokenType::KEYWORD_ELSE));
	inputs.push_back(std::make_tuple("enum", TokenType::KEYWORD_ENUM));
	inputs.push_back(std::make_tuple("false", TokenType::KEYWORD_FALSE));
	inputs.push_back(std::make_tuple("fn", TokenType::KEYWORD_FN));
	inputs.push_back(std::make_tuple("for", TokenType::KEYWORD_FOR));
	inputs.push_back(std::make_tuple("from", TokenType::IDENTIFIER));
	inputs.push_back(std::make_tuple("if", TokenType::KEYWORD_IF));
	inputs.push_back(std::make_tuple("import", TokenType::IDENTIFIER));
	inputs.push_back(std::make_tuple("in", TokenType::IDENTIFIER));
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
	inputs.push_back(std::make_tuple("package", TokenType::IDENTIFIER));
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
		// Words keep their text: identifiers, including the contextual keywords, and keywords, which
		// can still be names where only a name can go
		const bool is_word = std::isalpha(static_cast<unsigned char>(text[0])) != 0;
		if (is_word) {
			ASSERT_NE(output[0].value, nullptr) << std::format("No string contents for {}", text);
			EXPECT_EQ(std::string_view(*output[0].value), std::string_view(text)) << std::format("Incorrect string contents for {}", text);
		}
		else {
			EXPECT_EQ(output[0].value, nullptr)
				<< std::format("Incorrect string contents for {}", text);
		}

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

TEST(LexerTests, SingleComplexTokenTest)
{
	auto reporting = hemera::DisableReportingForBlock();
	StringCacheGuard string_cache;
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
	// Imaginary numbers, a complex number's or a quaternion's parts
	inputs.push_back(std::make_tuple("2i", TokenType::LITERAL_IMAGINARY));
	inputs.push_back(std::make_tuple("1.5j", TokenType::LITERAL_IMAGINARY));
	inputs.push_back(std::make_tuple("1e3k", TokenType::LITERAL_IMAGINARY));
	inputs.push_back(std::make_tuple("1_000i", TokenType::LITERAL_IMAGINARY));

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

		output.clear();
	}
}

/*
 * A line longer than a token's 16-bit column can count is an error (E2007), and cut short, so lexing
 * still ends. It used to start over at column 0 and never end.
 */
TEST(LexerTests, VeryLongLine)
{
	hemera::disable_reporting_printing();
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;
	Allocator<> alloc;
	MyVector<Token> output;

	std::istringstream input_stream("a\n" + std::string(70000, 'b') + "\nc");
	hemera::lexer::lex(input_stream, output, alloc, __FILE__);

	ASSERT_EQ(hemera::error_count(), 1);
	EXPECT_EQ(hemera::error_list()->at(0), hemera::ErrorCode::E2007);
	ASSERT_EQ(output.size(), 4);
	EXPECT_EQ(output[1].type, TokenType::IDENTIFIER);
	EXPECT_EQ(output[1].line_number, 2);
	EXPECT_EQ(output[2].type, TokenType::IDENTIFIER);
	EXPECT_EQ(output[2].line_number, 3);
	hemera::reset_reporting_storage();
}

// The errors lexing text reports, in order, each as "(line,column) code"
static std::vector<std::string> text_errors(const std::string& text) {
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;
	Allocator<> alloc;
	MyVector<Token> output;
	hemera::ReportScope scope;
	hemera::set_report_scope(&scope);
	std::istringstream input_stream(text);
	hemera::lexer::lex(input_stream, output, alloc, "text", true);
	hemera::set_report_scope(nullptr);
	hemera::reset_reporting_storage();
	std::vector<std::string> errors;
	std::istringstream lines(scope.output + scope.errors_output);
	for (std::string line; std::getline(lines, line);) {
		const size_t open = line.find('(');
		// The compiler's own codes, printed as hemera:E2008
		const size_t error = line.find("): error hemera:");
		if (open != std::string::npos && error != std::string::npos) {
			errors.push_back(line.substr(open, error + 1 - open) + " " + line.substr(error + 16, 5));
		}
	}
	return errors;
}

/*
 * Source is UTF-8: bytes that aren't are reported once a line, where they start (E2008), and a byte order mark at
 * the start is skipped
 */
TEST(LexerTests, InvalidUtf8)
{
	using Errors = std::vector<std::string>;
	EXPECT_EQ(text_errors("// caf\xC3\xA9 \xE6\x97\xA5\xE6\x9C\xAC \xF0\x9F\x98\x80\na :: \"\xD0\x96\""), Errors{});
	EXPECT_EQ(text_errors("\xEF\xBB\xBF" "a :: 1"), Errors{});
	// A stray continuation byte, a lead with none, an overlong '/', a surrogate, past U+10FFFF
	EXPECT_EQ(text_errors("// ab\x80"), (Errors{ "(1,5) E2008" }));
	EXPECT_EQ(text_errors("// \xC3x"), (Errors{ "(1,3) E2008" }));
	EXPECT_EQ(text_errors("// \xC0\xAF"), (Errors{ "(1,3) E2008" }));
	EXPECT_EQ(text_errors("// \xED\xA0\x80"), (Errors{ "(1,3) E2008" }));
	EXPECT_EQ(text_errors("// \xF4\x90\x80\x80"), (Errors{ "(1,3) E2008" }));
	// Once a line, on each line it happens on, inside a block comment too
	EXPECT_EQ(text_errors("/* \xFF\xFF\n\n \xFE */"), (Errors{ "(1,3) E2008", "(3,1) E2008" }));
}

// Bidirectional controls are an error wherever they are (E2009), and a string has them through \u{...}
TEST(LexerTests, BidirectionalControls)
{
	using Errors = std::vector<std::string>;
	// U+202E in a comment and U+2066 in a string, U+061C and U+200F
	EXPECT_EQ(text_errors("a :: 1 // \xE2\x80\xAE" "b"), (Errors{ "(1,10) E2009" }));
	EXPECT_EQ(text_errors("a :: \"x\xE2\x81\xA6\""), (Errors{ "(1,7) E2009" }));
	EXPECT_EQ(text_errors("// \xD8\x9C \xE2\x80\x8F"), (Errors{ "(1,3) E2009", "(1,6) E2009" }));
	EXPECT_EQ(text_errors("a :: \"\\u{202E}\""), Errors{});
}

TEST(LexerTests, UnicodeEscapes)
{
	using Errors = std::vector<std::string>;
	EXPECT_EQ(text_errors("a :: \"\\u{0}\\u{e9}\\u{10FFFF}\\u{00004A}\""), Errors{});
	EXPECT_EQ(text_errors("a :: \"\\u\""), (Errors{ "(1,7) E2010" }));
	EXPECT_EQ(text_errors("a :: \"\\u{}\""), (Errors{ "(1,7) E2010" }));
	EXPECT_EQ(text_errors("a :: \"\\u{12345678}\""), (Errors{ "(1,7) E2010" }));
	EXPECT_EQ(text_errors("a :: \"\\u{12g}\""), (Errors{ "(1,7) E2010" }));
	EXPECT_EQ(text_errors("a :: \"\\u{110000}\""), (Errors{ "(1,7) E2010" }));
	EXPECT_EQ(text_errors("a :: \"\\u{D800}\""), (Errors{ "(1,7) E2010" }));
	// A bad escape doesn't take the closing quote, so what follows still lexes
	EXPECT_EQ(text_errors("a :: \"\\u{41\"\nb :: 2"), (Errors{ "(1,7) E2010" }));

	StringCacheGuard string_cache;
	const Token literal(TokenType::LITERAL_STRING, 0, 1, hemera::intern(std::string("\"a\\u{E9}\\u{1F600}\\u{202e}\\n\"")));
	hemera::ast::Node node(hemera::ast::NodeType::LITERAL, literal);
	EXPECT_EQ(hemera::ast::string_value(&node), "a\xC3\xA9\xF0\x9F\x98\x80\xE2\x80\xAE\n");
}

// Each token's type and text, end of file left out
static std::vector<std::pair<TokenType, std::string>> tokens_of(const std::string& text) {
	auto reporting = hemera::DisableReportingForBlock();
	StringCacheGuard string_cache;
	Allocator<> alloc;
	MyVector<Token> output;
	std::istringstream input_stream(text);
	hemera::lexer::lex(input_stream, output, alloc, "text");
	std::vector<std::pair<TokenType, std::string>> tokens;
	for (const Token& token : output) {
		if (token.type != TokenType::END_OF_FILE) {
			tokens.emplace_back(token.type, token.value != nullptr ? std::string(*token.value) : std::string());
		}
	}
	return tokens;
}

/*
 * Names are UAX #31's default identifiers: a letter of any script first, then letters, digits, _ and combining marks
 * of any script, but not default ignorables
 */
TEST(LexerTests, UnicodeIdentifiers)
{
	using Tokens = std::vector<std::pair<TokenType, std::string>>;
	using Errors = std::vector<std::string>;
	const TokenType ID = TokenType::IDENTIFIER;
	/*
	 * Cyrillic, Japanese, Greek with an accent, q with a combining acute (which has no character of its own, so that's
	 * its NFKC), Arabic-Indic digits, Devanagari with its vowel signs
	 */
	for (const std::string name : { "\xD0\xB8\xD0\xBC\xD1\x8F", "\xE6\x97\xA5\xE6\x9C\xAC\xE8\xAA\x9E", "\xCE\xAC\xCE\xBB\xCF\x86\xCE\xB1",
		"q\xCC\x81t\xC3\xA9", "x\xD9\xA1\xD9\xA2", "\xE0\xA4\xA8\xE0\xA4\xBE\xE0\xA4\xAE", "\xC3\xA9_1" }) {
		EXPECT_EQ(tokens_of(name + " :: 1"), (Tokens{ { ID, name }, { TokenType::SYM_COLON, "" }, { TokenType::SYM_COLON, "" },
			{ TokenType::LITERAL_INTEGER, "1" } })) << name;
		EXPECT_EQ(text_errors(name + " :: 1"), Errors{}) << name;
		EXPECT_TRUE(hemera::lexer::is_identifier(name)) << name;
	}
	// Not a first character: an Arabic-Indic digit, a combining acute; each reported once, whole, where it starts
	EXPECT_EQ(text_errors("a \xD9\xA1"), (Errors{ "(1,2) E2006" }));
	EXPECT_EQ(text_errors("a \xCC\x81"), (Errors{ "(1,2) E2006" }));
	// Default ignorables end a name: a zero width joiner, a soft hyphen, a variation selector
	EXPECT_EQ(tokens_of("ab\xE2\x80\x8D" "c")[0], (std::pair<TokenType, std::string>{ ID, "ab" }));
	EXPECT_EQ(text_errors("ab\xE2\x80\x8D" "c"), (Errors{ "(1,2) E2006" }));
	EXPECT_EQ(text_errors("ab\xC2\xAD" "c"), (Errors{ "(1,2) E2006" }));
	EXPECT_EQ(text_errors("ab\xEF\xB8\x8F"), (Errors{ "(1,2) E2006" }));
	// Nor is an emoji anywhere in a name
	EXPECT_EQ(text_errors("\xF0\x9F\x98\x80 :: 1"), (Errors{ "(1,0) E2006" }));
	// A letter after an imaginary literal's i makes it a name instead, as an ASCII one does
	EXPECT_EQ(tokens_of("2i\xD0\xB6"), (Tokens{ { TokenType::LITERAL_INTEGER, "2" }, { ID, "i\xD0\xB6" } }));
	EXPECT_EQ(tokens_of("2i"), (Tokens{ { TokenType::LITERAL_IMAGINARY, "2i" } }));

	// What compiler.name takes as a name
	EXPECT_TRUE(hemera::lexer::is_identifier("a1_b"));
	EXPECT_FALSE(hemera::lexer::is_identifier(""));
	EXPECT_FALSE(hemera::lexer::is_identifier("_"));
	EXPECT_FALSE(hemera::lexer::is_identifier("_a"));
	EXPECT_FALSE(hemera::lexer::is_identifier("1a"));
	EXPECT_FALSE(hemera::lexer::is_identifier("if"));
	EXPECT_FALSE(hemera::lexer::is_identifier("a b"));
	EXPECT_FALSE(hemera::lexer::is_identifier("a\xE2\x80\x8D" "b"));
	EXPECT_FALSE(hemera::lexer::is_identifier("\xCC\x81" "a"));
	EXPECT_FALSE(hemera::lexer::is_identifier("a\xFF"));
}

/*
 * identifier_nfkc against Unicode's NormalizationTest.txt, the copy std/unicode's tests use: each line whose code points
 * can all be in a name, column 1 to 5's NFKC is column 4
 */
TEST(LexerTests, IdentifierNfkcMatchesUnicodesTests)
{
	const std::filesystem::path tests = std::filesystem::path(__FILE__).parent_path().parent_path().parent_path().parent_path()
		.parent_path() / "std" / "unicode" / "test" / "normalization_test.txt";
	std::ifstream file(tests, std::ios::binary);
	ASSERT_TRUE(file.is_open()) << tests.string();
	// A column's code points as UTF-8, or nothing if one of them can't be in a name
	auto column_text = [](std::string_view column) -> std::optional<std::string> {
		std::string text;
		std::istringstream points{ std::string(column) };
		for (std::string hex; points >> hex;) {
			const uint32_t code_point = static_cast<uint32_t>(std::stoul(hex, nullptr, 16));
			if (!hemera::lexer::is_identifier_continue(code_point)) {
				return std::nullopt;
			}
			hemera::utf8::encode(code_point, text);
		}
		return text;
	};
	size_t checked = 0;
	for (std::string line; std::getline(file, line);) {
		if (line.empty() || line[0] == '#' || line[0] == '@') {
			continue;
		}
		std::vector<std::string_view> columns;
		std::string_view rest(line);
		for (int i = 0; i < 5; ++i) {
			const size_t semicolon = rest.find(';');
			columns.push_back(rest.substr(0, semicolon));
			rest.remove_prefix(semicolon + 1);
		}
		std::optional<std::string> expected = column_text(columns[3]);
		if (!expected) {
			continue;
		}
		for (const std::string_view column : columns) {
			std::optional<std::string> source = column_text(column);
			if (source) {
				EXPECT_EQ(hemera::lexer::identifier_nfkc(*source), *expected) << line;
				checked += 1;
			}
		}
	}
	// Most of the file's lines are letters and marks a name can have
	EXPECT_GT(checked, 5000u);
}

// A name outside ASCII must be in NFKC already (E2011), which every ASCII name is
TEST(LexerTests, NamesInNfkc)
{
	using Errors = std::vector<std::string>;
	// é as e and a combining acute; the ligature ﬁ; a full-width Ａ; a Hangul syllable as its jamo; Å as the angstrom sign
	EXPECT_EQ(text_errors("cafe\xCC\x81 :: 1"), (Errors{ "(1,0) E2011" }));
	EXPECT_EQ(text_errors("x :: \xEF\xAC\x81le"), (Errors{ "(1,5) E2011" }));
	EXPECT_EQ(text_errors("\xEF\xBC\xA1 :: 1"), (Errors{ "(1,0) E2011" }));
	EXPECT_EQ(text_errors("\xE1\x84\x80\xE1\x85\xA1 :: 1"), (Errors{ "(1,0) E2011" }));
	// Already NFKC: é, 가, a Devanagari letter with its vowel sign
	EXPECT_EQ(text_errors("caf\xC3\xA9 :: \xEA\xB0\x80 + \xE0\xA4\x95\xE0\xA4\xBF"), Errors{});

	EXPECT_EQ(hemera::lexer::identifier_nfkc("cafe\xCC\x81"), "caf\xC3\xA9");
	EXPECT_EQ(hemera::lexer::identifier_nfkc("\xEF\xAC\x81le"), "file");
	EXPECT_EQ(hemera::lexer::identifier_nfkc("\xE1\x84\x80\xE1\x85\xA1\xE1\x86\xA8"), "\xEA\xB0\x81");
	EXPECT_FALSE(hemera::lexer::is_identifier("cafe\xCC\x81"));
	EXPECT_TRUE(hemera::lexer::is_identifier("caf\xC3\xA9"));
}

// UTS #39's skeletons, mixed scripts and identifier status, which the front end warns of names with
TEST(LexerTests, NameSecurity)
{
	using hemera::lexer::identifier_skeleton;
	using hemera::lexer::mixed_scripts;
	using hemera::lexer::uncommon_code_point;
	// Cyrillic сор and Latin cop; m and rn; Greek ο and Latin o; but not cop and cup
	EXPECT_EQ(identifier_skeleton("\xD1\x81\xD0\xBE\xD1\x80"), identifier_skeleton("cop"));
	EXPECT_EQ(identifier_skeleton("m"), identifier_skeleton("rn"));
	EXPECT_EQ(identifier_skeleton("x\xCE\xBF"), identifier_skeleton("xo"));
	EXPECT_NE(identifier_skeleton("cop"), identifier_skeleton("cup"));

	// Latin with Cyrillic, and Greek with Cyrillic; Latin with Han and kana, Han with Hangul, and digits and _ are fine
	EXPECT_EQ(mixed_scripts("total_\xD0\xB8\xD1\x82\xD0\xBE\xD0\xB3"), (std::vector<std::string_view>{ "Latin", "Cyrillic" }));
	EXPECT_EQ(mixed_scripts("\xCF\x80\xD0\xB8"), (std::vector<std::string_view>{ "Greek", "Cyrillic" }));
	EXPECT_TRUE(mixed_scripts("name_\xE6\x97\xA5\xE6\x9C\xAC\xE3\x81\xB2\xE3\x82\xAB").empty());
	EXPECT_TRUE(mixed_scripts("\xED\x95\x9C\xE6\xBC\xA2").empty());
	EXPECT_TRUE(mixed_scripts("\xD0\xB8\xD0\xBC\xD1\x8F_2").empty());
	EXPECT_TRUE(mixed_scripts("count").empty());

	// Runic isn't recommended for names; Cyrillic and ASCII are
	EXPECT_EQ(uncommon_code_point("a\xE1\x9A\xA0"), 0x16a0u);
	EXPECT_EQ(uncommon_code_point("\xD0\xB8\xD0\xBC\xD1\x8F_2"), 0u);
	EXPECT_EQ(hemera::lexer::script_name(0x16a0), "Runic");
}

/*
 * A file with CRLF line endings, as read in binary mode, lexes as the same file with LF: the same tokens, lines and
 * columns, and no errors, through comments, multiline strings and blank lines. A lone CR is still an error (E2002).
 */
TEST(LexerTests, CrlfLexesAsLf)
{
	const std::string lf = "// a comment\na :: 1 // trailing\n\n\\\\ multiline\n\\\\ string\nb :: \"text\"\n/* block\n   comment */ c :: 2\n";
	std::string crlf;
	for (const char c : lf) {
		crlf += c == '\n' ? std::string("\r\n") : std::string(1, c);
	}
	auto lexed = [](const std::string& text) {
		hemera::reset_reporting_storage();
		StringCacheGuard string_cache;
		Allocator<> alloc;
		MyVector<Token> output;
		std::istringstream input_stream(text);
		hemera::lexer::lex(input_stream, output, alloc, "text", true);
		std::vector<std::tuple<TokenType, uint32_t, uint16_t, std::string>> tokens;
		for (const Token& token : output) {
			tokens.emplace_back(token.type, token.line_number, token.column_number,
				token.value != nullptr ? std::string(*token.value) : std::string());
		}
		return tokens;
	};
	EXPECT_EQ(text_errors(crlf), std::vector<std::string>{});
	EXPECT_EQ(lexed(crlf), lexed(lf));
	EXPECT_EQ(text_errors("a :: 1\rb :: 2\n"), (std::vector<std::string>{ "(1,7) E2002" }));
}

TEST(LexerTests, ManyTokenTest)
{
	auto reporting = hemera::DisableReportingForBlock();
	StringCacheGuard string_cache;
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
	foo :: fn(x: int, y: u32) -> ptr[f32]? {
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
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_LBRACK, nullptr));
	expected_tokens.push_back(std::make_tuple(TokenType::IDENTIFIER, "f32"));
	expected_tokens.push_back(std::make_tuple(TokenType::SYM_RBRACK, nullptr));
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
		} else if (output[i].type < TokenType::KEYWORD_AUTO_CAST || output[i].type > TokenType::KEYWORD_WITH) {
			// Keywords keep their text, since they can still be names where only a name can go
			EXPECT_EQ(output[i].value, nullptr);
		}
		
	}
}

TEST(LexerTests, RangeLexingTest)
{
	auto reporting = hemera::DisableReportingForBlock();
	StringCacheGuard string_cache;

	Allocator<> alloc;
	MyVector<Token> output;

	const std::string& text = "1..<4";

	std::istringstream input_stream(text);

	hemera::lexer::lex(input_stream, output, alloc, __FILE__);

	EXPECT_EQ(output.size(), 4)
		<< std::format("Incorrect number of tokens for {}", text);
	EXPECT_EQ(output[0].type, TokenType::LITERAL_INTEGER)
		<< std::format("Incorrect type for {}", text);
	EXPECT_EQ(output[1].type, TokenType::OPERATOR_RANGE_EXCLUSIVE)
		<< std::format("Incorrect type for {}", text);
	EXPECT_EQ(output[2].type, TokenType::LITERAL_INTEGER)
		<< std::format("Incorrect type for {}", text);
	EXPECT_EQ(output[3].type, TokenType::END_OF_FILE)
		<< std::format("Incorrect type for {}", text);

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

TEST(LexerTests, InvalidTokenTest)
{
	auto reporting = hemera::DisableReportingForBlock();
	StringCacheGuard string_cache;
	Allocator<> alloc;
	MyVector<Token> output;

	std::vector<std::tuple<std::string, std::vector<TokenType>>> inputs;

	int invalid_chars[] = {
		0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0b, 0x0c,
		0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
		0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x7f
	};

	// A character outside ASCII that can't start a name, an arrow, is one invalid token, whole (UnicodeIdentifiers)
	inputs.push_back(std::make_tuple("\xE2\x86\x92",
		std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));
	inputs.push_back(std::make_tuple("'\n", 
		std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));
	inputs.push_back(std::make_tuple("\"\n", 
		std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));
	inputs.push_back(std::make_tuple("\\\\\r", 
		std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));
	for (int invalid : invalid_chars) {
		inputs.push_back(std::make_tuple(std::format("'{}'", static_cast<char>(invalid)),
			std::vector<TokenType>{ TokenType::INVALID, TokenType::INVALID, TokenType::END_OF_FILE }));
		inputs.push_back(std::make_tuple(std::format("\"{}\"", static_cast<char>(invalid)),
			std::vector<TokenType>{ TokenType::INVALID, TokenType::INVALID, TokenType::END_OF_FILE }));
		inputs.push_back(std::make_tuple(std::format("'\\{}'", static_cast<char>(invalid)),
			std::vector<TokenType>{ TokenType::INVALID, TokenType::INVALID, TokenType::END_OF_FILE }));
		inputs.push_back(std::make_tuple(std::format("\"\\{}\"", static_cast<char>(invalid)),
			std::vector<TokenType>{ TokenType::INVALID, TokenType::INVALID, TokenType::END_OF_FILE }));
		inputs.push_back(std::make_tuple(std::format("\\\\{}", static_cast<char>(invalid)),
			std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));
	}
	
	inputs.push_back(std::make_tuple("\\\n", std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));
	inputs.push_back(std::make_tuple("\\", std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));
	inputs.push_back(std::make_tuple("\r", std::vector<TokenType>{ TokenType::INVALID, TokenType::END_OF_FILE }));

	for (const auto& input : inputs) {
		output.clear();

		const auto& text = std::get<0>(input);

		std::istringstream input_stream(text);

		hemera::lexer::lex(input_stream, output, alloc, __FILE__);

		const std::vector<TokenType>& expected = std::get<1>(input);

		EXPECT_EQ(output.size(), expected.size())
			<< std::format("Incorrect number of tokens for {:}", sanitize(text));
		
		if (output.size() != expected.size()) {
			continue;
		}

		for (size_t i = 0; i < output.size(); ++i) {
			EXPECT_EQ(output[i].type, expected[i])
				<< std::format("Incorrect type for {:}", sanitize(text));
			EXPECT_EQ(output[i].value, nullptr)
				<< std::format("Incorrect string contents for {:}", sanitize(text));
		}
	}

}
