#pragma once

#include <string>
#include <vector>

#include "memory/allocator.h"

namespace hemera {

	namespace arg_parse {
		enum Option {
			DEBUG_INFO,
			HELP,
			OUTPUT,
			STOP_BEFORE_ASSEMBLY,
			STOP_BEFORE_LINK,
			VERSION,
		};

		struct OptionDescription {
			const char* name;
			const char* summary;
			Option option;
			char _padding[4] = { 0 };
		};

		static constexpr bool NO_ARGS = false;
		static constexpr bool HAS_ARGS = true;

		static constexpr OptionDescription NAMED_OPTIONS[] = {
			{"-c", "Compile or assemble sources, but do not link", Option::STOP_BEFORE_LINK},
			{"-S", "Stop after compilation, do not assemble", Option::STOP_BEFORE_ASSEMBLY},
			{"-o", "Place output in the specified file", Option::OUTPUT},
			{"--help", "Print out a help message", Option::HELP},
			{"--version", "Print version information", Option::VERSION},
			{"-d", "Produce debug information", Option::DEBUG_INFO},
		};

		struct OptionWithValue {
			MyString option;
			MyVector<MyString> values;
		};

		struct Options {
			MyVector<MyString> options;
			MyVector<OptionWithValue> options_with_values;
			MyString output;
			MyVector<MyString> input;
		};
		
		void parse_arguments(int argc, char* argv[], Options& output);
	}
	
}