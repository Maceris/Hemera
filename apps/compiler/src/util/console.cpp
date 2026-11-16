#include "util/console.h"

#include <cstdlib>
#include <iostream>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <Windows.h>
#else
#include <unistd.h>
#endif

namespace hemera {

#ifdef _WIN32
	// The console's code page before use_utf8_console, put back when the process ends
	static UINT previous_code_page = 0;

	void use_utf8_console() {
		previous_code_page = GetConsoleOutputCP();
		if (previous_code_page != 0 && previous_code_page != CP_UTF8 && SetConsoleOutputCP(CP_UTF8)) {
			std::atexit([] { SetConsoleOutputCP(previous_code_page); });
		}
	}

	bool process_code_page_is_utf8() {
		return GetACP() == CP_UTF8;
	}

	std::FILE* take_standard_output() {
		std::cout.flush();
		std::fflush(stdout);
		const int output = _fileno(stdout);
		const int error = _fileno(stderr);
		const HANDLE error_handle = GetStdHandle(STD_ERROR_HANDLE);
		if (output < 0 || error < 0 || error_handle == nullptr || error_handle == INVALID_HANDLE_VALUE) {
			return nullptr;
		}
		const int kept = _dup(output);
		if (kept < 0) {
			return nullptr;
		}
		// Binary, so a line ends in \n alone, as it does on the other systems
		_setmode(kept, _O_BINARY);
		std::FILE* stream = _fdopen(kept, "wb");
		if (stream == nullptr) {
			_close(kept);
			return nullptr;
		}
		/*
		 * Every C runtime's descriptor 1 is on the same handle, the one standard output started with, and each _dup2
		 * below closes it. Kept open instead, it can't be closed several times over, which would close whatever handle
		 * took its value in between. It's left as it is: kept above is the stream's own.
		 */
		const HANDLE original = reinterpret_cast<HANDLE>(_get_osfhandle(output));
		if (original != INVALID_HANDLE_VALUE) {
			SetHandleInformation(original, HANDLE_FLAG_PROTECT_FROM_CLOSE, HANDLE_FLAG_PROTECT_FROM_CLOSE);
		}
		/*
		 * The C runtime DLLs already loaded, as system DLLs load ucrtbase.dll, which compile-time code's C calls reach:
		 * each has a descriptor 1 of its own, moved through its own _dup2. One loaded later takes Windows' handle,
		 * moved last.
		 */
		using Dup2 = int(__cdecl*)(int, int);
		for (const char* library : { "ucrtbase.dll", "ucrtbased.dll", "msvcrt.dll" }) {
			const HMODULE loaded = GetModuleHandleA(library);
			const FARPROC found = loaded != nullptr ? GetProcAddress(loaded, "_dup2") : nullptr;
			if (found != nullptr) {
				reinterpret_cast<Dup2>(reinterpret_cast<void*>(found))(2, 1);
			}
		}
		// The compiler's own C runtime's descriptor 1, which stdout and std::cout write through, then Windows' handle
		if (_dup2(error, output) != 0 || !SetStdHandle(STD_OUTPUT_HANDLE, error_handle)) {
			std::fclose(stream);
			return nullptr;
		}
		return stream;
	}
#else
	void use_utf8_console() {}

	bool process_code_page_is_utf8() {
		return true;
	}

	std::FILE* take_standard_output() {
		std::cout.flush();
		std::fflush(stdout);
		const int kept = dup(STDOUT_FILENO);
		if (kept < 0) {
			return nullptr;
		}
		std::FILE* stream = fdopen(kept, "w");
		if (stream == nullptr) {
			close(kept);
			return nullptr;
		}
		if (dup2(STDERR_FILENO, STDOUT_FILENO) < 0) {
			std::fclose(stream);
			return nullptr;
		}
		return stream;
	}
#endif
}
