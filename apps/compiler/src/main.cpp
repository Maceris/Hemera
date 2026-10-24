
#include <cstdlib>
#include <iostream>
#ifdef _MSC_VER
#include <crtdbg.h>
#endif
#include <format>
#include <string>
#include <string_view>
#include <vector>

#include "job.h"
#include "back_end/back_end.h"
#include "back_end/symbolize.h"
#include "cmd_line/arg_parsing.h"
#include "cmd_line/cmd_line_utils.h"
#include "cmd_line/options.h"
#include "error/reporting.h"
#include "front_end/front_end.h"
#include "hmir/hmir_dialect.h"
#include "middle_end/build.h"
#include "middle_end/generate.h"
#include "memory/thread_safe_queue.h"
#include "util/crash_dump.h"
#include "util/logger.h"
#include "util/phase_timer.h"
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
		// hemera --symbolize=<program> <offset>...: a stack trace's frames, from the program's debug info
		if (argc >= 2 && std::string_view(argv[1]).starts_with("--symbolize=")) {
			std::vector<std::string> offsets(argv + 2, argv + argc);
			return symbolize(std::string(std::string_view(argv[1]).substr(std::string_view("--symbolize=").size())), offsets, std::cout);
		}
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

		initialize_interned_string_cache();
		initialize_reporting_storage();
		enable_reporting();
		enable_reporting_printing();

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

		{
			PhaseTimer timer(options->time_phases, "check");
			kick_off_processing(program_info, options);
		}

		if (error_count() > 0) {
			rc = -1;
		}
		// A build package registers targets while it's checked, and is only what builds them
		else if (!build_registry().targets.empty() || !build_registry().steps.empty()) {
			rc = build_targets(program_info, *options, main_alloc) ? 0 : -1;
		}
		else if (!finish_program(options, program_info, mlir_module)) {
			rc = -1;
		}

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
	// A dump if it crashes, for crashes that don't come again when they're looked for
	hemera::install_crash_dump_handler(argc > 0 ? argv[0] : "hemera");
	return hemera::main(argc, argv);
}
