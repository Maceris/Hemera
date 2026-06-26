
#include <iostream>
#include <format>

#include "job.h"
#include "back_end/back_end.h"
#include "cmd_line/arg_parsing.h"
#include "cmd_line/cmd_line_utils.h"
#include "cmd_line/options.h"
#include "error/reporting.h"
#include "front_end/front_end.h"
#include "memory/thread_safe_queue.h"
#include "util/logger.h"
#include "util/thread_pool.h"

#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Support/FileSystem.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"

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
			return 1;
		}

		Allocator<> main_alloc;

		hemera::Options* options = main_alloc.new_object<hemera::Options>();
		all_fine = process_command_line_args(*command_line_options, *options);
		if (!all_fine) {
			std::cout << "Error parsing arguments!" << std::endl;

			print_command_line_help();
			return 1;
		}
		initialize_reporting_storage();

		// Compile
		ThreadSafeQueue<Job> work_queue = ThreadSafeQueue<Job>();
		ThreadPool threads = ThreadPool();

		mlir::MLIRContext mlir_context;
		mlir_context.loadDialect<mlir::BuiltinDialect>();
		mlir::OpBuilder mlir_builder(&mlir_context);

		mlir::ModuleOp mlir_module =
			mlir::ModuleOp::create(mlir_builder.getUnknownLoc());
		
		ProgramInfo* program_info = main_alloc.new_object<ProgramInfo>(
			&mlir_context, &mlir_builder, &mlir_module);

		kick_off_processing(program_info);

		if (options->build_extent < BuildExtent::LOWER) {
			destroy_reporting_storage();
			return 0;
		}

		//TODO(ches) Lower

		if (options->build_extent < BuildExtent::ASSEMBLE) {
			destroy_reporting_storage();
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

		std::string errorStr;
		llvm::raw_string_ostream os(errorStr);
		if (llvm::verifyFunction(*func, &os)) {
			std::cout << "Function verification failed: " << os.str() << std::endl;
			errorStr.clear();
		}
		if (llvm::verifyModule(*dummy_module, &os)) {
			std::cout << "Module verification failed: " << os.str() << std::endl;
		}

		std::string object_file_name = std::format("{}.o", options->output_name);
		backend->generate_object_file(*options, *dummy_module, object_file_name);

		if (options->build_extent < BuildExtent::LINK) {
			backend->destroy();
			delete backend;
			backend = nullptr;
			destroy_reporting_storage();
			return 0;
		}
		backend->link(*options, object_file_name);

		backend->destroy();
		delete backend;
		backend = nullptr;
		destroy_reporting_storage();
		return 0;
	}
}

int main(int argc, char* argv[])
{
	return hemera::main(argc, argv);
}
