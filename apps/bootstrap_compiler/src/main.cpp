
#include <iostream>

#include "version.h"
#include "cmd_line/arg_parsing.h"
#include "util/logger.h"

namespace hemera {

	static void print_list(const MyVector<MyString>& list) {
		for (size_t i = 0; i < list.size(); ++i) {
			std::cout << list[i];
			if (i + 1 < list.size()) {
				std::cout << ", ";
			}
		}
	}

	int main(int argc, char* argv[])
	{
		Logger::init();
		Allocator<> arg_alloc;

		using std::cout;
		using std::endl;

		arg_parse::Options* options =
			arg_alloc.new_object<arg_parse::Options>();

		bool all_fine = arg_parse::parse_arguments(argc, argv, *options, arg_alloc);

		cout << "Options:" << endl;

		cout << "Input: ";
		print_list(options->input);
		cout << endl;

		cout << "Options: ";
		for (size_t i = 0; i < options->options.size(); ++i) {
			std::cout << options->options[i];
			if (i + 1 < options->options.size()) {
				std::cout << ", ";
			}
		}
		cout << endl;
		
		cout << "Options with values: ";
		for (size_t i = 0; i < options->options_with_values.size(); ++i) {
			cout << "{ " << options->options_with_values[i].option << " | ";
			print_list(options->options_with_values[i].values);
			cout << " }";
			if (i + 1 < options->options_with_values.size()) {
				std::cout << ", ";
			}
		}
		cout << endl;

		if (!all_fine) {
			//TODO(ches) print help text
			cout << "Not all arguments could be parsed!" << endl;
			return 1;
		}

		return 0;
	}
}

int main(int argc, char* argv[])
{
	return hemera::main(argc, argv);
}