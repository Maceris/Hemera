#include "middle_end/build.h"

#include <format>

#include "back_end/back_end.h"
#include "cmd_line/options.h"
#include "error/reporting.h"
#include "front_end/front_end.h"
#include "front_end/info.h"
#include "hmir/hmir_dialect.h"
#include "middle_end/generate.h"

#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/raw_ostream.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"

namespace hemera {

	/*
	 * A program, checked already: generated, lowered, assembled and linked, as far as its options say. Returns
	 * whether it worked.
	 */
	bool finish_program(Options* options, ProgramInfo* program_info, mlir::ModuleOp mlir_module, Allocator<>& alloc) {
		const std::string object_file_name = std::format("{}.o", options->output_name);
		// Generate the program's MLIR, from main and everything it uses
		if (!generate_program(program_info, *options, mlir_module)) {
			return false;
		}
		if (options->build_extent < BuildExtent::LOWER) {
			dump_mlir_to_file(options, &mlir_module);
			return true;
		}
		llvm::LLVMContext context;
		std::unique_ptr<llvm::Module> lowered = lower_to_llvm(mlir_module, context, *options);
		if (lowered == nullptr || error_count() > 0) {
			return false;
		}
		if (options->build_extent < BuildExtent::ASSEMBLE) {
			std::error_code error;
			llvm::raw_fd_ostream file(std::format("{}.ll", options->output_name), error);
			if (!error) {
				lowered->print(file, nullptr);
			}
			return true;
		}
		Backend* backend = alloc.new_object<BackendLLVM>();
		bool worked = backend->initialize(*options) && backend->generate_object_file(*options, *lowered, object_file_name)
			&& error_count() == 0;
		if (worked && options->build_extent >= BuildExtent::LINK) {
			backend->link(*options, object_file_name);
			worked = error_count() == 0;
		}
		backend->destroy();
		delete backend;
		return worked;
	}

	/*
	 * A build package's targets (docs/compilation.md, Build Packages), each compiled here in turn: checked, run
	 * through the build's checks, then generated and linked. Then the build's steps. Each target's program stays
	 * for the rest of the build, since the build's code may hold its types.
	 */
	bool build_targets(ProgramInfo* build, const Options& build_options, Allocator<>& alloc) {
		BuildRegistry& registry = build_registry();
		bool worked = true;
		for (size_t i = 0; i < registry.targets.size(); ++i) {
			BuildTarget& target = registry.targets[i];
			Options* options = alloc.new_object<Options>();
			if (!target_options(target, build_options, *options)) {
				worked = false;
				continue;
			}
			const size_t errors_before = error_count();
			auto* mlir_context = new mlir::MLIRContext();
			mlir_context->loadDialect<mlir::BuiltinDialect>();
			mlir_context->loadDialect<mlir::func::FuncDialect>();
			mlir_context->loadDialect<hmir::HemeraDialect>();
			auto* mlir_builder = new mlir::OpBuilder(mlir_context);
			auto* mlir_module = new mlir::ModuleOp(mlir::ModuleOp::create(mlir_builder->getUnknownLoc(), options->output_name));
			ProgramInfo* program = alloc.new_object<ProgramInfo>(mlir_context, mlir_builder, mlir_module);
			kick_off_processing(program, options);
			if (error_count() != errors_before || !run_build_checks(build, build_options, program, *options)) {
				worked = false;
				continue;
			}
			if (target.output_type == "Nothing") {
				target.built = true;
				continue;
			}
			if (!finish_program(options, program, *mlir_module, alloc) || error_count() != errors_before) {
				worked = false;
				continue;
			}
			target.built = true;
			target.output = OSType::Win32 == options->os ? options->output_name + ".exe" : options->output_name;
		}
		return run_build_steps(build, build_options) && worked && error_count() == 0;
	}

}
