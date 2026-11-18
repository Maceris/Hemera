#pragma once

#include <cstdint>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "memory/allocator.h"
#include "mlir/IR/BuiltinOps.h"

namespace hemera {

	struct NameIndex;

	struct Options;
	struct ProgramInfo;

	/*
	 * What a build package's compile-time code registers (docs/compilation.md, Build Packages): targets the
	 * compiler builds once the build package is checked, checks it runs on each of them, and steps it runs after.
	 * One build per compilation, so the registry is the process's.
	 */

	/// <summary>
	/// A place in the build package's source, for errors about what was registered there.
	/// </summary>
	struct BuildLocation {
		std::string file;
		uint32_t line = 0;
		uint16_t column = 0;
	};

	/// <summary>
	/// A compiler.LinkedLibrary: another target, by its name, or a package's folder and a library's file.
	/// </summary>
	struct BuildLibrary {
		std::string target;
		std::string root;
		std::string file;
	};

	/// <summary>
	/// A target: compiler.BuildOptions, read from the build package's value.
	/// </summary>
	struct BuildTarget {
		uint32_t node = 0;
		std::string name;
		std::string root;
		std::string output_path;
		std::string entry;
		/// <summary>
		/// BuildOptions.test and test_filter: a program of the root package's #test functions (docs/testing.md).
		/// </summary>
		bool test = false;
		std::string test_filter;
		std::string test_tags;
		uint64_t test_seed = 0;
		bool test_seeded = false;
		uint64_t test_runs = 0;
		std::vector<std::pair<std::string, std::string>> settings;
		std::vector<std::pair<std::string, std::string>> package_paths;
		// BuildOptions.allowed_warnings and denied_warnings: patterns separated by commas, as --allow and --deny take
		std::string allowed_warnings;
		std::string denied_warnings;
		std::vector<BuildLibrary> libraries;
		std::string optimization_level;
		bool debug_info = false;
		std::string configuration;
		std::string architecture;
		std::string os;
		std::string output_type;
		std::string cpu;
		std::string cpu_features;
		std::string code_model;
		std::string relocation_model;
		bool red_zone = true;
		bool address_zero_is_memory = false;
		bool control_flow_integrity = false;
		bool coverage = false;
		bool model_checked = false;
		std::string linker_script;
		std::vector<std::string> library_paths;
		std::string linker;
		bool startup_code = true;
		std::string stack_check_failure;
		uint64_t max_frame_size = 0;
		BuildLocation location;
		// Once built: whether it worked, and the output's path
		bool built = false;
		std::string output;
	};

	/// <summary>
	/// A check or a step: the function, and the wrapper the compiler calls it through, which gives it a carrier
	/// block and the compile-time context. The code stays loaded for the rest of the build.
	/// </summary>
	struct BuildCallback {
		uint32_t node = 0;
		void (*caller)(void*) = nullptr;
		const void* function = nullptr;
		// For a step, what it runs after
		std::vector<uint32_t> after;
		BuildLocation location;
	};

	struct BuildRegistry {
		std::mutex mutex;
		std::vector<BuildTarget> targets;
		std::vector<BuildCallback> checks;
		std::vector<BuildCallback> steps;
		uint32_t next_node = 1;
	};

	BuildRegistry& build_registry();

	/// <summary>
	/// Empties the registry, for compiling another build in the same process, like tests do.
	/// </summary>
	void reset_build_registry();

	/// <summary>
	/// A program that's checked: generated, lowered, assembled and linked, as far as its options say.
	/// </summary>
	/// <returns>Whether it worked.</returns>
	bool finish_program(Options* options, ProgramInfo* program_info, mlir::ModuleOp mlir_module);

	/// <summary>
	/// A build package's targets, each compiled in turn in this process (checked, run through the build's checks,
	/// generated and linked), then its steps. With an index, each target's names are recorded while it's checked, and
	/// added to it once every target is done (--index).
	/// </summary>
	/// <returns>Whether everything worked.</returns>
	bool build_targets(ProgramInfo* build, const Options& build_options, Allocator<>& alloc, NameIndex* index = nullptr);

	/// <summary>
	/// The options to compile a target with, from what the build package gave and the build's own options.
	/// Reports what's wrong and returns false if they can't be used.
	/// </summary>
	bool target_options(const BuildTarget& target, const Options& build, Options& result);

	/// <summary>
	/// Runs every check the build registered on a target, once it's checked. Returns false if one failed.
	/// build_memory is the lock the checks take turns on, as they run the build's code in its memory; describing the
	/// target for them is done beside other targets', taking it only to copy in a value worked out for them. waited,
	/// when given, gets how long it waited for that lock, in milliseconds, for --time-phases' timeline.
	/// </summary>
	bool run_build_checks(ProgramInfo* build, const Options& build_options, ProgramInfo* target, const Options& options,
		std::mutex& build_memory, double* waited = nullptr);

	/// <summary>
	/// Runs every step the build registered, after what each depends on. Returns false if one failed or couldn't run.
	/// </summary>
	bool run_build_steps(ProgramInfo* build, const Options& build_options);

	/*
	 * Each folder compile-time code listed with compiler.subfolders, by its canonical path, and the subfolders it
	 * found, in the order it asked, so a long-lived compiler can tell whether a build would find the same targets
	 * (hemera --serve).
	 */
	std::vector<std::pair<std::string, std::vector<std::string>>> folder_listings();

	// The programs compiler.load_package loaded, which last as long as the compiler does.
	std::vector<ProgramInfo*> loaded_program_list();

	// The same, each with the folder it was loaded from, by its canonical path.
	std::vector<std::pair<std::string, ProgramInfo*>> loaded_package_programs();

	/*
	 * What compile-time code can read of the package load_package loaded from folder, through find_constant: each of
	 * its constants, by name, with its type and value, as text, to compare with another time's. A value is written
	 * as its bytes but for a string's, so one holding a pointer is never the same. Empty if nothing was loaded there.
	 */
	std::string loaded_constants(const std::string& folder);

	/*
	 * The package load_package loaded from folder checked again from the start, reading overlays (--overlay), in
	 * place of the program it had, which is freed, but for its types. Nothing if nothing was loaded there.
	 */
	void reload_package(const std::string& folder, const std::vector<std::pair<std::string, std::string>>& overlays);
}
