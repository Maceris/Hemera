#pragma once

#include <memory>
#include <vector>

#include "cmd_line/options.h"
#include "front_end/info.h"

#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "mlir/IR/BuiltinOps.h"

namespace hemera {

	/// <summary>
	/// Generates the program's code as MLIR (the LLVM dialect, with HMIR's structured control flow),
	/// from the entry function, main, and everything it uses: functions, instances and constants.
	/// Adds an entry point for hosted programs, which gives main a context and returns its exit code.
	/// </summary>
	/// <returns>Whether it worked, having reported anything that didn't.</returns>
	bool generate_program(ProgramInfo* program_info, const Options& options, mlir::ModuleOp module);

	/// <summary>
	/// Runs an evaluation's compile-time code while the program is still being checked
	/// (docs/compilation.md, Compile-Time Execution), keeping its result in the evaluation. If functions or
	/// constants it reaches aren't checked yet, lists them in unchecked and returns false, reporting
	/// nothing; it's run again once they are.
	/// </summary>
	/// <returns>Whether it ran, having reported anything that went wrong.</returns>
	bool run_evaluation(ProgramInfo* program_info, const Options& options, Evaluation& evaluation,
		std::vector<Declaration*>& unchecked);

	/// <summary>
	/// Lowers the generated MLIR: expands defers, lowers HMIR's control flow to branches, and
	/// translates the module to LLVM IR.
	/// </summary>
	/// <returns>The LLVM module, or null after reporting why it failed.</returns>
	std::unique_ptr<llvm::Module> lower_to_llvm(mlir::ModuleOp module, llvm::LLVMContext& context,
		const Options& options);

	/// <summary>
	/// The symbol a hosted program starts at, which the linker is told about.
	/// </summary>
	constexpr const char* HOSTED_ENTRY_SYMBOL = "hemera_entry";
	// What intrinsics.capture_stack_trace calls, defined by lower_to_llvm
	constexpr const char* STACK_WALKER_SYMBOL = "hemera_capture_stack_trace";
	// What intrinsics.capture_fiber_stack_trace calls, defined by lower_to_llvm
	constexpr const char* FIBER_STACK_WALKER_SYMBOL = "hemera.fiber_stack_walker";
	/*
	 * What the walks need from the generated fiber switches and morestack, when a program has them:
	 * the resume loop's return address, morestack's, and a table of offsets (see fiber_walk_table).
	 */
	constexpr const char* FIBER_LOOP_RETURN_SYMBOL = "hemera.fiber_loop_return";
	constexpr const char* MORESTACK_CONTINUE_SYMBOL = "hemera.morestack_continue";
	constexpr const char* FIBER_WALK_SYMBOL = "hemera.fiber_walk";
	/*
	 * The libraries #foreign functions come from: the MLIR module's attribute, then the LLVM module's
	 * named metadata, a string each, which the back end links.
	 */
	constexpr const char* LIBRARIES_ATTRIBUTE = "hmir.libraries";
	constexpr const char* LIBRARIES_METADATA = "hemera.libraries";
}
