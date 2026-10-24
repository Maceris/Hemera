#include "middle_end/build.h"

#include <algorithm>
#include <atomic>
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
#include "hmir/hmir_dialect.h"
#include "middle_end/generate.h"
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
		// Generate the program's MLIR, from main and everything it uses
		auto generating = timer("generate");
		if (!generate_program(program_info, *options, mlir_module)) {
			return false;
		}
		generating.reset();
		if (options->build_extent < BuildExtent::LOWER) {
			dump_mlir_to_file(options, &mlir_module);
			return true;
		}
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
		return worked;
	}

	/*
	 * How many targets are built at once without --jobs: a quarter of the logical processors, since each
	 * target's checking and code generation spread across threads of their own too.
	 */
	static size_t default_jobs() {
		return std::max<size_t>(1, std::thread::hardware_concurrency() / 4);
	}

	/*
	 * A build package's targets (docs/compilation.md, Build Packages), several at once (--jobs): each checked,
	 * run through the build's checks, then generated and linked, reporting in a scope of its own, which is
	 * printed whole and in the targets' order. The checks take turns, since they run the build's own code in
	 * its memory. Then the build's steps. Each target's program stays for the rest of the build, since the
	 * build's code may hold its types.
	 */
	bool build_targets(ProgramInfo* build, const Options& build_options, Allocator<>& alloc) {
		BuildRegistry& registry = build_registry();
		const size_t count = registry.targets.size();
		std::vector<std::unique_ptr<ReportScope>> scopes;
		for (size_t i = 0; i < count; ++i) {
			scopes.push_back(std::make_unique<ReportScope>());
		}
		std::vector<char> finished(count, 0);
		std::vector<char> succeeded(count, 0);
		// alloc isn't for several threads, and the build's checks run its own code in its own memory
		std::mutex allocating;
		std::mutex checking;
		std::mutex reporting;
		size_t printed = 0;

		auto build_one = [&](BuildTarget& target) -> bool {
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
			{
				PhaseTimer timer(options->time_phases, std::format("check {}", std::filesystem::path(options->output_name).filename().string()));
				kick_off_processing(program, options);
			}
			if (error_count() != 0) {
				return false;
			}
			{
				std::scoped_lock<std::mutex> lock(checking);
				if (!run_build_checks(build, build_options, program, *options)) {
					return false;
				}
			}
			if (target.output_type == "Nothing") {
				target.built = true;
				return true;
			}
			if (!finish_program(options, program, *mlir_module) || error_count() != 0) {
				return false;
			}
			target.built = true;
			target.output = OSType::Win32 == options->os ? options->output_name + ".exe" : options->output_name;
			return true;
		};

		// Each worker takes the next target, and what's finished is printed in order
		std::atomic<size_t> next{ 0 };
		auto work = [&]() {
			for (;;) {
				const size_t i = next.fetch_add(1);
				if (i >= count) {
					return;
				}
				set_report_scope(scopes[i].get());
				const bool built = build_one(registry.targets[i]);
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
		const bool worked = std::all_of(succeeded.begin(), succeeded.end(), [](char built) { return built != 0; });
		return run_build_steps(build, build_options) && worked && error_count() == 0;
	}

}
