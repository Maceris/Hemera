#pragma once

#include "memory/allocator.h"
#include "cmd_line/arg_parsing.h"
#include "cmd_line/options.h"

namespace hemera {

	hemera::Options* handle_command_line(int argc, char* argv[], Allocator<> main_alloc, bool* all_fine);
	void print_command_line_help();
	void print_command_line_version();
	void print_command_line_arg_list(const MyString& value);
	bool process_command_line_args(const arg_parse::UnprocessedOptions& input,
		hemera::Options& output);
}
