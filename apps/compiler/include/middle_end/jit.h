#pragma once

#include <functional>
#include <memory>
#include <string>

namespace llvm {
	class LLVMContext;
	class Module;
}

namespace hemera {

	/// <summary>
	/// Compiles module for the machine the compiler runs on and calls entry(result) in it
	/// (docs/compilation.md, Compile-Time Execution). entry is a C function taking a pointer. While
	/// the code is still loaded, so anything result points into is still there, calls while_loaded.
	/// Returns false with error set if the module couldn't be compiled or entry wasn't found.
	/// </summary>
	bool run_on_host(std::unique_ptr<llvm::Module> module, std::unique_ptr<llvm::LLVMContext> context,
		const std::string& entry, void* result, const std::function<void()>& while_loaded, std::string& error);

}
