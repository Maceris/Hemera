#include "util/crash_dump.h"

#if defined(WIN32)
#include <cstdio>
#include <cstring>

#pragma warning(push)
#pragma warning(disable: 5039)
#include <Windows.h>
#include <DbgHelp.h>
#pragma warning(pop)

#pragma comment(lib, "dbghelp.lib")

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/Signals.h"

namespace hemera {

	// LLVM's filter, which prints a stack trace, to run after this one
	static LPTOP_LEVEL_EXCEPTION_FILTER llvm_filter = nullptr;

	/*
	 * The unhandled exception filter: a dump of every thread's stack and registers, and the memory they point at,
	 * which is enough to see where it crashed and with what, without the whole heap; then LLVM's, which prints a
	 * stack trace. The process still ends as it would have, with the exception's code.
	 */
	static LONG WINAPI write_crash_dump(EXCEPTION_POINTERS* exception) {
		char folder[MAX_PATH] = {};
		const DWORD configured = GetEnvironmentVariableA("HEMERA_CRASH_DUMPS", folder, MAX_PATH);
		if (configured == 0 || configured >= MAX_PATH) {
			GetTempPathA(MAX_PATH, folder);
		}
		char path[MAX_PATH + 64] = {};
		const size_t length = std::strlen(folder);
		const char* separator = length > 0 && folder[length - 1] != '\\' && folder[length - 1] != '/' ? "\\" : "";
		std::snprintf(path, sizeof(path), "%s%shemera-crash-%lu.dmp", folder, separator, GetCurrentProcessId());
		const DWORD code = exception != nullptr && exception->ExceptionRecord != nullptr ? exception->ExceptionRecord->ExceptionCode : 0;
		HANDLE file = CreateFileA(path, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
		if (file == INVALID_HANDLE_VALUE) {
			std::fprintf(stderr, "hemera crashed (exception %#lx), and couldn't write a dump at %s\n", code, path);
		}
		else {
			MINIDUMP_EXCEPTION_INFORMATION information{};
			information.ThreadId = GetCurrentThreadId();
			information.ExceptionPointers = exception;
			information.ClientPointers = FALSE;
			const auto kind = static_cast<MINIDUMP_TYPE>(MiniDumpWithIndirectlyReferencedMemory | MiniDumpWithThreadInfo
				| MiniDumpWithUnloadedModules | MiniDumpWithProcessThreadData);
			const BOOL written = MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), file, kind, &information, nullptr, nullptr);
			CloseHandle(file);
			std::fprintf(stderr, written ? "hemera crashed (exception %#lx); a dump is at %s\n"
				: "hemera crashed (exception %#lx), and writing a dump at %s failed\n", code, path);
		}
		std::fflush(stderr);
		return llvm_filter != nullptr ? llvm_filter(exception) : EXCEPTION_CONTINUE_SEARCH;
	}

	/*
	 * LLVM installs its filter the first time it needs one, like when it writes an output file, replacing any
	 * before it without calling it. So it's made to install it now, and this one goes on top.
	 */
	void install_crash_dump_handler(const char* program) {
		llvm::sys::PrintStackTraceOnErrorSignal(program);
		llvm_filter = SetUnhandledExceptionFilter(write_crash_dump);
	}

}

#else

namespace hemera {

	void install_crash_dump_handler(const char* program) {
		(void)program;
	}

}

#endif
