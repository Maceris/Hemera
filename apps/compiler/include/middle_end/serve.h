#pragma once

namespace hemera {

	/*
	 * hemera --serve [--memory-limit=MB]: a compiler that stays running, checking what it's asked to, for an editor
	 * (docs/compilation.md, A Long-Lived Compiler). Each line of standard input asks for a check, as a JSON object:
	 * {"arguments": [...]}, the arguments a hemera run would take, like --check, --targets, --overlay and the package.
	 * It answers on standard output with the check's diagnostics, a JSON object a line as --diagnostics=json prints
	 * them, then {"done":true,"exit":N,"restart":R}: N the exit code hemera would give, and R whether it should be
	 * started again before the next check, which past the memory limit it should. What else it or compile-time code
	 * prints goes to standard error.
	 *
	 * The first check of a build package keeps the build's state: its program, the programs compiler.load_package
	 * loaded, and the targets it registered. A later check whose arguments are the same, but for --targets, --overlay,
	 * --index and --diagnostics, and for which every file those programs read has the same bytes and every folder
	 * compiler.subfolders listed lists the same, reuses it: the build isn't checked again, its diagnostics are reported
	 * again, and only its targets are checked. Any other check is answered {"done":false,"restart":true}, without
	 * running, to be asked again of a compiler started afresh. It returns when standard input ends: 0, or 3 after a
	 * restart is asked for.
	 */
	int serve(int argc, char* argv[]);
}
