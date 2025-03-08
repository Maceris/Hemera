
#include <iostream>

#include "version.h"
#include "cmd_line/arg_parsing.h"
#include "util/logger.h"

namespace hemera {

	static void print_help() {
		using std::cout;
		using std::endl;

		cout << "Usage: hemera [-c | -S ] [-g] [-d] [-o=output_name] inputs..." << endl;
		cout << "Flags:" << endl;

		size_t longest_flag = 0;
		for (const auto& arg : arg_parse::NAMED_OPTIONS) {
			longest_flag = std::max(arg.name_length, longest_flag);
		}
		static const char* ARGS_STRING = "=arg1,arg2...";
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

	int main(int argc, char* argv[])
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

		return 0;
	}
}

int main(int argc, char* argv[])
{
	return hemera::main(argc, argv);
}