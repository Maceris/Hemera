
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
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"

namespace hemera {
	
	static void fill_out_dummy_module(llvm::LLVMContext& context, unsigned int address_space, llvm::Module* module) {
		//TODO(ches) get rid of the dummy module

		llvm::Type* int32 = llvm::Type::getInt32Ty(context);
		llvm::FunctionType* func_type = llvm::FunctionType::get(int32, false);
		llvm::Function* func = llvm::Function::Create(func_type,
			llvm::Function::ExternalLinkage,
			address_space,
			"main",
			module
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
		if (llvm::verifyModule(*module, &os)) {
			std::cout << "Module verification failed: " << os.str() << std::endl;
		}
	}

	static int main(int argc, char* argv[])
	{
		Logger::init();
		Allocator<> main_alloc;
		int rc = 0;

		bool all_fine = true;
		hemera::Options* options = handle_command_line(argc, argv, main_alloc,
			&all_fine);

		if (!all_fine) {
			return 1;
		}
		if (!options) {
			return 0;
		}

		std::string object_file_name = std::format("{}.o", options->output_name);
		llvm::Module* main_module = nullptr;
		unsigned int address_space = 0;
		Backend* backend = nullptr;

		initialize_reporting_storage();

		// Compile
		ThreadSafeQueue<Job> work_queue = ThreadSafeQueue<Job>();
		ThreadPool threads = ThreadPool();

		mlir::MLIRContext mlir_context;
		mlir_context.loadDialect<mlir::BuiltinDialect>();
		mlir_context.loadDialect<mlir::func::FuncDialect>();
		mlir::OpBuilder mlir_builder(&mlir_context);

		mlir::ModuleOp mlir_module =
			mlir::ModuleOp::create(mlir_builder.getUnknownLoc());

		ProgramInfo* program_info = main_alloc.new_object<ProgramInfo>(
			&mlir_context, &mlir_builder, &mlir_module);

		//TODO(ches) this isn't thread safe, we need locking or more contexts
		llvm::LLVMContext context;

		kick_off_processing(program_info);

		if (options->build_extent < BuildExtent::LOWER) {
			goto teardown_compilation;
		}

		// Lower
		
		//TODO(ches) Lower

		if (options->build_extent < BuildExtent::ASSEMBLE) {
			goto teardown_lowering;
		}
		// Assemble

		backend = main_alloc.new_object<BackendLLVM>();
		if (!backend->initialize(*options)) {
			goto teardown_lowering;
		}

		main_module = main_alloc.new_object<llvm::Module>(options->output_name,
			context);

		fill_out_dummy_module(context, address_space, main_module);
		
		backend->generate_object_file(*options, *main_module, object_file_name);

		if (options->build_extent < BuildExtent::LINK) {
			goto teardown_assembly;
		}
		// Link
		
		backend->link(*options, object_file_name);

	teardown_assembly:

	teardown_lowering:
		backend->destroy();
		delete backend;
		backend = nullptr;

	teardown_compilation:
		destroy_reporting_storage();

		return rc;
	}
}

int main(int argc, char* argv[])
{
	return hemera::main(argc, argv);
}
