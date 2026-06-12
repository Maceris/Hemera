
#include <iostream>

#include "job.h"
#include "cmd_line/arg_parsing.h"
#include "cmd_line/cmd_line_utils.h"
#include "cmd_line/options.h"
#include "memory/thread_safe_queue.h"
#include "util/logger.h"
#include "util/thread_pool.h"

namespace hemera {

	static int main(int argc, char* argv[])
	{
		Logger::init();
		Allocator<> arg_alloc;

		arg_parse::UnprocessedOptions* command_line_options =
			arg_alloc.new_object<arg_parse::UnprocessedOptions>();

		bool all_fine = arg_parse::parse_arguments(argc, argv, 
			*command_line_options, arg_alloc);

		if (!all_fine) {
			std::cout << "Error parsing arguments!" << std::endl;

			print_command_line_help();
			return 1;
		}

		for (const auto& option : command_line_options->options) {
			if (option == arg_parse::Option::HELP) {
				print_command_line_help();
				return 0;
			}

			if (option == arg_parse::Option::VERSION) {
				print_command_line_version();
				return 0;
			}
		}

		for (const auto& option_with_value : command_line_options->options_with_values) {
			if (option_with_value.option == arg_parse::Option::LIST) {
				for (const auto& value : option_with_value.values) {
					print_command_line_arg_list(value);
				}
				return 0;
			}
		}

		hemera::Options* options = new hemera::Options();
		all_fine = process_command_line_args(*command_line_options, *options);
		if (!all_fine) {
			std::cout << "Error parsing arguments!" << std::endl;

			print_command_line_help();
			return 1;
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
