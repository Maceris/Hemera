#pragma once

#include <filesystem>
#include <string>
#include <system_error>

#include "llvm/Support/ErrorOr.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Program.h"

namespace hemera {

	/*
	 * Find the linker a program is linked with: linker as given, a path or a name. A path is taken as it is. A name is
	 * looked for first in the compiler's own folder, where Hemera's build puts the linkers its own LLVM builds (ld.lld
	 * and lld-link, with Hemera's patches), and then on the PATH. Returns the linker's path, or an error where it's in
	 * neither.
	 */
	inline llvm::ErrorOr<std::string> find_linker(const std::string& linker) {
		if (std::filesystem::path(linker).is_absolute()) {
			return linker;
		}
		static int anchor = 0;
		const std::string executable = llvm::sys::fs::getMainExecutable(nullptr, &anchor);
		if (!executable.empty()) {
			const std::filesystem::path folder = std::filesystem::path(executable).parent_path();
			llvm::ErrorOr<std::string> beside = llvm::sys::findProgramByName(linker, { folder.string() });
			if (beside) {
				return beside;
			}
		}
		return llvm::sys::findProgramByName(linker);
	}

}
