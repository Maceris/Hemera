#pragma once

#include <memory>

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
}
