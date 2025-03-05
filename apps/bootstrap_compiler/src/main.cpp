
#include <iostream>

#include "version.h"
#include "cmd_line/arg_parsing.h"

namespace hemera {
	int main(int argc, char* argv[])
	{
		Allocator<> allocator;

		MyVector<arg_parse::ArgumentInfo>* args =
			arg_parse::parse_arguments(argc, argv, allocator);

		std::cout << "Options:";
		for (auto arg : *args) {
			std::cout << "{ Option : " << arg.option << ", args: ";
			for (size_t i = 0; i < arg.values.size(); ++i) {
				std::cout << '\'' << arg.values[i] << '\'';
				if (i + 1 < arg.values.size()) {
					std::cout << ", ";
				}
			}
			std::cout << " }";
		}
		std::cout << std::endl;
		return 0;
	}
}

int main(int argc, char* argv[])
{
	return hemera::main(argc, argv);
}