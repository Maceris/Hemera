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
			CODE_MODEL,
			CPU,
			CPU_FEATURES,
			DEBUG_INFO,
			ENTRY,
			ENVIRONMENT,
			HELP,
			INSTALL_PATH,
			LINKER_SCRIPT,
			SYSROOT,
			LIST,
			ADDRESS_ZERO_IS_MEMORY,
			ALLOW_RUN,
			NO_RED_ZONE,
			NO_STARTUP_CODE,
			O0,
			O1,
			O2,
			O3,
			OBJECT_FORMAT,
			OS,
			OUTPUT,
			PACKAGE_PATH,
			RELOCATION_MODEL,
			SETTING,
			STACK_CHECK,
			STOP_BEFORE_ASSEMBLY,
			STOP_BEFORE_LOWERING,
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
			{"-s", Option::STOP_BEFORE_LOWERING},
			{"--stop-before-lowering", Option::STOP_BEFORE_LOWERING},
			{"-S", Option::STOP_BEFORE_ASSEMBLY},
			{"--stop-before-assembly", Option::STOP_BEFORE_ASSEMBLY},
			{"-c", Option::STOP_BEFORE_LINK},
			{"--stop-before-link", Option::STOP_BEFORE_LINK},
			{"-o", Option::OUTPUT},
			{"--output", Option::OUTPUT},
			{"-O0", Option::O0},
			{"-O1", Option::O1},
			{"-O2", Option::O2},
			{"-O3", Option::O3},
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
			{"-mcpu", Option::CPU},
			{"--cpu", Option::CPU},
			{"--cpu-features", Option::CPU_FEATURES},
			{"--object-format", Option::OBJECT_FORMAT},
			{"--obj", Option::OBJECT_FORMAT},
			{"--code-model", Option::CODE_MODEL},
			{"--relocation-model", Option::RELOCATION_MODEL},
			{"--no-red-zone", Option::NO_RED_ZONE},
			{"--address-zero-is-memory", Option::ADDRESS_ZERO_IS_MEMORY},
			{"--entry", Option::ENTRY},
			{"--no-startup-code", Option::NO_STARTUP_CODE},
			{"--linker-script", Option::LINKER_SCRIPT},
			{"--sysroot", Option::SYSROOT},
			{"--stack-check", Option::STACK_CHECK},
			{"--install-path", Option::INSTALL_PATH},
			{"--package", Option::PACKAGE_PATH},
			{"--allow-run", Option::ALLOW_RUN},
			{"--setting", Option::SETTING},
		};

		//NOTE(ches) these are in the order that we'll print them out in
		static constexpr OptionDescription NAMED_OPTIONS[] = {
			{Option::STOP_BEFORE_LOWERING, "Stop after compiling, do not lower MLIR to LLVM IR", NO_ARGS},
			{Option::STOP_BEFORE_ASSEMBLY, "Stop after lowering to LLVM IR, do not assemble", NO_ARGS},
			{Option::STOP_BEFORE_LINK, "Compile or assemble sources, but do not link", NO_ARGS},
			{Option::OUTPUT, "Place output in the specified file", HAS_ARGS},
			{Option::HELP, "Print out a help message", NO_ARGS},
			{Option::LIST, "List supported options. Valid values are: architecture, subarchitecture, vendor, os, environment, object-format", HAS_ARGS, MULTIPLE_ARGS},
			{Option::VERSION, "Print version information", NO_ARGS},
			{Option::O0, "Disable as many optimizations as possible", NO_ARGS},
			{Option::O1, "Optimize quickly without destroying debuggability", NO_ARGS},
			{Option::O2, "Optimize for fast execution as much as possible without slowdown, the default", NO_ARGS},
			{Option::O3, "Optimize for fast execution as much as possible", NO_ARGS},
			{Option::DEBUG_INFO, "Produce debug information", NO_ARGS},
			{Option::ARCHITECTURE, "Specify the target architecture", HAS_ARGS},
			{Option::SUBARCHITECTURE, "Specify the target subarchitecture", HAS_ARGS},
			{Option::VENDOR, "Specify the target vendor", HAS_ARGS},
			{Option::OS, "Specify the target OS", HAS_ARGS},
			{Option::ENVIRONMENT, "Specify the target environment", HAS_ARGS},
			{Option::CPU, "The CPU to target, defaults to 'generic'", HAS_ARGS},
			{Option::CPU_FEATURES, "The CPU features to target, defaults to blank", HAS_ARGS},
			{Option::OBJECT_FORMAT, "Specify the intermediary object format, which follows the OS by default", HAS_ARGS},
			{Option::CODE_MODEL, "How far apart code and data may be: default, small, kernel, medium or large", HAS_ARGS},
			{Option::RELOCATION_MODEL, "Absolute or position-independent addresses: static or pic, the default", HAS_ARGS},
			{Option::NO_RED_ZONE, "Don't use the area below the stack pointer, for kernel code", NO_ARGS},
			{Option::ADDRESS_ZERO_IS_MEMORY, "Address 0 is memory on this target, so accesses to it through a rawptr are kept", NO_ARGS},
			{Option::ENTRY, "The function the program starts at, defaults to main", HAS_ARGS},
			{Option::NO_STARTUP_CODE, "Leave out the startup code, for freestanding programs whose entry sets up a carrier and context itself", NO_ARGS},
			{Option::LINKER_SCRIPT, "Linker script that places sections, for outputs loaded at fixed addresses", HAS_ARGS},
			{Option::SYSROOT, "Folder with the target's shared libraries, for a Linux program that links C", HAS_ARGS},
			{Option::STACK_CHECK, "What a function does without room on the stack: off, the default, or trap, which needs a carrier block", HAS_ARGS},
			{Option::INSTALL_PATH, "Folder containing the standard libraries", HAS_ARGS},
			{Option::PACKAGE_PATH, "Paths to builtin pacakge(s), written as \"package:path\"", HAS_ARGS, MULTIPLE_ARGS},
			{Option::SETTING, "Settings compile-time code reads with compiler.target_setting, written as \"name=value\"", HAS_ARGS, MULTIPLE_ARGS},
			{Option::ALLOW_RUN, "Let the build package's compile-time code run programs and write outside the output folder", NO_ARGS},
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
			MyString input;

			UnprocessedOptions(Allocator<>& allocator);
			UnprocessedOptions(const UnprocessedOptions&) = delete;
			UnprocessedOptions(UnprocessedOptions&&) = delete;
			UnprocessedOptions& operator=(const UnprocessedOptions&) = delete;
			UnprocessedOptions& operator=(UnprocessedOptions&&) = delete;
		};
		
		bool parse_arguments(int argc, char* argv[], UnprocessedOptions& output,
			Allocator<> alloc);

		std::optional<const OptionDescription*> find_option(const char* option);
	}
	
}
