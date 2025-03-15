#include <format>

#include "gtest/gtest.h"

#include "cmd_line/arg_parsing.h"

using hemera::arg_parse::Option;
using hemera::arg_parse::Options;
using hemera::Allocator;

TEST(ArgParsingTest, OptionsWithoutArgs)
{
	Allocator<> alloc;
	
	char application[] = "hemera.exe";
	char debug_info[] = "-d";
	char help[] = "--help";
	char stop_before_assembly[] = "-S";
	char stop_before_link[] = "-c";
	char version[] = "--version";

	std::vector<std::pair<char*, Option>> options;
	options.push_back(std::make_pair(debug_info, Option::DEBUG_INFO));
	options.push_back(std::make_pair(help, Option::HELP));
	options.push_back(std::make_pair(stop_before_assembly, Option::STOP_BEFORE_ASSEMBLY));
	options.push_back(std::make_pair(stop_before_link, Option::STOP_BEFORE_LINK));
	options.push_back(std::make_pair(version, Option::VERSION));

	char* arguments[] = { application, nullptr };
	Options output;

	for (const auto& input : options) {
		arguments[1] = input.first;
		output.options.clear();

		bool result = hemera::arg_parse::parse_arguments(2, arguments, output, alloc);

		EXPECT_TRUE(result);
		EXPECT_EQ(output.options.size(), 1);
		EXPECT_EQ(output.options[0], input.second);
		EXPECT_EQ(output.options_with_values.size(), 0);
		EXPECT_EQ(output.input.size(), 0);
	}
	
}

TEST(ArgParsingTest, OutputArg)
{
	Allocator<> alloc;

	char application[] = "hemera.exe";
	const char* value = "example.exe";
	std::string output_string = std::format("-o={}", value);
	char* output_chars = output_string.data();

	char* arguments[] = { application, output_chars };
	Options output;

	bool result = hemera::arg_parse::parse_arguments(2, arguments, output, alloc);

	EXPECT_TRUE(result);
	EXPECT_EQ(output.options.size(), 0);
	EXPECT_EQ(output.options_with_values.size(), 1);
	EXPECT_EQ(output.options_with_values[0].option, Option::OUTPUT);
	EXPECT_EQ(strncmp(output.options_with_values[0].values[0].c_str(), value, strlen(value)), 0);
	EXPECT_EQ(output.input.size(), 0);
}

TEST(ArgParsingTest, ErrorStartingWithEquals)
{
	Allocator<> alloc;

	char application[] = "hemera.exe";
	char invalid[] = "=123";

	char* arguments[] = { application, invalid };
	Options output;

	bool result = hemera::arg_parse::parse_arguments(2, arguments, output, alloc);

	EXPECT_FALSE(result);
}

TEST(ArgParsingTest, ErrorMissingArg)
{
	Allocator<> alloc;

	char application[] = "hemera.exe";
	char invalid[] = "-o";

	char* arguments[] = { application, invalid };
	Options output;

	bool result = hemera::arg_parse::parse_arguments(2, arguments, output, alloc);

	EXPECT_FALSE(result);
}

TEST(ArgParsingTest, ErrorExtraArg)
{
	Allocator<> alloc;

	char application[] = "hemera.exe";
	char invalid[] = "-c=a,b,c";

	char* arguments[] = { application, invalid };
	Options output;

	bool result = hemera::arg_parse::parse_arguments(2, arguments, output, alloc);

	EXPECT_FALSE(result);
}

TEST(ArgParsingTest, ErrorFlagAfterInput)
{
	Allocator<> alloc;

	char application[] = "hemera.exe";
	char input[] = "foo.hsc";
	char flag[] = "-d";

	char* arguments[] = { application, input, flag };
	Options output;

	bool result = hemera::arg_parse::parse_arguments(3, arguments, output, alloc);

	EXPECT_FALSE(result);
}

TEST(ArgParsingTest, ErrorFlagWithArgsAfterInput)
{
	Allocator<> alloc;

	char application[] = "hemera.exe";
	char input[] = "foo.hsc";
	char flag[] = "-o=test.exe";

	char* arguments[] = { application, input, flag };
	Options output;

	bool result = hemera::arg_parse::parse_arguments(3, arguments, output, alloc);

	EXPECT_FALSE(result);
}

TEST(ArgParsingTest, ErrorUnknownFlag)
{
	Allocator<> alloc;

	char application[] = "hemera.exe";
	char invalid[] = "-this-does-not-exist";

	char* arguments[] = { application, invalid };
	Options output;

	bool result = hemera::arg_parse::parse_arguments(2, arguments, output, alloc);

	EXPECT_FALSE(result);
}
