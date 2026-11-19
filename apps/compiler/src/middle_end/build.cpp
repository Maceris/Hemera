#include "middle_end/build.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <filesystem>
#include <format>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

#include "back_end/back_end.h"
#include "cmd_line/options.h"
#include "error/reporting.h"
#include "front_end/front_end.h"
#include "front_end/info.h"
#include "front_end/name_index.h"
#include "hmir/hmir_dialect.h"
#include "middle_end/build_cache.h"
#include "middle_end/generate.h"
#include "middle_end/reflection.h"
#include "util/phase_timer.h"

#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/raw_ostream.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"

namespace hemera {

	/*
	 * A program, checked already: generated, lowered, assembled and linked, as far as its options say. Returns
	 * whether it worked.
	 */
	bool finish_program(Options* options, ProgramInfo* program_info, mlir::ModuleOp mlir_module) {
		const std::string object_file_name = std::format("{}.o", options->output_name);
		const std::string program = std::filesystem::path(options->output_name).filename().string();
		auto timer = [&](const char* phase) { return std::make_unique<PhaseTimer>(options->time_phases, std::format("{} {}", phase, program)); };
		/*
		 * A check reaches what generating would and runs what it would at compile time, without generating it; a
		 * typed library, whose interface takes its types' hashes, and --generate-all, are generated as for a build
		 */
		if (BuildExtent::CHECK == options->build_extent && !options->typed_library && !options->generate_all) {
			auto reaching = timer("reach");
			return reach_program(program_info, *options, mlir_module);
		}
		// Generate the program's MLIR, from main and everything it uses
		auto generating = timer("generate");
		if (!generate_program(program_info, *options, mlir_module)) {
			return false;
		}
		generating.reset();
		if (options->build_extent < BuildExtent::LOWER) {
			if (BuildExtent::COMPILE == options->build_extent) {
				dump_mlir_to_file(options, &mlir_module);
			}
			return true;
		}
		/*
		 * A program generated as one built before, with the same options and compiler, takes that one's outputs from
		 * the build cache (docs/compilation.md, The Build Cache) rather than being lowered, optimized and linked again
		 */
		std::string cache_key;
		std::vector<CacheOutput> cache_before;
		if (caches(*options)) {
			{
				PhaseTimer looking(options->time_phases, std::format("find {} in the build cache", program));
				cache_key = build_cache_key(*options, mlir_module);
			}
			// Timed only when it's taken, so --time-phases says which programs were
			const auto taking = std::chrono::steady_clock::now();
			if (!cache_key.empty() && reuse_from_cache(*options, cache_key)) {
				if (options->time_phases) {
					const auto took = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - taking);
					report_to_standard_error(std::format("phase take {} from the build cache: {} ms", program, took.count()));
				}
				return true;
			}
			cache_before = cache_outputs(*options);
		}
		// What's reported from here on, which taking the outputs from the cache another time wouldn't report
		const size_t reported_before = error_count() + warning_count();
		llvm::LLVMContext context;
		auto lowering = timer("lower");
		std::unique_ptr<llvm::Module> lowered = lower_to_llvm(mlir_module, context, *options);
		lowering.reset();
		if (lowered == nullptr || error_count() > 0) {
			return false;
		}
		if (options->build_extent < BuildExtent::ASSEMBLE) {
			std::error_code error;
			const std::string path = std::format("{}.ll", options->output_name);
			llvm::raw_fd_ostream file(path, error);
			if (error) {
				report_error(ErrorCode::E6000, path, 0, 0, error.message());
				return false;
			}
			lowered->print(file, nullptr);
			return true;
		}
		auto backend = std::make_unique<BackendLLVM>();
		auto optimizing = timer("optimize and assemble");
		bool worked = backend->initialize(*options) && backend->generate_object_file(*options, *lowered, object_file_name)
			&& error_count() == 0;
		optimizing.reset();
		if (worked && options->build_extent >= BuildExtent::LINK) {
			auto linking = timer("link");
			backend->link(*options, object_file_name);
			worked = error_count() == 0;
		}
		backend->destroy();
		if (worked && !cache_key.empty() && error_count() + warning_count() == reported_before) {
			PhaseTimer keeping(options->time_phases, std::format("keep {} in the build cache", program));
			keep_in_cache(*options, cache_key, cache_before);
		}
		return worked;
	}

	/*
	 * --time-phases' timeline of one target, in milliseconds since the build's targets began, printed when it's done,
	 * like "timeline kernel.elf: started 0 ms, checked 3120 ms, waited 410 ms for the build's lock, through the build's
	 * checks 3870 ms, done 6950 ms". What it didn't reach, like the checks after an error, is left out.
	 */
	struct Timeline {
		std::string target;
		bool enabled;
		std::chrono::steady_clock::time_point began;
		double started;
		double checked = -1;
		double waited = 0;
		double through_checks = -1;

		Timeline(std::string target_, bool enabled_, std::chrono::steady_clock::time_point began_)
			: target{ std::move(target_) }
			, enabled{ enabled_ }
			, began{ began_ }
			, started{ now() }
		{}

		Timeline(const Timeline&) = delete;
		Timeline& operator=(const Timeline&) = delete;

		// Milliseconds since the build's targets began.
		double now() const {
			return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
		}

		~Timeline() {
			if (!enabled) {
				return;
			}
			std::string line = std::format("timeline {}: started {:.0f} ms", target, started);
			if (checked >= 0) {
				line += std::format(", checked {:.0f} ms", checked);
			}
			if (through_checks >= 0) {
				line += std::format(", waited {:.0f} ms for the build's lock, through the build's checks {:.0f} ms", waited, through_checks);
			}
			line += std::format(", done {:.0f} ms", now());
			report_to_standard_error(line);
		}
	};

	/*
	 * How many targets are built at once without --jobs: half the logical processors. Each target's checking spreads
	 * across threads of its own too, but waits on itself enough that more targets at once keep the processors busier:
	 * a check of a large build took a sixth less time than with a quarter, and no more memory, as every target's
	 * program is kept until the end either way.
	 */
	static size_t default_jobs() {
		return std::max<size_t>(1, std::thread::hardware_concurrency() / 2);
	}

	/*
	 * A build package's targets (docs/compilation.md, Build Packages), several at once (--jobs): each checked,
	 * run through the build's checks, then generated and linked, reporting in a scope of its own, which is
	 * printed whole and in the targets' order. The checks take turns, since they run the build's own code in
	 * its memory, but each target's constants, which describing it for them takes, are worked out beside
	 * others'. Then the build's steps. Each target's program stays for the rest of the build, since the build's
	 * code may hold its types.
	 */
	bool build_targets(ProgramInfo* build, const Options& build_options, Allocator<>& alloc, NameIndex* index) {
		BuildRegistry& registry = build_registry();
		const size_t count = registry.targets.size();
		std::vector<std::unique_ptr<ReportScope>> scopes;
		for (size_t i = 0; i < count; ++i) {
			scopes.push_back(std::make_unique<ReportScope>());
			// Each diagnostic says which target found it, for a tool that keeps them by target, like an editor's
			scopes.back()->target = registry.targets[i].name;
		}
		std::vector<char> finished(count, 0);
		std::vector<char> succeeded(count, 0);
		// alloc isn't for several threads, and the build's checks run its own code in its own memory
		std::mutex allocating;
		std::mutex checking;
		std::mutex reporting;
		// Each target's program and options, for its part of the name index once they're all done, and what it was made with
		std::vector<ProgramInfo*> programs(count, nullptr);
		std::vector<Options*> programs_options(count, nullptr);
		struct Made {
			mlir::MLIRContext* context = nullptr;
			mlir::OpBuilder* builder = nullptr;
			mlir::ModuleOp* module = nullptr;
		};
		std::vector<Made> made(count);
		// What a target did last time is forgotten, as a long-lived compiler builds them again (hemera --serve)
		for (BuildTarget& target : registry.targets) {
			target.built = false;
			target.output.clear();
		}
		size_t printed = 0;
		const auto began = std::chrono::steady_clock::now();

		auto build_one = [&](size_t i, BuildTarget& target) -> bool {
			Options* options = nullptr;
			ProgramInfo* program = nullptr;
			mlir::ModuleOp* mlir_module = nullptr;
			{
				std::scoped_lock<std::mutex> lock(allocating);
				options = alloc.new_object<Options>();
			}
			if (!target_options(target, build_options, *options)) {
				return false;
			}
			auto* mlir_context = new mlir::MLIRContext();
			mlir_context->loadDialect<mlir::BuiltinDialect>();
			mlir_context->loadDialect<mlir::func::FuncDialect>();
			mlir_context->loadDialect<hmir::HemeraDialect>();
			auto* mlir_builder = new mlir::OpBuilder(mlir_context);
			mlir_module = new mlir::ModuleOp(mlir::ModuleOp::create(mlir_builder->getUnknownLoc(), options->output_name));
			{
				std::scoped_lock<std::mutex> lock(allocating);
				program = alloc.new_object<ProgramInfo>(mlir_context, mlir_builder, mlir_module);
			}
			programs[i] = program;
			programs_options[i] = options;
			made[i] = Made{ mlir_context, mlir_builder, mlir_module };
			// --time-phases' timeline: when the target started, was checked, through the build's checks, and done
			Timeline timeline(std::filesystem::path(options->output_name).filename().string(), options->time_phases, began);
			{
				PhaseTimer timer(options->time_phases, std::format("check {}", std::filesystem::path(options->output_name).filename().string()));
				if (index != nullptr) {
					program->name_uses = std::make_shared<NameUses>();
				}
				kick_off_processing(program, options);
			}
			timeline.checked = timeline.now();
			if (error_count() != 0) {
				return false;
			}
			// It takes the lock on the build's memory itself, for all but working out the target's constants
			const bool passed = run_build_checks(build, build_options, program, *options, checking, &timeline.waited);
			timeline.through_checks = timeline.now();
			if (!passed) {
				return false;
			}
			if (target.output_type == "Nothing") {
				target.built = true;
				return true;
			}
			if (!finish_program(options, program, *mlir_module) || error_count() != 0) {
				return false;
			}
			target.built = true;
			target.output = OSType::Win32 == options->os ? options->output_name + (options->typed_library ? ".dll" : ".exe") : options->output_name;
			return true;
		};

		// --targets: only those named, each one the build has
		const std::vector<std::string>& only = build_options.only_targets;
		for (const std::string& name : only) {
			if (std::none_of(registry.targets.begin(), registry.targets.end(), [&](const BuildTarget& target) { return target.name == name; })) {
				report_error(ErrorCode::E4047, build_options.input.string(), 0, 0, std::format("the build has no target {}", name));
				return false;
			}
		}
		const auto chosen = [&](const BuildTarget& target) {
			return only.empty() || std::find(only.begin(), only.end(), target.name) != only.end();
		};

		/*
		 * What the build's memory gets from here on, describing targets to its checks, goes once they're done, for
		 * a compiler that checks them again (hemera --serve): otherwise it would hold every check's
		 */
		CompileTimeData::Mark build_memory_mark;
		if (build_options.free_targets) {
			build_memory_mark = compile_time_data(build).mark();
		}

		// Each worker takes the next target, and what's finished is printed in order
		std::atomic<size_t> next{ 0 };
		auto work = [&]() {
			for (;;) {
				const size_t i = next.fetch_add(1);
				if (i >= count) {
					return;
				}
				set_report_scope(scopes[i].get());
				const bool built = !chosen(registry.targets[i]) || build_one(i, registry.targets[i]);
				set_report_scope(nullptr);
				std::scoped_lock<std::mutex> lock(reporting);
				succeeded[i] = built;
				finished[i] = 1;
				while (printed < count && finished[printed]) {
					print_report_scope(*scopes[printed]);
					++printed;
				}
			}
		};
		const size_t jobs = std::clamp<size_t>(build_options.jobs != 0 ? build_options.jobs : default_jobs(), 1, std::max<size_t>(count, 1));
		if (jobs == 1) {
			work();
		}
		else {
			std::vector<std::thread> workers;
			for (size_t i = 0; i < jobs; ++i) {
				workers.emplace_back(work);
			}
			for (std::thread& worker : workers) {
				worker.join();
			}
		}
		if (index != nullptr) {
			for (size_t i = 0; i < count; ++i) {
				if (programs[i] != nullptr) {
					add_to_index(*index, *programs[i], *programs_options[i]);
					add_readers(*index, *programs[i], registry.targets[i].name);
				}
			}
		}
		const bool worked = std::all_of(succeeded.begin(), succeeded.end(), [](char built) { return built != 0; });
		// A check (--check) stops at its targets, as does building some of them: the steps would use them all
		if (BuildExtent::CHECK == build_options.build_extent || !only.empty()) {
			const bool built = worked && error_count() == 0;
			/*
			 * Each target's program freed, for a compiler that goes on to check them again (hemera --serve), with
			 * what the build's memory got for them: its descriptions of their types and the constants worked out
			 * for them, kept by their addresses, which later programs may reuse.
			 */
			if (build_options.free_targets) {
				PhaseTimer freeing(build_options.time_phases, "free the targets");
				CompileTimeData& data = compile_time_data(build);
				{
					std::scoped_lock<std::mutex> lock(data.constant_values_mutex);
					data.constant_values.clear();
				}
				data.release(build_memory_mark);
				/*
				 * Each program on its own memory and MLIR context, so they're torn down on every processor, as nothing
				 * else runs now, only giving the memory back to alloc taking turns: one after another, this was seconds
				 */
				const size_t freeing_jobs = std::clamp<size_t>(std::thread::hardware_concurrency(), 1, std::max<size_t>(count, 1));
				std::atomic<size_t> next_freed{ 0 };
				auto free_some = [&]() {
					for (;;) {
						const size_t i = next_freed.fetch_add(1);
						if (i >= count) {
							return;
						}
						if (programs[i] == nullptr) {
							continue;
						}
						std::destroy_at(programs[i]);
						std::destroy_at(programs_options[i]);
						made[i].module->erase();
						delete made[i].module;
						delete made[i].builder;
						delete made[i].context;
						std::scoped_lock<std::mutex> lock(allocating);
						alloc.deallocate_object(programs[i]);
						alloc.deallocate_object(programs_options[i]);
					}
				};
				std::vector<std::thread> freeing_workers;
				for (size_t i = 1; i < freeing_jobs; ++i) {
					freeing_workers.emplace_back(free_some);
				}
				free_some();
				for (std::thread& worker : freeing_workers) {
					worker.join();
				}
			}
			return built;
		}
		return run_build_steps(build, build_options) && worked && error_count() == 0;
	}

}
