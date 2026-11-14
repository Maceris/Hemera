#include "util/console.h"

#include <cstdlib>

#ifdef _WIN32
#include <Windows.h>
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
#else
	void use_utf8_console() {}

	bool process_code_page_is_utf8() {
		return true;
	}
#endif
}
