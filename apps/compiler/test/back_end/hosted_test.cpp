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
TEST(Hosted, RunsProgram)
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
	const std::filesystem::path output_folder = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "hosted";
	std::filesystem::create_directories(output_folder);
	hemera::Options options;
	options.input = std::filesystem::canonical(scenario("hosted"));
	options.builtin_paths[hemera::BuiltinPackage::STD] = std::filesystem::canonical(std_folder());
	options.output_name = (output_folder / "hosted").string();
	const std::string object_file = std::format("{}.o", options.output_name);
	const std::string executable = std::format("{}.exe", options.output_name);
	std::filesystem::remove(executable);

	hemera::kick_off_processing(program_info.get(), &options);
	ASSERT_EQ(hemera::error_count(), 0);
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

// A call in a constant's value would have to run while compiling, which isn't supported yet: it's reported.
TEST(Hosted, ReportsCallInConstant)
{
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;

	mlir::MLIRContext context;
	context.loadDialect<mlir::BuiltinDialect>();
	context.loadDialect<hmir::HemeraDialect>();
	mlir::OpBuilder builder(&context);
	mlir::ModuleOp module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "constant_call");
	auto program_info = std::make_unique<hemera::ProgramInfo>(&context, &builder, &module);

	hemera::Options options;
	options.input = std::filesystem::canonical(scenario("constant_call"));
	options.output_name = (std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "constant_call").string();

	hemera::kick_off_processing(program_info.get(), &options);
	ASSERT_EQ(hemera::error_count(), 0);
	EXPECT_FALSE(hemera::generate_program(program_info.get(), options, module));
	EXPECT_EQ(hemera::error_count(), 1);

	module.erase();
}
