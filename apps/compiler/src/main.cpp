
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

		hemera::Options options{};

		bool architecture_seen = false;
		bool debug_info_seen = false;
		bool environment_seen = false;
		bool object_format_seen = false;
		bool os_seen = false;
		bool stage_seen = false;
		bool subarchitecture_seen = false;
		bool vendor_seen = false;

		for (const auto& option : command_line_options->options) {
			switch (option) {
			case hemera::arg_parse::STOP_BEFORE_ASSEMBLY:
				if (stage_seen) {
					std::cout << "Duplicate stage flag" << std::endl;
					return 1;
				}
				options.build_extent = BuildExtent::LOWER;
				stage_seen = true;
				break;
			case hemera::arg_parse::STOP_BEFORE_LINK:
				if (stage_seen) {
					std::cout << "Duplicate stage flag" << std::endl;
					return 1;
				}
				options.build_extent = BuildExtent::ASSEMBLE;
				stage_seen = true;
				break;
			case hemera::arg_parse::ARCHITECTURE:
			case hemera::arg_parse::DEBUG_INFO:
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

		for (const auto& option_with_value : command_line_options->options_with_values) {
			switch (option_with_value.option) {
				case hemera::arg_parse::ARCHITECTURE:
					if (architecture_seen) {
						std::cout << "Duplicate architecture flag" << std::endl;
						return 1;
					}
					//TODO(ches) parse arg
					architecture_seen = true;
					break;
				case hemera::arg_parse::DEBUG_INFO:
					if (debug_info_seen) {
						std::cout << "Duplicate debug flag" << std::endl;
						return 1;
					}
					//TODO(ches) parse arg
					debug_info_seen = true;
					break;
				case hemera::arg_parse::ENVIRONMENT:
					if (environment_seen) {
						std::cout << "Duplicate environment flag" << std::endl;
						return 1;
					}
					//TODO(ches) parse arg
					environment_seen = true;
					break;
				case hemera::arg_parse::OBJECT_FORMAT:
					if (object_format_seen) {
						std::cout << "Duplicate object-format flag" << std::endl;
						return 1;
					}
					//TODO(ches) parse arg
					object_format_seen = true;
					break;
				case hemera::arg_parse::OS:
					if (os_seen) {
						std::cout << "Duplicate os flag" << std::endl;
						return 1;
					}
					//TODO(ches) parse arg
					os_seen = true;
					break;
				case hemera::arg_parse::SUBARCHITECTURE:
					if (subarchitecture_seen) {
						std::cout << "Duplicate subarchitecture flag" << std::endl;
						return 1;
					}
					//TODO(ches) parse arg
					subarchitecture_seen = true;
					break;
				case hemera::arg_parse::VENDOR:
					if (vendor_seen) {
						std::cout << "Duplicate vendor flag" << std::endl;
						return 1;
					}
					//TODO(ches) parse arg
					vendor_seen = true;
					break;
				case hemera::arg_parse::HELP:
				case hemera::arg_parse::LIST:
				case hemera::arg_parse::OUTPUT:
				case hemera::arg_parse::STOP_BEFORE_ASSEMBLY:
				case hemera::arg_parse::STOP_BEFORE_LINK:
				case hemera::arg_parse::VERSION:
					break;
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
