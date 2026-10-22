#pragma once

#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <string_view>
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
		/// Symbols the module refers to that are in the compiler: type descriptors and services.
		/// </summary>
		std::vector<std::pair<std::string, const void*>> symbols;
		/// <summary>
		/// Each type descriptor's address and the type it describes, so values compile-time code logs can be
		/// formatted.
		/// </summary>
		const std::map<uintptr_t, const TypeInfo*>* types = nullptr;
		/// <summary>
		/// The code being run, where a crash in it is reported.
		/// </summary>
		std::string file_path;
		uint32_t line = 0;
		uint16_t column = 0;
	};

	/// <summary>
	/// A program's compile-time code once it's compiled: one JIT for every run, each run's module in a library
	/// of its own that links to the earlier ones, so a function an earlier run compiled, like the compile-time
	/// context's logger, isn't compiled again (docs/compilation.md, Compile-Time Execution).
	/// </summary>
	struct CompileTimeLibrary;

	std::shared_ptr<CompileTimeLibrary> new_compile_time_library();

	/// <summary>
	/// Whether an earlier run compiled the function called symbol, so a later one can call it rather than
	/// compiling it again.
	/// </summary>
	bool compile_time_library_has(CompileTimeLibrary& library, const std::string& symbol);

	/// <summary>
	/// What a run's module shares with the library: the functions it defines for later runs, and the ones it
	/// calls that earlier runs defined.
	/// </summary>
	struct CompileTimeLinks {
		CompileTimeLibrary* library = nullptr;
		std::vector<std::string> defines;
		std::vector<std::string> uses;
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
		std::string& error, const CompileTimeLinks& links = {});

	/// <summary>
	/// Keeps the code running now loaded once it finishes, since it registered functions the compiler calls later,
	/// like a build package's checks and steps. For the compiler's services.
	/// </summary>
	void keep_running_code_loaded();

	/// <summary>
	/// Calls a C function in code that was kept loaded, the way run_on_host calls its entry: its logs are printed,
	/// and a failed assertion or a crash is reported and stops it.
	/// </summary>
	RunResult call_loaded(void (*function)(void*), void* argument, const CompileTimeRun& run);

	/// <summary>
	/// format with each % filled in from count any values at params, the way compile-time code's logs are,
	/// for compile-time code that's running.
	/// </summary>
	std::string format_compile_time(std::string_view format, const void* params, size_t count);

	/// <summary>
	/// The symbols compile-time code calls for runtime.COMPILE_TIME_CONTEXT's services (base/intrinsics).
	/// </summary>
	constexpr const char* COMPILE_TIME_LOG_SYMBOL = "hemera.compile_time_log";
	constexpr const char* COMPILE_TIME_ALLOCATE_SYMBOL = "hemera.compile_time_allocate";
	constexpr const char* COMPILE_TIME_FREE_SYMBOL = "hemera.compile_time_free";
	constexpr const char* COMPILE_TIME_FAIL_SYMBOL = "hemera.compile_time_fail";

}
