#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "memory/allocator.h"

namespace hemera {

	namespace arg_parse {

		constexpr size_t constexpr_strlen(const char* str) {
			size_t length = 0;
			while (str[length] != '\0') {
				++length;
			}
			return length;
		}

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
			const size_t name_length;
			const Option option;
			const bool has_args;
			const char _padding[3] = { 0 };

			constexpr OptionDescription(const char* name, const char* summary,
				const Option option, const bool has_args)
				: name{ name }
				, summary{ summary }
				, name_length{ constexpr_strlen(name) }
				, option{ option }
				, has_args(has_args)
			{}
			OptionDescription(const OptionDescription&) = delete;
			OptionDescription& operator=(const OptionDescription&) = delete;
			OptionDescription& operator=(OptionDescription&&) = delete;
		};

		static constexpr bool NO_ARGS = false;
		static constexpr bool HAS_ARGS = true;

		static constexpr OptionDescription NAMED_OPTIONS[] = {
			{"-c", "Compile or assemble sources, but do not link", Option::STOP_BEFORE_LINK, NO_ARGS},
			{"-S", "Stop after compilation, do not assemble", Option::STOP_BEFORE_ASSEMBLY, NO_ARGS},
			{"-o", "Place output in the specified file", Option::OUTPUT, HAS_ARGS},
			{"--help", "Print out a help message", Option::HELP, NO_ARGS},
			{"--version", "Print version information", Option::VERSION, NO_ARGS},
			{"-d", "Produce debug information", Option::DEBUG_INFO, NO_ARGS},
		};

		struct OptionWithValue {
			Option option;
			const char padding[4] = { 0 };
			MyVector<MyString> values;

			OptionWithValue() = default;
			OptionWithValue(const OptionWithValue&) = delete;
			OptionWithValue(OptionWithValue&&) = default;
			OptionWithValue& operator=(const OptionWithValue&) = delete;
			OptionWithValue& operator=(OptionWithValue&&) = delete;
		};

		struct Options {
			MyVector<Option> options;
			MyVector<OptionWithValue> options_with_values;
			MyVector<MyString> input;
		};
		
		bool parse_arguments(int argc, char* argv[], Options& output,
			Allocator<> alloc);

		std::optional<const OptionDescription*> find_option(const char* option);
	}
	
}