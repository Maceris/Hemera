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
			ARCHITECTURE,
			DEBUG_INFO,
			ENVIRONMENT,
			HELP,
			LIST,
			OBJECT_FORMAT,
			OS,
			OUTPUT,
			STOP_BEFORE_ASSEMBLY,
			STOP_BEFORE_LINK,
			SUBARCHITECTURE,
			VENDOR,
			VERSION,
		};

		struct OptionMapping {
			const char* name;
			const size_t name_length;
			const Option option;

			constexpr OptionMapping(const char* name, const Option option)
				: name{ name }
				, name_length{ constexpr_strlen(name) }
				, option{ option }
			{}
			OptionMapping(const OptionMapping&) = delete;
			OptionMapping& operator=(const OptionMapping&) = delete;
			OptionMapping& operator=(OptionMapping&&) = delete;
			constexpr ~OptionMapping() = default;
		};

		struct OptionDescription {
			const char* summary;
			const Option option;
			const bool has_args;
			const bool multiple_args;
			const char _padding[2] = { 0 };

			constexpr OptionDescription(const Option option,
				const char* summary,
				const bool has_args,
				const bool multiple_args = false)
				: summary{ summary }
				, option{ option }
				, has_args{ has_args }
				, multiple_args{ multiple_args }
			{}
			OptionDescription(const OptionDescription&) = delete;
			OptionDescription& operator=(const OptionDescription&) = delete;
			OptionDescription& operator=(OptionDescription&&) = delete;
			constexpr ~OptionDescription() = default;
		};

		static constexpr bool NO_ARGS = false;
		static constexpr bool HAS_ARGS = true;
		static constexpr bool MULTIPLE_ARGS = true;

		//NOTE(ches) these are in the order that we'll print them out in
		static constexpr OptionMapping OPTION_MAPPINGS[] = {
			{"-c", Option::STOP_BEFORE_LINK},
			{"--stop-before-link", Option::STOP_BEFORE_LINK},
			{"-S", Option::STOP_BEFORE_ASSEMBLY},
			{"--stop-before-assembly", Option::STOP_BEFORE_ASSEMBLY},
			{"-o", Option::OUTPUT},
			{"--output", Option::OUTPUT},
			{"--help", Option::HELP},
			{"--list", Option::LIST},
			{"--version", Option::VERSION},
			{"-d", Option::DEBUG_INFO},
			{"--debug", Option::DEBUG_INFO},
			{"--architecture", Option::ARCHITECTURE},
			{"--arch", Option::ARCHITECTURE},
			{"--subarchitecture", Option::SUBARCHITECTURE},
			{"--subarch", Option::SUBARCHITECTURE},
			{"--vendor", Option::VENDOR},
			{"--os", Option::OS},
			{"--environment", Option::ENVIRONMENT},
			{"--env", Option::ENVIRONMENT},
			{"--object-format", Option::OBJECT_FORMAT},
			{"--obj", Option::OBJECT_FORMAT},
		};

		//NOTE(ches) these are in the order that we'll print them out in
		static constexpr OptionDescription NAMED_OPTIONS[] = {
			{Option::STOP_BEFORE_LINK, "Compile or assemble sources, but do not link", NO_ARGS},
			{Option::STOP_BEFORE_ASSEMBLY, "Stop after compilation, do not assemble", NO_ARGS},
			{Option::OUTPUT, "Place output in the specified file", HAS_ARGS},
			{Option::HELP, "Print out a help message", NO_ARGS},
			{Option::LIST, "List supported options. Valid values are: architecture, subarchitecture, vendor, os, environment, object-format", HAS_ARGS, MULTIPLE_ARGS},
			{Option::VERSION, "Print version information", NO_ARGS},
			{Option::DEBUG_INFO, "Produce debug information", NO_ARGS},
			{Option::ARCHITECTURE, "Specify the target architecture", HAS_ARGS},
			{Option::SUBARCHITECTURE, "Specify the target subarchitecture", HAS_ARGS},
			{Option::VENDOR, "Specify the target vendor", HAS_ARGS},
			{Option::OS, "Specify the target OS", HAS_ARGS},
			{Option::ENVIRONMENT, "Specify the target environment", HAS_ARGS},
			{Option::OBJECT_FORMAT, "Specify the intermediary object format", HAS_ARGS},
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

		struct UnprocessedOptions {
			MyVector<Option> options;
			MyVector<OptionWithValue> options_with_values;
			MyVector<MyString> input;
		};
		
		bool parse_arguments(int argc, char* argv[], UnprocessedOptions& output,
			Allocator<> alloc);

		std::optional<const OptionDescription*> find_option(const char* option);
	}
	
}
