#include "cmd_line/cmd_line_utils.h"

#include <algorithm>
#include <cctype>
#include <iostream>

#include "version.h"
#include "cmd_line/arg_parsing.h"
#include "util/logger.h"

namespace hemera {

	void print_command_line_help() {
		using std::cout;
		using std::endl;

		cout << "Usage: hemera [<optional flags>...] <package path>" << endl;
		cout << "       hemera --list=<type(s)>" << endl;
		cout << "Flags:" << endl;

		static const char* ARG_STRING = "=value";
		static const size_t ARG_STRING_LEN = strlen(ARG_STRING);
		static const char* MULTIPLE_ARGS_STRING = "=arg1,arg2,...";
		static const size_t MULTIPLE_ARGS_STRING_LEN
			= strlen(MULTIPLE_ARGS_STRING);

		size_t longest_flag = 0;
		for (const auto& arg : arg_parse::NAMED_OPTIONS) {
			size_t total_length = 0;
			for (const auto& name_mapping : arg_parse::OPTION_MAPPINGS) {
				if (arg.option == name_mapping.option) {
					if (total_length > 0) {
						// Comma and space between items
						total_length += 2;
					}
					total_length += name_mapping.name_length;
				}
			}

			if (arg.has_args) {
				if (arg.multiple_args) {
					total_length += MULTIPLE_ARGS_STRING_LEN;
				}
				else {
					total_length += ARG_STRING_LEN;
				}
			}
			longest_flag = std::max(total_length, longest_flag);
		}

		const size_t total_space = longest_flag + 1;
		LOG_ASSERT(total_space < 80);

		for (const auto& arg : arg_parse::NAMED_OPTIONS) {
			size_t length_used = 0;

			for (const auto& name_mapping : arg_parse::OPTION_MAPPINGS) {
				if (arg.option != name_mapping.option) {
					continue;
				}
				if (length_used > 0) {
					// We already listed an option
					cout << ", ";
					length_used += 2;
				}
				cout << name_mapping.name;
				length_used += name_mapping.name_length;
			}

			if (arg.has_args) {
				if (arg.multiple_args) {
					cout << MULTIPLE_ARGS_STRING;
					length_used += MULTIPLE_ARGS_STRING_LEN;
				}
				else {
					cout << ARG_STRING;
					length_used += ARG_STRING_LEN;
				}
			}

			cout << std::string(total_space - length_used, ' ');

			// Word wrapping hell
			std::streamsize remaining_summary =
				static_cast<std::streamsize>(strlen(arg.summary));
			const std::streamsize description_space =
				80 - static_cast<std::streamsize>(total_space);
			const std::string full_padding = std::string(total_space, ' ');
			std::streamsize end_of_word = 0;
			const char* current_line_start = arg.summary;
			bool has_wrapped = false;

			while (remaining_summary > 0) {
				if (has_wrapped) {
					cout << full_padding;
				}
				if (description_space >= remaining_summary) {
					// the rest fits on this line
					cout.write(current_line_start, remaining_summary);
					break;
				}
				else {
					// we need to break

					// Find the first space working back from where we need to wrap
					end_of_word = std::min(description_space, remaining_summary);
					while (*(current_line_start + end_of_word) != ' ' && end_of_word > 0) {
						end_of_word -= 1;
					}
					LOG_ASSERT(end_of_word > 0
						&& "Stop using diabolically long words in the description please");

					cout.write(current_line_start, end_of_word);
					cout << endl;

					has_wrapped = true;
					if (*(current_line_start + end_of_word) == ' ') {
						// We wrapped on a space, so skip that space
						current_line_start += 1;
						remaining_summary -= 1;
					}
					current_line_start += end_of_word;
					remaining_summary -= end_of_word;
				}
			}

			cout << endl;
		}
	}

	void print_command_line_version() {
		std::cout << "Hemera compiler version " << VERSION_STR << std::endl;
		std::cout << VERSION_COPYRIGHT_STR << std::endl;
	}

	void print_command_line_arg_list(const MyString& value) {
		using std::cout;
		using std::endl;

		if (value == "architecture") {
			cout << "Architectures: ";
			cout << "arm ";
			cout << "armeb ";
			cout << "aarch64 ";
			cout << "aarch64_be ";
			cout << "aarch64_32 ";
			cout << "x86 ";
			cout << "x86_64 ";
			cout << endl;
		}
		else if (value == "subarchitecture") {
			cout << "Sub-architectures: ";
			cout << "None ";
			cout << "ARMSubArch_v9_7a ";
			cout << "ARMSubArch_v9_6a ";
			cout << "ARMSubArch_v9_5a ";
			cout << "ARMSubArch_v9_4a ";
			cout << "ARMSubArch_v9_3a ";
			cout << "ARMSubArch_v9_2a ";
			cout << "ARMSubArch_v9_1a ";
			cout << "ARMSubArch_v9 ";
			cout << "ARMSubArch_v8_9a ";
			cout << "ARMSubArch_v8_8a ";
			cout << "ARMSubArch_v8_7a ";
			cout << "ARMSubArch_v8_6a ";
			cout << "ARMSubArch_v8_5a ";
			cout << "ARMSubArch_v8_4a ";
			cout << "ARMSubArch_v8_3a ";
			cout << "ARMSubArch_v8_2a ";
			cout << "ARMSubArch_v8_1a ";
			cout << "ARMSubArch_v8 ";
			cout << "ARMSubArch_v8r ";
			cout << "ARMSubArch_v8m_baseline ";
			cout << "ARMSubArch_v8m_mainline ";
			cout << "ARMSubArch_v8_1m_mainline ";
			cout << "ARMSubArch_v7 ";
			cout << "ARMSubArch_v7em ";
			cout << "ARMSubArch_v7m ";
			cout << "ARMSubArch_v7s ";
			cout << "ARMSubArch_v7k ";
			cout << "ARMSubArch_v7ve ";
			cout << "ARMSubArch_v6 ";
			cout << "ARMSubArch_v6m ";
			cout << "ARMSubArch_v6k ";
			cout << "ARMSubArch_v6t2 ";
			cout << "ARMSubArch_v5 ";
			cout << "ARMSubArch_v5te ";
			cout << "ARMSubArch_v4t ";
			cout << "AArch64SubArch_arm64e ";
			cout << "AArch64SubArch_arm64ec ";
			cout << "AArch64SubArch_lfi ";
			cout << endl;
		}
		else if (value == "vendor") {
			cout << "Vendors: ";
			cout << "Unknown ";
			cout << "Apple ";
			cout << "PC ";
			cout << "AMD ";
			cout << "Intel ";
			cout << endl;
		}
		else if (value == "os") {
			cout << "Operating systems: ";
			cout << "Unknown ";
			cout << "Darwin ";
			cout << "FreeBSD ";
			cout << "Linux ";
			cout << "MacOSX ";
			cout << "NetBSD ";
			cout << "OpenBSD ";
			cout << "UEFI ";
			cout << "Win32 ";
			cout << "Firmware ";
			cout << endl;
		}
		else if (value == "environment") {
			cout << "Environments: ";
			cout << "Unknown ";
			cout << "GNU ";
			cout << "GNUT64 ";
			cout << "GNUEABI ";
			cout << "GNUEABIT64 ";
			cout << "GNUEABIHF ";
			cout << "GNUEABIHFT64 ";
			cout << "GNUF32 ";
			cout << "GNUF64 ";
			cout << "GNUSF ";
			cout << "GNUX32 ";
			cout << "GNUILP32 ";
			cout << "EABI ";
			cout << "EABIHF ";
			cout << "Musl ";
			cout << "MuslABI64 ";
			cout << "MuslEABI ";
			cout << "MuslEABIHF ";
			cout << "MuslF32 ";
			cout << "MuslSF ";
			cout << "MuslX32 ";
			cout << "MSVC ";
			cout << "Itanium ";
			cout << endl;
		}
		else if (value == "object-format") {
			cout << "Object Formats: ";
			cout << "Unknown ";
			cout << "COFF ";
			cout << "ELF ";
			cout << "MachO ";
			cout << endl;
		}
	}

	bool process_command_line_args(const arg_parse::UnprocessedOptions& input,
		hemera::Options& output) {

		using std::cout;
		using std::endl;

		output.input = std::string(input.input.data(), input.input.size());

		bool architecture_seen = false;
		bool debug_info_seen = false;
		bool environment_seen = false;
		bool object_format_seen = false;
		bool os_seen = false;
		bool stage_seen = false;
		bool subarchitecture_seen = false;
		bool vendor_seen = false;

		for (const auto& option : input.options) {
			switch (option) {
			case hemera::arg_parse::STOP_BEFORE_LOWERING:
				if (stage_seen) {
					std::cout << "Duplicate stage flag" << std::endl;
					return 1;
				}
				output.build_extent = BuildExtent::COMPILE;
				stage_seen = true;
				break;
			case hemera::arg_parse::STOP_BEFORE_ASSEMBLY:
				if (stage_seen) {
					std::cout << "Duplicate stage flag" << std::endl;
					return 1;
				}
				output.build_extent = BuildExtent::LOWER;
				stage_seen = true;
				break;
			case hemera::arg_parse::STOP_BEFORE_LINK:
				if (stage_seen) {
					std::cout << "Duplicate stage flag" << std::endl;
					return 1;
				}
				output.build_extent = BuildExtent::ASSEMBLE;
				stage_seen = true;
				break;
			case hemera::arg_parse::DEBUG_INFO:
				if (debug_info_seen) {
					cout << "Duplicate debug flag" << endl;
					return false;
				}
				output.debug_info = true;
				debug_info_seen = true;
				break;
			case hemera::arg_parse::ARCHITECTURE:
			case hemera::arg_parse::ENVIRONMENT:
			case hemera::arg_parse::HELP:
			case hemera::arg_parse::LIST:
			case hemera::arg_parse::OBJECT_FORMAT:
			case hemera::arg_parse::OS:
			case hemera::arg_parse::OUTPUT:
			case hemera::arg_parse::SUBARCHITECTURE:
			case hemera::arg_parse::VENDOR:
			case hemera::arg_parse::VERSION:
				break;
			}
		}

		for (const auto& option_with_value : input.options_with_values) {

			MyString first_arg = option_with_value.values[0];
			
			std::transform(first_arg.begin(), first_arg.end(), 
				first_arg.begin(), [](unsigned char c) {
				return std::tolower(c);
			});

			switch (option_with_value.option) {
			case hemera::arg_parse::ARCHITECTURE:
				if (architecture_seen) {
					cout << "Duplicate architecture flag" << endl;
					return false;
				}

				if (strcmp("arm", first_arg.c_str()) == 0) {
					output.architecture = ArchType::arm;
					architecture_seen = true;
				}
				else if (strcmp("armeb", first_arg.c_str()) == 0) {
					output.architecture = ArchType::armeb;
					architecture_seen = true;
				}
				else if (strcmp("aarch64", first_arg.c_str()) == 0) {
					output.architecture = ArchType::aarch64;
					architecture_seen = true;
				}
				else if (strcmp("aarch64_be", first_arg.c_str()) == 0) {
					output.architecture = ArchType::aarch64_be;
					architecture_seen = true;
				}
				else if (strcmp("aarch64_32", first_arg.c_str()) == 0) {
					output.architecture = ArchType::aarch64_32;
					architecture_seen = true;
				}
				else if (strcmp("x86", first_arg.c_str()) == 0) {
					output.architecture = ArchType::x86;
					architecture_seen = true;
				}
				else if (strcmp("x86_64", first_arg.c_str()) == 0) {
					output.architecture = ArchType::x86_64;
					architecture_seen = true;
				}

				if (!architecture_seen) {
					cout << "Unrecognized architecture: " << first_arg << endl;
				}
				break;
			case hemera::arg_parse::ENVIRONMENT:
				if (environment_seen) {
					cout << "Duplicate environment flag" << endl;
					return false;
				}
				
				if (strcmp("unknown", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::UnknownEnvironment;
					environment_seen = true;
				}
				else if (strcmp("gnu", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::GNU;
					environment_seen = true;
				}
				else if (strcmp("gnut64", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::GNUT64;
					environment_seen = true;
				}
				else if (strcmp("gnueabi", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::GNUEABI;
					environment_seen = true;
				}
				else if (strcmp("gnueabit64", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::GNUEABIT64;
					environment_seen = true;
				}
				else if (strcmp("gnueabihf", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::GNUEABIHF;
					environment_seen = true;
				}
				else if (strcmp("gnueabihft64", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::GNUEABIHFT64;
					environment_seen = true;
				}
				else if (strcmp("gnuf32", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::GNUF32;
					environment_seen = true;
				}
				else if (strcmp("gnuf64", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::GNUF64;
					environment_seen = true;
				}
				else if (strcmp("gnusf", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::GNUSF;
					environment_seen = true;
				}
				else if (strcmp("gnux32", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::GNUX32;
					environment_seen = true;
				}
				else if (strcmp("gnuilp32", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::GNUILP32;
					environment_seen = true;
				}
				else if (strcmp("eabi", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::EABI;
					environment_seen = true;
				}
				else if (strcmp("eabihf", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::EABIHF;
					environment_seen = true;
				}
				else if (strcmp("musl", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::Musl;
					environment_seen = true;
				}
				else if (strcmp("muslabi64", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::MuslABI64;
					environment_seen = true;
				}
				else if (strcmp("musleabi", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::MuslEABI;
					environment_seen = true;
				}
				else if (strcmp("musleabihf", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::MuslEABIHF;
					environment_seen = true;
				}
				else if (strcmp("muslf32", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::MuslF32;
					environment_seen = true;
				}
				else if (strcmp("muslsf", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::MuslSF;
					environment_seen = true;
				}
				else if (strcmp("muslx32", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::MuslX32;
					environment_seen = true;
				}
				else if (strcmp("msvc", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::MSVC;
					environment_seen = true;
				}
				else if (strcmp("itanium", first_arg.c_str()) == 0) {
					output.environment = EnvironmentType::Itanium;
					environment_seen = true;
				}

				if (!environment_seen) {
					cout << "Unrecognized environment: " << first_arg << endl;
				}
				break;
			case hemera::arg_parse::OBJECT_FORMAT:
				if (object_format_seen) {
					cout << "Duplicate object-format flag" << endl;
					return false;
				}

				if (strcmp("unknown", first_arg.c_str()) == 0) {
					output.object_format = ObjectFormatType::UnknownObjectFormat;
					object_format_seen = true;
				}
				else if (strcmp("coff", first_arg.c_str()) == 0) {
					output.object_format = ObjectFormatType::COFF;
					object_format_seen = true;
				}
				else if (strcmp("elf", first_arg.c_str()) == 0) {
					output.object_format = ObjectFormatType::ELF;
					object_format_seen = true;
				}
				else if (strcmp("macho", first_arg.c_str()) == 0) {
					output.object_format = ObjectFormatType::MachO;
					object_format_seen = true;
				}

				if (!object_format_seen) {
					cout << "Unrecognized object format: " << first_arg << endl;
				}
				break;
			case hemera::arg_parse::OS:
				if (os_seen) {
					cout << "Duplicate os flag" << endl;
					return false;
				}

				if (strcmp("unknown", first_arg.c_str()) == 0) {
					output.os = OSType::UnknownOS;
					os_seen = true;
				}
				else if (strcmp("darwin", first_arg.c_str()) == 0) {
					output.os = OSType::Darwin;
					os_seen = true;
				}
				else if (strcmp("freebsd", first_arg.c_str()) == 0) {
					output.os = OSType::FreeBSD;
					os_seen = true;
				}
				else if (strcmp("linux", first_arg.c_str()) == 0) {
					output.os = OSType::Linux;
					os_seen = true;
				}
				else if (strcmp("macosx", first_arg.c_str()) == 0) {
					output.os = OSType::MacOSX;
					os_seen = true;
				}
				else if (strcmp("netbsd", first_arg.c_str()) == 0) {
					output.os = OSType::NetBSD;
					os_seen = true;
				}
				else if (strcmp("openbsd", first_arg.c_str()) == 0) {
					output.os = OSType::OpenBSD;
					os_seen = true;
				}
				else if (strcmp("uefi", first_arg.c_str()) == 0) {
					output.os = OSType::UEFI;
					os_seen = true;
				}
				else if (strcmp("win32", first_arg.c_str()) == 0) {
					output.os = OSType::Win32;
					os_seen = true;
				}
				else if (strcmp("firmware", first_arg.c_str()) == 0) {
					output.os = OSType::Firmware;
					os_seen = true;
				}

				if (!os_seen) {
					cout << "Unrecognized os: " << first_arg << endl;
				}
				break;
			case hemera::arg_parse::SUBARCHITECTURE:
				if (subarchitecture_seen) {
					cout << "Duplicate subarchitecture flag" << endl;
					return false;
				}

				if (strcmp("none", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::NoSubArch;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v9_7a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v9_7a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v9_6a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v9_6a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v9_5a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v9_5a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v9_4a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v9_4a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v9_3a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v9_3a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v9_2a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v9_2a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v9_1a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v9_1a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v9", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v9;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8_9a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8_9a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8_8a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8_8a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8_7a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8_7a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8_6a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8_6a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8_5a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8_5a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8_4a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8_4a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8_3a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8_3a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8_2a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8_2a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8_1a", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8_1a;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8r", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8r;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8m_baseline", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8m_baseline;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8m_mainline", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8m_mainline;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v8_1m_mainline", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v8_1m_mainline;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v7", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v7;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v7em", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v7em;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v7m", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v7m;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v7s", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v7s;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v7k", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v7k;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v7ve", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v7ve;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v6", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v6;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v6m", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v6m;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v6k", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v6k;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v6t2", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v6t2;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v5", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v5;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v5te", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v5te;
					subarchitecture_seen = true;
				}
				else if (strcmp("armsubarch_v4t", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::ARMSubArch_v4t;
					subarchitecture_seen = true;
				}
				else if (strcmp("aarch64subarch_arm64e", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::AArch64SubArch_arm64e;
					subarchitecture_seen = true;
				}
				else if (strcmp("aarch64subarch_arm64ec", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::AArch64SubArch_arm64ec;
					subarchitecture_seen = true;
				}
				else if (strcmp("aarch64subarch_lfi", first_arg.c_str()) == 0) {
					output.subarchitecture = SubArchType::AArch64SubArch_lfi;
					subarchitecture_seen = true;
				}

				if (!subarchitecture_seen) {
					cout << "Unrecognized subarchitecture: " << first_arg << endl;
				}
				break;
			case hemera::arg_parse::VENDOR:
				if (vendor_seen) {
					cout << "Duplicate vendor flag" << endl;
					return false;
				}

				if (strcmp("unknown", first_arg.c_str()) == 0) {
					output.vendor = VendorType::UnknownVendor;
					vendor_seen = true;
				}
				else if (strcmp("apple", first_arg.c_str()) == 0) {
					output.vendor = VendorType::Apple;
					vendor_seen = true;
				}
				else if (strcmp("pc", first_arg.c_str()) == 0) {
					output.vendor = VendorType::PC;
					vendor_seen = true;
				}
				else if (strcmp("amd", first_arg.c_str()) == 0) {
					output.vendor = VendorType::AMD;
					vendor_seen = true;
				}
				else if (strcmp("intel", first_arg.c_str()) == 0) {
					output.vendor = VendorType::Intel;
					vendor_seen = true;
				}

				if (!vendor_seen) {
					cout << "Unrecognized vendor: " << first_arg << endl;
				}
				break;
			case hemera::arg_parse::DEBUG_INFO:
			case hemera::arg_parse::HELP:
			case hemera::arg_parse::LIST:
			case hemera::arg_parse::OUTPUT:
			case hemera::arg_parse::STOP_BEFORE_LOWERING:
			case hemera::arg_parse::STOP_BEFORE_ASSEMBLY:
			case hemera::arg_parse::STOP_BEFORE_LINK:
			case hemera::arg_parse::VERSION:
				break;
			}
		}

		return true;
	}
}
