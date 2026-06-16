
#include <iostream>

#include "job.h"
#include "back_end/back_end.h"
#include "cmd_line/arg_parsing.h"
#include "cmd_line/cmd_line_utils.h"
#include "cmd_line/options.h"
#include "memory/thread_safe_queue.h"
#include "util/logger.h"
#include "util/thread_pool.h"

#include "llvm/IR/IRBuilder.h"

namespace hemera {

	static int main(int argc, char* argv[])
	{
		Logger::init();
		Allocator<> arg_alloc;

		arg_parse::UnprocessedOptions* command_line_options =
			arg_alloc.new_object<arg_parse::UnprocessedOptions>(arg_alloc);

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

		if (command_line_options->input.empty()) {
			std::cout << "Missing input folder! Please provide a path to a package." << std::endl;
		}

		Allocator<> main_alloc;

		hemera::Options* options = main_alloc.new_object<hemera::Options>();
		all_fine = process_command_line_args(*command_line_options, *options);
		if (!all_fine) {
			std::cout << "Error parsing arguments!" << std::endl;

			print_command_line_help();
			return 1;
		}

		ThreadSafeQueue<Job> work_queue = ThreadSafeQueue<Job>();

		ThreadPool threads = ThreadPool();

		// Compile

		if (options->build_extent < BuildExtent::LOWER) {
			return 0;
		}

		//TODO(ches) Lower

		if (options->build_extent < BuildExtent::ASSEMBLE) {
			return 0;
		}
		//TODO(ches) Assemble
		Backend* backend = new BackendLLVM();
		backend->initialize(*options);
		
		//TODO(ches) get rid of the dummy module
		llvm::LLVMContext context;
		llvm::Module* dummy_module = main_alloc.new_object<llvm::Module>(
			"dummy_module", context);
		llvm::Type* int32 = llvm::Type::getInt32Ty(context);
		llvm::FunctionType* func_type = llvm::FunctionType::get(int32, false);
		llvm::Function* func = llvm::Function::Create(func_type,
			llvm::Function::ExternalLinkage,
			"main",
			dummy_module
		);
		llvm::BasicBlock* block = llvm::BasicBlock::Create(context, "entry", func);
		llvm::IRBuilder<> builder(block);
		llvm::Value* constant_zero = builder.getInt32(0);
		builder.CreateRet(constant_zero);

		backend->generate_object_file(*options, *dummy_module);

		if (options->build_extent < BuildExtent::LINK) {
			backend->destroy();
			delete backend;
			backend = nullptr;
			return 0;
		}
		//TODO(ches) Link

		backend->destroy();
		delete backend;
		backend = nullptr;
		return 0;
	}
}

int main(int argc, char* argv[])
{
	return hemera::main(argc, argv);
}
