#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace llvm {
	class LLVMContext;
	class Module;
}

namespace hemera {

	struct TypeInfo;

	/// <summary>
	/// What compile-time code needs from the compiler while it runs (docs/compilation.md, Compile-Time
	/// Execution).
	/// </summary>
	struct CompileTimeRun {
		/// <summary>
		/// Each type descriptor's symbol in the module and the type it describes, so values compile-time code
		/// logs can be formatted.
		/// </summary>
		std::vector<std::pair<std::string, const TypeInfo*>> descriptors;
		/// <summary>
		/// The code being run, where a crash in it is reported.
		/// </summary>
		std::string file_path;
		uint32_t line = 0;
		uint16_t column = 0;
	};

	enum class RunResult {
		RAN,
		// The module couldn't be compiled or entry wasn't found: error says why.
		NOT_COMPILED,
		// It failed an assertion or crashed, which was reported, and was stopped there.
		FAILED,
	};

	/// <summary>
	/// Compiles module for the machine the compiler runs on and calls entry(result) in it. entry is a C
	/// function taking a pointer. While the code is still loaded, so anything result points into is still
	/// there, calls while_loaded. Compile-time code's logs are printed, and its failed assertions and crashes
	/// reported, at run's location if it has none of its own.
	/// </summary>
	RunResult run_on_host(std::unique_ptr<llvm::Module> module, std::unique_ptr<llvm::LLVMContext> context,
		const std::string& entry, void* result, const std::function<void()>& while_loaded, const CompileTimeRun& run,
		std::string& error);

	/// <summary>
	/// The symbols compile-time code calls for runtime.COMPILE_TIME_CONTEXT's services (base/intrinsics).
	/// </summary>
	constexpr const char* COMPILE_TIME_LOG_SYMBOL = "hemera.compile_time_log";
	constexpr const char* COMPILE_TIME_ALLOCATE_SYMBOL = "hemera.compile_time_allocate";
	constexpr const char* COMPILE_TIME_FREE_SYMBOL = "hemera.compile_time_free";
	constexpr const char* COMPILE_TIME_FAIL_SYMBOL = "hemera.compile_time_fail";

}
