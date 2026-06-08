
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

		cout << "Usage: hemera [-c | -S ] [-g] [-d] [-o=output_name] inputs..." << endl;
		cout << "       hemera --list=[architecture | subarchitecture | vendor | os | environment | object]" << endl;
		cout << "Flags:" << endl;

		size_t longest_flag = 0;
		for (const auto& arg : arg_parse::NAMED_OPTIONS) {
			longest_flag = std::max(arg.name_length, longest_flag);
		}
		static const char* ARGS_STRING = "=arg1";
		static const size_t ARGS_STRING_LEN = strlen(ARGS_STRING);

		const size_t total_space = longest_flag + ARGS_STRING_LEN + 1;

		for (const auto& arg : arg_parse::NAMED_OPTIONS) {
			cout << arg.name;
			size_t length_used = arg.name_length;
			if (arg.has_args) {
				cout << ARGS_STRING;
				length_used += ARGS_STRING_LEN;
			}
			cout << std::string(total_space - length_used, ' ');
			cout << arg.summary;
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
			std::cout << "Apple ";
			std::cout << "PC ";
			std::cout << "AMD ";
			std::cout << "Intel ";
			std::cout << std::endl;
		}
		else if (value == "os") {
			std::cout << "Operating systems: ";
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
		else if (value == "object") {
			std::cout << "Operating systems: ";
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
