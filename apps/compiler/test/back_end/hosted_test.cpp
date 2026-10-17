#include <cstdlib>
#include <filesystem>
#include <format>
#include <memory>
#include <string>

#include "gtest/gtest.h"

#include "back_end/back_end.h"
#include "cmd_line/options.h"
#include "error/reporting.h"
#include "front_end/front_end.h"
#include "front_end/info.h"
#include "hmir/hmir_dialect.h"
#include "middle_end/build.h"
#include "middle_end/generate.h"
#include "../string_cache_guard.h"

#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "mlir/IR/BuiltinDialect.h"

static std::filesystem::path scenario(std::string_view name) {
	return std::filesystem::path(__FILE__).remove_filename() / "scenarios" / name;
}

// std, in the repository: apps/compiler/test/back_end/hosted_test.cpp
static std::filesystem::path std_folder() {
	return std::filesystem::path(__FILE__).parent_path().parent_path().parent_path().parent_path().parent_path() / "std";
}

/*
 * A hosted program, compiled the whole way: generated, lowered, assembled, linked with lld-link,
 * then run. Its main returns 42 if everything it checks worked, or the number of the first
 * check that failed.
 */
static void run_hosted(std::string_view name, hemera::TargetStackCheck stack_check)
{
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;

	mlir::MLIRContext context;
	context.loadDialect<mlir::BuiltinDialect>();
	context.loadDialect<hmir::HemeraDialect>();
	mlir::OpBuilder builder(&context);
	mlir::ModuleOp module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "hosted");
	auto program_info = std::make_unique<hemera::ProgramInfo>(&context, &builder, &module);

	// In the build folder, which antivirus software is likelier to leave alone than the temp folder
	const std::filesystem::path output_folder = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / name;
	std::filesystem::create_directories(output_folder);
	hemera::Options options;
	options.input = std::filesystem::canonical(scenario(name));
	options.builtin_paths[hemera::BuiltinPackage::STD] = std::filesystem::canonical(std_folder());
	options.output_name = (output_folder / name).string();
	options.stack_check = stack_check;
	const std::string object_file = std::format("{}.o", options.output_name);
	const std::string executable = std::format("{}.exe", options.output_name);
	std::filesystem::remove(executable);

	hemera::kick_off_processing(program_info.get(), &options);
	ASSERT_EQ(hemera::error_count(), 0) << "first error: " << static_cast<int>(hemera::error_list()->front());
	ASSERT_TRUE(hemera::generate_program(program_info.get(), options, module));

	llvm::LLVMContext llvm_context;
	std::unique_ptr<llvm::Module> lowered = hemera::lower_to_llvm(module, llvm_context, options);
	ASSERT_NE(lowered, nullptr);

	hemera::BackendLLVM backend;
	ASSERT_TRUE(backend.initialize(options));
	EXPECT_TRUE(backend.generate_object_file(options, *lowered, object_file));
	backend.link(options, object_file);
	backend.destroy();
	ASSERT_EQ(hemera::error_count(), 0);
	ASSERT_TRUE(std::filesystem::exists(executable));

	// On Windows, system gives the program's exit code
	EXPECT_EQ(std::system(std::format("\"{}\"", executable).c_str()), 42);

	module.erase();
}

TEST(Hosted, RunsProgram)
{
	run_hosted("hosted", hemera::TargetStackCheck::Off);
}

/*
 * Fibers taking turns in a std/fiber pool with one carrier, one of them growing its stack onto segments:
 * on Windows, Hemera's frames chain through rbp like elsewhere (docs/calling_convention.md, Windows x64).
 */
TEST(Hosted, RunsFibers)
{
	run_hosted("fibers", hemera::TargetStackCheck::Morestack);
}

/*
 * Threads on Windows, each with its own carrier block: a plain main thread, two threads sharing
 * one std/fiber pool and three sharing another, and a thread without a pool.
 */
TEST(Hosted, RunsThreads)
{
	run_hosted("threads", hemera::TargetStackCheck::Off);
}

// Compile-time code that gives a pointer: what it points to doesn't exist in the program, so it's reported.
TEST(Hosted, ReportsPointerFromCompileTime)
{
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;

	mlir::MLIRContext context;
	context.loadDialect<mlir::BuiltinDialect>();
	context.loadDialect<hmir::HemeraDialect>();
	mlir::OpBuilder builder(&context);
	mlir::ModuleOp module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "compile_time_pointer");
	auto program_info = std::make_unique<hemera::ProgramInfo>(&context, &builder, &module);

	hemera::Options options;
	options.input = std::filesystem::canonical(scenario("compile_time_pointer"));
	options.output_name = (std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "compile_time_pointer").string();

	hemera::kick_off_processing(program_info.get(), &options);
	ASSERT_EQ(hemera::error_count(), 0);
	EXPECT_FALSE(hemera::generate_program(program_info.get(), options, module));
	EXPECT_EQ(hemera::error_count(), 1);

	module.erase();
}

// A build package (docs/compilation.md, Build Packages): its target compiled in the same process, run through its
// check, linked, and its step run after; then the target is run.
TEST(Build, BuildsTargets)
{
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;
	hemera::reset_build_registry();

	mlir::MLIRContext context;
	context.loadDialect<mlir::BuiltinDialect>();
	context.loadDialect<hmir::HemeraDialect>();
	mlir::OpBuilder builder(&context);
	mlir::ModuleOp module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "build");
	auto program_info = std::make_unique<hemera::ProgramInfo>(&context, &builder, &module);

	const std::filesystem::path output_folder = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "build_package";
	std::filesystem::create_directories(output_folder);
	const std::string output = (output_folder / "app").string();
	std::filesystem::remove(output + ".exe");
	hemera::Options options;
	options.input = std::filesystem::canonical(scenario("build_package") / "build");
	options.output_name = (output_folder / "build").string();
	options.settings = { { "output", output }, { "answer", "42" } };

	hemera::kick_off_processing(program_info.get(), &options);
	ASSERT_EQ(hemera::error_count(), 0) << "first error: " << static_cast<int>(hemera::error_list()->front());
	ASSERT_EQ(hemera::build_registry().targets.size(), 1u);
	hemera::Allocator<> alloc;
	EXPECT_TRUE(hemera::build_targets(program_info.get(), options, alloc));
	EXPECT_EQ(hemera::error_count(), 0);
	// The check's warning and the step's
	EXPECT_EQ(std::count(hemera::warning_list()->begin(), hemera::warning_list()->end(), hemera::WarningCode::W4001), 2);
	EXPECT_EQ(std::system(std::format("\"{}.exe\"", output).c_str()), 42);

	hemera::reset_build_registry();
	module.erase();
}

// A build package that finds what to build: it lists a folder's subfolders, loads each one, and builds the
// packages that say they're programs.
TEST(Build, BuildsDiscoveredTargets)
{
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;
	hemera::reset_build_registry();

	mlir::MLIRContext context;
	context.loadDialect<mlir::BuiltinDialect>();
	context.loadDialect<hmir::HemeraDialect>();
	mlir::OpBuilder builder(&context);
	mlir::ModuleOp module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "build");
	auto program_info = std::make_unique<hemera::ProgramInfo>(&context, &builder, &module);

	const std::filesystem::path output_folder = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "build_discovery";
	std::filesystem::create_directories(output_folder);
	const std::string output = (output_folder / "alpha").string();
	std::filesystem::remove(output + ".exe");
	hemera::Options options;
	options.input = std::filesystem::canonical(scenario("build_discovery") / "build");
	options.output_name = (output_folder / "build").string();
	options.builtin_paths[hemera::BuiltinPackage::STD] = std::filesystem::canonical(std_folder());
	options.settings = { { "output", output } };

	hemera::kick_off_processing(program_info.get(), &options);
	ASSERT_EQ(hemera::error_count(), 0) << "first error: " << static_cast<int>(hemera::error_list()->front());
	ASSERT_EQ(hemera::build_registry().targets.size(), 1u);
	EXPECT_EQ(hemera::build_registry().targets[0].name, "alpha");
	hemera::Allocator<> alloc;
	EXPECT_TRUE(hemera::build_targets(program_info.get(), options, alloc));
	EXPECT_EQ(hemera::error_count(), 0);
	EXPECT_EQ(std::system(std::format("\"{}.exe\"", output).c_str()), 11);

	hemera::reset_build_registry();
	module.erase();
}
