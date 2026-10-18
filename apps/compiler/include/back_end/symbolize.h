#pragma once

#include <iosfwd>
#include <string>
#include <vector>

namespace hemera {
	/*
	 * hemera --symbolize=<program> <offset>...: the functions, files and lines of the return
	 * addresses a stack trace gave, as offsets into the program's image (runtime.image_offset), from
	 * the program's debug info: its PDB for PE/COFF, or its DWARF for ELF. Inlined calls are listed
	 * innermost first. Writes to out, and gives the process's exit code: 0, or 1 if the program
	 * can't be read.
	 */
	int symbolize(const std::string& program, const std::vector<std::string>& offsets, std::ostream& out);
}
