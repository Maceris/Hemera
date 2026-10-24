#pragma once

namespace hemera {

	/// <summary>
	/// On Windows, makes a crash write a minidump before the process ends: into the folder HEMERA_CRASH_DUMPS
	/// names, or the temporary folder, as hemera-crash-&lt;process ID&gt;.dmp, saying where on standard error.
	/// LLVM's stack trace is printed after it. It changes nothing until a crash, and does nothing elsewhere.
	/// program is argv[0].
	/// </summary>
	void install_crash_dump_handler(const char* program);

}
