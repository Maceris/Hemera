
#include <iostream>

#include "job.h"
#include "version.h"
#include "cmd_line/arg_parsing.h"
#include "memory/thread_safe_queue.h"
#include "util/logger.h"
#include "util/thread_pool.h"

namespace hemera {

	static void print_help() {
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
			for (const auto& name_mapping: arg_parse::OPTION_MAPPINGS) {
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

	static void print_version() {
		std::cout << "Hemera compiler version " << VERSION_STR << std::endl;
		std::cout << VERSION_COPYRIGHT_STR << std::endl;
	}

	static void print_list(const MyString& value) {
		if (value == "architecture") {
			std::cout << "Architectures: ";
			std::cout << "arm ";
			std::cout << "armeb ";
			std::cout << "aarch64 ";
			std::cout << "aarch64_be ";
			std::cout << "aarch64_32 ";
			std::cout << "x86 ";
			std::cout << "x86_64 ";
			std::cout << std::endl;
		}
		else if (value == "subarchitecture") {
			std::cout << "Sub-architectures: ";
			std::cout << "None ";
			std::cout << "ARMSubArch_v9_7a ";
			std::cout << "ARMSubArch_v9_6a ";
			std::cout << "ARMSubArch_v9_5a ";
			std::cout << "ARMSubArch_v9_4a ";
			std::cout << "ARMSubArch_v9_3a ";
			std::cout << "ARMSubArch_v9_2a ";
			std::cout << "ARMSubArch_v9_1a ";
			std::cout << "ARMSubArch_v9 ";
			std::cout << "ARMSubArch_v8_9a ";
			std::cout << "ARMSubArch_v8_8a ";
			std::cout << "ARMSubArch_v8_7a ";
			std::cout << "ARMSubArch_v8_6a ";
			std::cout << "ARMSubArch_v8_5a ";
			std::cout << "ARMSubArch_v8_4a ";
			std::cout << "ARMSubArch_v8_3a ";
			std::cout << "ARMSubArch_v8_2a ";
			std::cout << "ARMSubArch_v8_1a ";
			std::cout << "ARMSubArch_v8 ";
			std::cout << "ARMSubArch_v8r ";
			std::cout << "ARMSubArch_v8m_baseline ";
			std::cout << "ARMSubArch_v8m_mainline ";
			std::cout << "ARMSubArch_v8_1m_mainline ";
			std::cout << "ARMSubArch_v7 ";
			std::cout << "ARMSubArch_v7em ";
			std::cout << "ARMSubArch_v7m ";
			std::cout << "ARMSubArch_v7s ";
			std::cout << "ARMSubArch_v7k ";
			std::cout << "ARMSubArch_v7ve ";
			std::cout << "ARMSubArch_v6 ";
			std::cout << "ARMSubArch_v6m ";
			std::cout << "ARMSubArch_v6k ";
			std::cout << "ARMSubArch_v6t2 ";
			std::cout << "ARMSubArch_v5 ";
			std::cout << "ARMSubArch_v5te ";
			std::cout << "ARMSubArch_v4t ";
			std::cout << "AArch64SubArch_arm64e ";
			std::cout << "AArch64SubArch_arm64ec ";
			std::cout << "AArch64SubArch_lfi ";
			std::cout << std::endl;
		}
		else if (value == "vendor") {
			std::cout << "Vendors: ";
			std::cout << "Unknown ";
			std::cout << "Apple ";
			std::cout << "PC ";
			std::cout << "AMD ";
			std::cout << "Intel ";
			std::cout << std::endl;
		}
		else if (value == "os") {
			std::cout << "Operating systems: ";
			std::cout << "Unknown ";
			std::cout << "Darwin ";
			std::cout << "FreeBSD ";
			std::cout << "Linux ";
			std::cout << "MacOSX ";
			std::cout << "NetBSD ";
			std::cout << "OpenBSD ";
			std::cout << "UEFI ";
			std::cout << "Win32 ";
			std::cout << "Firmware ";
			std::cout << std::endl;
		}
		else if (value == "environment") {
			std::cout << "Environments: ";
			std::cout << "Unknown ";
			std::cout << "GNU ";
			std::cout << "GNUT64 ";
			std::cout << "GNUEABI ";
			std::cout << "GNUEABIT64 ";
			std::cout << "GNUEABIHF ";
			std::cout << "GNUEABIHFT64 ";
			std::cout << "GNUF32 ";
			std::cout << "GNUF64 ";
			std::cout << "GNUSF ";
			std::cout << "GNUX32 ";
			std::cout << "GNUILP32 ";
			std::cout << "EABI ";
			std::cout << "EABIHF ";
			std::cout << "Musl ";
			std::cout << "MuslABI64 ";
			std::cout << "MuslEABI ";
			std::cout << "MuslEABIHF ";
			std::cout << "MuslF32 ";
			std::cout << "MuslSF ";
			std::cout << "MuslX32 ";
			std::cout << "MSVC ";
			std::cout << "Itanium ";
			std::cout << std::endl;
		}
		else if (value == "object-format") {
			std::cout << "Object Formats: ";
			std::cout << "Unknown ";
			std::cout << "COFF ";
			std::cout << "ELF ";
			std::cout << "MachO ";
			std::cout << std::endl;
		}
	}

	static int main(int argc, char* argv[])
	{
		Logger::init();
		Allocator<> arg_alloc;

		arg_parse::Options* options =
			arg_alloc.new_object<arg_parse::Options>();

		bool all_fine = arg_parse::parse_arguments(argc, argv, *options, arg_alloc);

		if (!all_fine) {
			std::cout << "Error parsing arguments!" << std::endl;

			print_help();
			return 1;
		}

		for (const auto& option : options->options) {
			if (option == arg_parse::Option::HELP) {
				print_help();
				return 0;
			}

			if (option == arg_parse::Option::VERSION) {
				print_version();
				return 0;
			}
		}

		for (const auto& option_with_value : options->options_with_values) {
			if (option_with_value.option == arg_parse::Option::LIST) {
				for (const auto& value : option_with_value.values) {
					print_list(value);
				}
				return 0;
			}
		}

		ThreadSafeQueue<Job> work_queue = ThreadSafeQueue<Job>();

		ThreadPool threads = ThreadPool();

		return 0;
	}
}

int main(int argc, char* argv[])
{
	return hemera::main(argc, argv);
}
