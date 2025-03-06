#pragma once

#include "memory/allocator.h"

namespace hemera {
	namespace options {
		struct OptionDescription {
			const char* name;
			const char* summary;
			bool has_arguments;
			char _padding[7] = { 0 };
		};

		static constexpr bool NO_ARGS = false;
		static constexpr bool HAS_ARGS = true;

		static constexpr OptionDescription NAMED_OPTIONS[] = {
			{"-c", "Compile or assemble sources, but do not link", NO_ARGS},
			{"-S", "Stop after compilation, do not assemble", NO_ARGS},
			{"-o", "Place output in the spcified file", HAS_ARGS},
			{"--help", "Print out a help message", NO_ARGS},
			{"--version", "Print version information", NO_ARGS},
			{"-d", "Produce debug information", NO_ARGS},
		};

		struct OptionWithValue {
			MyString option;
			MyVector<MyString> values;
		};

		struct Options {
			MyVector<MyString> flags;
			MyVector<OptionWithValue> options_with_values;
			MyString output;
			MyVector<MyString> input;
		};

	}
}