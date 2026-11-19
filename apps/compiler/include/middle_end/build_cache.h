#pragma once

#include <cstdint>
#include <filesystem>
#include <map>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "mlir/IR/BuiltinOps.h"

namespace hemera {

	struct Options;
	struct ProgramInfo;

	/*
	 * What a build package's target's build used of files, for the build cache to tell later whether it would build
	 * the same (docs/compilation.md, The Build Cache): each file compile-time code read or wrote, as std's file
	 * functions tell the compiler (compiler.note_file), and each #file_data's file, in the order they were used.
	 */

	/// <summary>
	/// How a file was used, as base's compiler.FileUse numbers them.
	/// </summary>
	enum class FileUse : uint32_t {
		READ = 0,
		WRITTEN = 1,
		LISTED = 2,
		PROBED = 3,
		UNTRACKED = 4,
	};

	/// <summary>
	/// The files a target's build used. Its threads record into it at once, so it's locked.
	/// </summary>
	struct FileRecord {
		std::mutex mutex;
		// Each path, absolute, and how it was used, in order
		std::vector<std::pair<std::string, FileUse>> uses;
	};

	/// <summary>
	/// The record the calling thread notes files in, or null for none: set for a target's build (set_file_record),
	/// and taken on by the threads its checking starts (front_end.cpp).
	/// </summary>
	FileRecord* file_record();
	void set_file_record(FileRecord* record);

	/// <summary>
	/// Notes that path was used, in the calling thread's record, if it has one. A relative path is taken from the
	/// compiler's current folder, as the code that used it took it.
	/// </summary>
	void note_file_use(const std::string& path, FileUse use);

	/// <summary>
	/// What a target is built from beyond its own files, worked out once for a build package's targets: the
	/// compiler, the build's options, and every file the build package read, with each folder it listed.
	/// </summary>
	std::string build_identity(ProgramInfo* build, const Options& build_options);

	/// <summary>
	/// Each file's bytes' hash, worked out once in a build, as many targets read the same std files. Locked.
	/// </summary>
	struct FileHashes {
		std::mutex mutex;
		std::map<std::string, std::string> hashes;

		// The hash of what's at path: "missing" if nothing, "folder" for a folder, or its bytes' hash
		std::string of(const std::string& path, const Options& reading);
	};

	/// <summary>
	/// What a target's build gives besides its files: whether it was built, the program's path, its outputs' key in
	/// the cache (empty for a check, or a target that's Nothing).
	/// </summary>
	struct TargetResult {
		std::string output;
		std::string outputs_key;
	};

	/// <summary>
	/// The key a target's build is kept under: what it's built from (identity), the target as the build registered
	/// it, and its options. Empty when the compiler can't be read.
	/// </summary>
	std::string target_key(const std::string& identity, const std::string& registered, const Options& options);

	/// <summary>
	/// Whether the target kept under key would build the same now: every file it read as it was. If it would, what
	/// it wrote is written again, its outputs copied into place, and result says what it gave. Returns false, having
	/// written nothing, otherwise.
	/// </summary>
	bool replay_target(const Options& options, const std::string& key, FileHashes& hashes, TargetResult& result);

	/// <summary>
	/// Keeps what a target's build used and made under key: what it read, from its program's files (program) and its
	/// record, what it wrote, as it is now, and result. Nothing is kept for a record with an untracked use.
	/// </summary>
	void keep_target(const Options& options, const std::string& key, ProgramInfo* program, FileRecord& record,
		FileHashes& hashes, const TargetResult& result);

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
