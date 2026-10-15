
#include <cstdlib>
#include <iostream>
#ifdef _MSC_VER
#include <crtdbg.h>
#endif
#include <format>

#include "job.h"
#include "back_end/back_end.h"
#include "cmd_line/arg_parsing.h"
#include "cmd_line/cmd_line_utils.h"
#include "cmd_line/options.h"
#include "error/reporting.h"
#include "front_end/front_end.h"
#include "hmir/hmir_dialect.h"
#include "middle_end/generate.h"
#include "memory/thread_safe_queue.h"
#include "util/logger.h"
#include "util/thread_pool.h"

#include "llvm/Support/FileSystem.h"
#include "llvm/Support/raw_ostream.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"

namespace hemera {
	
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
		std::unique_ptr<llvm::Module> main_module;
		Backend* backend = nullptr;

		initialize_interned_string_cache();
		initialize_reporting_storage();
		enable_reporting();
		enable_reporting_printing();

		// Compile
		ThreadSafeQueue<Job> work_queue = ThreadSafeQueue<Job>();
		ThreadPool threads = ThreadPool();

		mlir::MLIRContext mlir_context;
		mlir_context.loadDialect<mlir::BuiltinDialect>();
		mlir_context.loadDialect<mlir::func::FuncDialect>();
		mlir_context.loadDialect<hmir::HemeraDialect>();
		mlir::OpBuilder mlir_builder(&mlir_context);

		mlir::ModuleOp mlir_module =
			mlir::ModuleOp::create(mlir_builder, mlir_builder.getUnknownLoc(), 
				options->output_name);

		ProgramInfo* program_info = main_alloc.new_object<ProgramInfo>(
			&mlir_context, &mlir_builder, &mlir_module);

		llvm::LLVMContext context;

		kick_off_processing(program_info, options);

		if (error_count() > 0) {
			rc = -1;
			goto teardown_compilation;
		}

		// Generate the program's MLIR, from main and everything it uses
		if (!generate_program(program_info, *options, mlir_module)) {
			rc = -1;
			goto teardown_compilation;
		}

		if (options->build_extent < BuildExtent::LOWER) {
			dump_mlir_to_file(options, &mlir_module);
			goto teardown_compilation;
		}

		// Lower

		main_module = lower_to_llvm(mlir_module, context, *options);

		if (main_module == nullptr || error_count() > 0) {
			rc = -1;
			goto teardown_lowering;
		}
		if (options->build_extent < BuildExtent::ASSEMBLE) {
			std::error_code error;
			llvm::raw_fd_ostream file(std::format("{}.ll", options->output_name), error);
			if (!error) {
				main_module->print(file, nullptr);
			}
			goto teardown_lowering;
		}
		// Assemble

		backend = main_alloc.new_object<BackendLLVM>();
		if (!backend->initialize(*options)) {
			rc = -1;
			goto teardown_lowering;
		}

		if (!backend->generate_object_file(*options, *main_module, object_file_name)) {
			rc = -1;
			goto teardown_lowering;
		}

		if (error_count() > 0) {
			rc = -1;
			goto teardown_assembly;
		}
		if (options->build_extent < BuildExtent::LINK) {
			goto teardown_assembly;
		}
		// Link
		
		backend->link(*options, object_file_name);
		if (error_count() > 0) {
			rc = -1;
		}

	teardown_assembly:

	teardown_lowering:
		if (backend != nullptr) {
			backend->destroy();
			delete backend;
			backend = nullptr;
		}
		main_module.reset();

	teardown_compilation:
		destroy_reporting_storage();
		purge_interned_string_cache();

		return rc;
	}
}

int main(int argc, char* argv[])
{
#ifdef _MSC_VER
	// Report debug-runtime assertions and aborts on stderr instead of in a dialog
	_CrtSetReportMode(_CRT_ASSERT, _CRTDBG_MODE_FILE);
	_CrtSetReportFile(_CRT_ASSERT, _CRTDBG_FILE_STDERR);
	_CrtSetReportMode(_CRT_ERROR, _CRTDBG_MODE_FILE);
	_CrtSetReportFile(_CRT_ERROR, _CRTDBG_FILE_STDERR);
	_set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
#endif
	return hemera::main(argc, argv);
}
