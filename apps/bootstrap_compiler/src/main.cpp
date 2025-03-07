
#include <iostream>

#include "version.h"
#include "cmd_line/arg_parsing.h"

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
		Allocator<> allocator;

		using std::cout;
		using std::endl;

		arg_parse::Options* options =
			allocator.new_object<arg_parse::Options>();

		arg_parse::parse_arguments(argc, argv, *options);

		cout << "Options:" << endl;

		cout << "Input: ";
		print_list(options->input);
		cout << endl;
		cout << "Output: " << options->output << endl;

		cout << "Flags: ";
		print_list(options->options);
		cout << endl;

		cout << "Flags with options: ";
		for (size_t i = 0; i < options->options_with_values.size(); ++i) {
			cout << "{ " << options->options_with_values[i].option << " | ";
			print_list(options->options_with_values[i].values);
			cout << " }";
			if (i + 1 < options->options_with_values.size()) {
				std::cout << ", ";
			}
		}
		cout << endl;

		return 0;
	}
}

int main(int argc, char* argv[])
{
	return hemera::main(argc, argv);
}