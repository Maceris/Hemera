#pragma once

#include <cstdio>

namespace hemera {

	/*
	 * On Windows, makes the console show what's printed as UTF-8, which everything the compiler prints is, until the
	 * process ends, and then puts back what it showed it as before: the console's setting outlives the process, and
	 * belongs to whatever else runs in it. Does nothing elsewhere, or without a console.
	 */
	void use_utf8_console();

	/*
	 * Whether the process's code page, which Windows converts paths and the command line through, is UTF-8: it is when
	 * the program has utf8.manifest, on Windows 10 1903 and later. Always true elsewhere, where they're bytes.
	 */
	bool process_code_page_is_utf8();

	/*
	 * Keeps standard output for the caller alone: returns a stream to where it went, and from here on everything
	 * else written to standard output, by the C and C++ libraries, by Windows' own handle (GetStdHandle) or to
	 * descriptor 1, goes to standard error instead, compile-time code's prints included. Whatever was buffered for
	 * standard output is flushed first. Null, changing nothing, if it can't. Call it once, before other threads
	 * start; the stream stays open until the process ends.
	 */
	std::FILE* take_standard_output();
}
