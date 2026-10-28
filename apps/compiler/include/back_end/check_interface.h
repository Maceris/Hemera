#pragma once

#include <iosfwd>
#include <string>

namespace hemera {
	/*
	 * hemera --check-interface=<old library> <new library>: whether the new typed library can stand in for the old one
	 * (docs/compilation.md, Typed Libraries), from their interface records, read from the files without loading them.
	 * It can if it's built for the same calling convention and Context, and has every export of the old one, by name,
	 * with the same type's schema hash; it may export more. Writes what it found to out, and gives the process's exit
	 * code: 0 if it can, 1 if it can't, saying why, 2 if either can't be read as a typed library.
	 */
	int check_interface(const std::string& old_library, const std::string& new_library, std::ostream& out);
}
