#pragma once

#include <filesystem>
#include <string>
#include <vector>

#include "mlir/IR/BuiltinOps.h"

namespace hemera {

	struct Options;

	/*
	 * The build cache (docs/compilation.md, The Build Cache): a program's outputs kept by a hash of everything they're
	 * made from once it's generated, its MLIR, the options lowering, optimizing and linking read, the files they read,
	 * and the compiler itself, so a program generated the same again takes them rather than being optimized and
	 * linked again. Output is deterministic (Deterministic Output), so what's taken is what building would write.
	 */

	/// <summary>
	/// One file a program's build may write, and how it was before the build, to tell whether the build wrote it.
	/// </summary>
	struct CacheOutput {
		std::filesystem::path path;
		bool existed = false;
		std::filesystem::file_time_type written;
	};

	/// <summary>
	/// Whether a program built with options may use the cache: asked for (use_cache), built as far as linking, and
	/// without a fuzzer, whose runs aren't outputs.
	/// </summary>
	bool caches(const Options& options);

	/// <summary>
	/// The key of a program generated into module with options: 32 hexadecimal digits of a 128-bit hash, or empty if
	/// it can't be made, like when the linker script can't be read.
	/// </summary>
	std::string build_cache_key(const Options& options, mlir::ModuleOp module);

	/// <summary>
	/// The files a program's build may write, each as it is now: the program, and its debug file, PDB and import
	/// library where it has them. Taken before building, then given to keep_in_cache.
	/// </summary>
	std::vector<CacheOutput> cache_outputs(const Options& options);

	/// <summary>
	/// Writes the outputs kept under key over the program's, as building it would. Returns false, writing nothing, if
	/// the cache has nothing under key, or what it has can't all be copied, in which case the program is built.
	/// </summary>
	bool reuse_from_cache(const Options& options, const std::string& key);

	/// <summary>
	/// Keeps what the build wrote of outputs (cache_outputs, from before it) under key. Nothing is kept if a file
	/// can't be copied, or another build kept the same key first; either way the build itself is unaffected.
	/// </summary>
	void keep_in_cache(const Options& options, const std::string& key, const std::vector<CacheOutput>& outputs);

	/// <summary>
	/// Removes the entries used longest ago while the cache holds more than its limit, 4 GiB, once a build has kept
	/// something in it; otherwise does nothing.
	/// </summary>
	void trim_build_cache(const Options& options);

	/// <summary>
	/// The folder the cache is in: options.cache_folder, or the user's cache folder's hemera folder
	/// (%LOCALAPPDATA%/Hemera/cache on Windows, $XDG_CACHE_HOME/hemera or ~/.cache/hemera elsewhere).
	/// </summary>
	std::filesystem::path cache_folder_of(const Options& options);
}
