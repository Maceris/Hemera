#pragma once

#include <cstdint>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "memory/allocator.h"
#include "mlir/IR/BuiltinOps.h"

namespace hemera {

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
	/// A target: compiler.BuildOptions, read from the build package's value.
	/// </summary>
	struct BuildTarget {
		uint32_t node = 0;
		std::string name;
		std::string root;
		std::string output_path;
		std::string entry;
		std::vector<std::pair<std::string, std::string>> settings;
		std::vector<std::pair<std::string, std::string>> package_paths;
		std::string optimization_level;
		bool debug_info = false;
		std::string architecture;
		std::string os;
		std::string output_type;
		std::string cpu;
		std::string cpu_features;
		std::string code_model;
		std::string relocation_model;
		bool red_zone = true;
		bool address_zero_is_memory = false;
		std::string linker_script;
		bool startup_code = true;
		std::string stack_check_failure;
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
	/// generated and linked), then its steps.
	/// </summary>
	/// <returns>Whether everything worked.</returns>
	bool build_targets(ProgramInfo* build, const Options& build_options, Allocator<>& alloc);

	/// <summary>
	/// The options to compile a target with, from what the build package gave and the build's own options.
	/// Reports what's wrong and returns false if they can't be used.
	/// </summary>
	bool target_options(const BuildTarget& target, const Options& build, Options& result);

	/// <summary>
	/// Runs every check the build registered on a target, once it's checked. Returns false if one failed.
	/// </summary>
	bool run_build_checks(ProgramInfo* build, const Options& build_options, ProgramInfo* target, const Options& options);

	/// <summary>
	/// Runs every step the build registered, after what each depends on. Returns false if one failed or couldn't run.
	/// </summary>
	bool run_build_steps(ProgramInfo* build, const Options& build_options);

}
