#pragma once

#include "memory/allocator.h"
#include "cmd_line/arg_parsing.h"
#include "cmd_line/options.h"

namespace hemera {

	void print_command_line_help();
	void print_command_line_version();
	void print_command_line_arg_list(const MyString& value);
	bool process_command_line_args(const arg_parse::UnprocessedOptions& input,
		hemera::Options& output);
}
