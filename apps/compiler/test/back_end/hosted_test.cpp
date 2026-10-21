#include <cstdlib>
#include <filesystem>
#include <format>
#include <fstream>
#include <iterator>
#include <memory>
#include <sstream>
#include <string>

#include "gtest/gtest.h"

#include "back_end/back_end.h"
#include "back_end/symbolize.h"
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

// A file's bytes, or nothing if it can't be read.
static std::string read_file(const std::filesystem::path& path) {
	std::ifstream file(path, std::ios::binary);
	return std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
}

// What a hosted program wrote, to standard output and to standard error, and where the program is.
struct HostedOutput {
	std::string output;
	std::string error;
	std::string executable;
};

/*
 * A hosted program, compiled the whole way: generated, lowered, assembled, linked with lld-link,
 * then run, with what it writes to standard output and error kept in files. Its main returns 42
 * if everything it checks worked, or the number of the first check that failed.
 */
static HostedOutput run_hosted(std::string_view name, hemera::TargetStackCheck stack_check, int expected_exit_code = 42,
	std::string_view arguments = "", bool debug_info = false, bool generate_all = false, bool valgrind_secrets = false)
{
	HostedOutput result;
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
	options.debug_info = debug_info;
	options.generate_all = generate_all;
	options.valgrind_secrets = valgrind_secrets;
	const std::string object_file = std::format("{}.o", options.output_name);
	const std::string executable = std::format("{}.exe", options.output_name);
	result.executable = executable;
	std::filesystem::remove(executable);

	hemera::kick_off_processing(program_info.get(), &options);
	EXPECT_EQ(hemera::error_count(), 0) << "first error: " << static_cast<int>(hemera::error_list()->front());
	if (hemera::error_count() != 0 || !hemera::generate_program(program_info.get(), options, module)) {
		ADD_FAILURE() << "generating failed";
		return result;
	}

	llvm::LLVMContext llvm_context;
	std::unique_ptr<llvm::Module> lowered = hemera::lower_to_llvm(module, llvm_context, options);
	if (lowered == nullptr) {
		ADD_FAILURE() << "lowering failed";
		return result;
	}

	hemera::BackendLLVM backend;
	EXPECT_TRUE(backend.initialize(options));
	EXPECT_TRUE(backend.generate_object_file(options, *lowered, object_file));
	backend.link(options, object_file);
	backend.destroy();
	EXPECT_EQ(hemera::error_count(), 0);
	if (!std::filesystem::exists(executable)) {
		ADD_FAILURE() << "linking failed";
		return result;
	}

	// On Windows, system gives the program's exit code; cmd takes off the outermost quotes
	const std::filesystem::path output_file = output_folder / "output.txt";
	const std::filesystem::path error_file = output_folder / "error.txt";
	EXPECT_EQ(std::system(std::format("\"\"{}\" {} > \"{}\" 2> \"{}\"\"", executable, arguments, output_file.string(), error_file.string()).c_str()),
		expected_exit_code);
	result.output = read_file(output_file);
	result.error = read_file(error_file);

	module.erase();
	return result;
}

TEST(Hosted, RunsProgram)
{
	run_hosted("hosted", hemera::TargetStackCheck::Off);
}

// Results and parameters too large for registers, through pointers (docs/calling_convention.md, Large Values).
TEST(Hosted, PassesLargeValues)
{
	run_hosted("large_values", hemera::TargetStackCheck::Off);
}

// An object file in a folder that isn't there is reported (E6000), rather than written to a stream that never opened.
TEST(Hosted, ReportsUnwritableOutput)
{
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;
	mlir::MLIRContext context;
	context.loadDialect<mlir::BuiltinDialect>();
	context.loadDialect<hmir::HemeraDialect>();
	mlir::OpBuilder builder(&context);
	mlir::ModuleOp module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "hosted");
	auto program_info = std::make_unique<hemera::ProgramInfo>(&context, &builder, &module);

	const std::filesystem::path missing = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "no_such_folder" / "deeper";
	std::filesystem::remove_all(missing.parent_path());
	hemera::Options options;
	options.input = std::filesystem::canonical(scenario("hosted"));
	options.builtin_paths[hemera::BuiltinPackage::STD] = std::filesystem::canonical(std_folder());
	options.output_name = (missing / "hosted").string();
	hemera::kick_off_processing(program_info.get(), &options);
	ASSERT_EQ(hemera::error_count(), 0);
	ASSERT_TRUE(hemera::generate_program(program_info.get(), options, module));
	llvm::LLVMContext llvm_context;
	std::unique_ptr<llvm::Module> lowered = hemera::lower_to_llvm(module, llvm_context, options);
	ASSERT_NE(lowered, nullptr);

	hemera::BackendLLVM backend;
	ASSERT_TRUE(backend.initialize(options));
	EXPECT_FALSE(backend.generate_object_file(options, *lowered, std::format("{}.o", options.output_name)));
	backend.destroy();
	ASSERT_EQ(hemera::error_count(), 1);
	EXPECT_EQ(hemera::error_list()->front(), hemera::ErrorCode::E6000);
	module.erase();
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
 * one std/fiber pool and three sharing another, and a thread without a pool. Built with morestack,
 * so stacks grow onto segments allocated as they're needed.
 */
TEST(Hosted, RunsThreads)
{
	run_hosted("threads", hemera::TargetStackCheck::Morestack);
}

// The hosted context's allocator, from several threads at once.
TEST(Hosted, AllocatesFromThreads)
{
	run_hosted("heap", hemera::TargetStackCheck::Off);
}

// std/containers, which need no allocator.
TEST(Hosted, UsesContainers)
{
	run_hosted("containers", hemera::TargetStackCheck::Off);
}

// Format string options, in base's output_format and std's text_buffer (docs/format_strings.md).
TEST(Hosted, FormatsWithOptions)
{
	run_hosted("format", hemera::TargetStackCheck::Off);
}

// using on named fields: through pointers, and structs held in place (docs/types.md, Structs).
TEST(Hosted, UsesThroughFields)
{
	run_hosted("using_fields", hemera::TargetStackCheck::Off);
}

// Generic arguments given with mut, and instances given mut becoming read-only (docs/types.md, Mutability).
TEST(Hosted, GivesMutToGenerics)
{
	run_hosted("mut_arguments", hemera::TargetStackCheck::Off);
}

// Owned types: released, moved, taken, shared, in arrays and matches (docs/memory.md, Owned Types).
TEST(Hosted, ReleasesOwners)
{
	run_hosted("owned", hemera::TargetStackCheck::Off);
}

// std/memory's SharedPtr, WeakPtr and LocalPtr (docs/memory.md, Shared Ownership).
TEST(Hosted, SharesOwnership)
{
	run_hosted("shared", hemera::TargetStackCheck::Off);
}

// Optional function types written in place: (fn(n: int) -> int)? (docs/functions.md).
TEST(Hosted, TakesOptionalFunctions)
{
	run_hosted("optional_functions", hemera::TargetStackCheck::Off);
}

// std/crypto's ChaCha20-Poly1305 and AES-256-GCM, with and without AES-NI, against known values.
TEST(Hosted, AuthenticatedEncryption)
{
	run_hosted("aead", hemera::TargetStackCheck::Off);
}

// std/crypto's X25519 and Ed25519 against known values, with bad keys and signatures refused.
TEST(Hosted, Curves)
{
	run_hosted("curves", hemera::TargetStackCheck::Off);
}

// std/crypto's Argon2id against known values, its memory from new_array, and bad parameters refused.
TEST(Hosted, PasswordHashes)
{
	run_hosted("argon2", hemera::TargetStackCheck::Off);
}

/*
 * std/crypto's constant-time functions built with --valgrind-secrets, whose requests to Valgrind do
 * nothing outside it; linux_tests.py runs them under Memcheck.
 */
TEST(Hosted, MarksSecretsForValgrind)
{
	run_hosted("ctgrind", hemera::TargetStackCheck::Off, 42, "", false, false, true);
}

// std/crypto against Project Wycheproof's vectors: X25519, Ed25519, both AEADs, HMAC and HKDF.
TEST(Hosted, Wycheproof)
{
	run_hosted("wycheproof", hemera::TargetStackCheck::Off);
}

// std/crypto's hashes, HMAC and HKDF against known values (std/crypto).
TEST(Hosted, Hashes)
{
	run_hosted("hashes", hemera::TargetStackCheck::Off);
}

// Secrets: constant-time comparisons, choices without a branch, and wiping (docs/memory.md, Secrets).
TEST(Hosted, KeepsSecrets)
{
	run_hosted("secrets", hemera::TargetStackCheck::Off);
}

// for loops with #reverse, last to first (docs/control_flow.md, Range-based for).
TEST(Hosted, ReversesLoops)
{
	run_hosted("reverse_loops", hemera::TargetStackCheck::Off);
}

// Vectors, their intrinsics, and AES-NI and PCLMULQDQ where the CPU has them (docs/types.md, Vectors).
TEST(Hosted, RunsVectors)
{
	run_hosted("vectors", hemera::TargetStackCheck::Off);
}

// Integer literals at the edges of their types' ranges, kept exactly (docs/types.md, Number Formats).
TEST(Hosted, KeepsIntegerLiterals)
{
	run_hosted("integer_ranges", hemera::TargetStackCheck::Off);
}

// std/os's run_process: output, error output, exit codes, a missing program, and quoting.
TEST(Hosted, RunsProcesses)
{
	run_hosted("processes", hemera::TargetStackCheck::Off);
}

// std/maps' HashMap, made with the hash function it uses: std's, and one of its own.
TEST(Hosted, UsesHashMaps)
{
	run_hosted("maps", hemera::TargetStackCheck::Off);
}

/*
 * std/io's printing, to standard output and error, and the standard logger the hosted context starts
 * with: what the program writes is in output.txt and error.txt in its scenario folder.
 */
TEST(Hosted, WritesOutput)
{
	const HostedOutput written = run_hosted("output", hemera::TargetStackCheck::Off);
	EXPECT_EQ(written.output, read_file(scenario("output") / "output.txt"));
	EXPECT_EQ(written.error, read_file(scenario("output") / "error.txt"));
}

// Generics with constraints, used the ways they allow, generated and run.
TEST(Hosted, UsesConstrainedGenerics)
{
	run_hosted("constraints", hemera::TargetStackCheck::Off);
}

// The hosted context's clock and random numbers, from the system.
TEST(Hosted, UsesSystemClockAndRandom)
{
	run_hosted("system", hemera::TargetStackCheck::Off);
}

// Dynamic arrays, from a counting allocator that checks every block is given back.
TEST(Hosted, UsesDynamicArrays)
{
	run_hosted("arrays", hemera::TargetStackCheck::Off);
}

/*
 * std's general-purpose packages: strings, time's calendar, memory's SharedPtr, and logger, whose
 * lines are in output.txt and error.txt in the scenario folder.
 */
TEST(Hosted, UsesStdLibrary)
{
	const HostedOutput written = run_hosted("library", hemera::TargetStackCheck::Off);
	EXPECT_EQ(written.output, read_file(scenario("library") / "output.txt"));
	EXPECT_EQ(written.error, read_file(scenario("library") / "error.txt"));
}

/*
 * std/os: the program's arguments, an environment variable with a character outside ASCII, and
 * files and folders it makes in the current directory and removes again.
 */
TEST(Hosted, UsesFilesAndArguments)
{
	_wputenv_s(L"HEMERA_FILES_TEST", L"h\u00e9llo");
	run_hosted("files", hemera::TargetStackCheck::Off, 42, "alpha \"two words\" \"\"");
	_wputenv_s(L"HEMERA_FILES_TEST", L"");
}

// A failed assertion, with the hosted context's handler: the failure, where it was and the stack, then ASSERTION_EXIT_CODE.
TEST(Hosted, ReportsFailedAssertion)
{
	const HostedOutput written = run_hosted("assertion", hemera::TargetStackCheck::Off, 134);
	EXPECT_TRUE(written.output.empty());
	EXPECT_TRUE(written.error.starts_with("assertion failed: count must be positive\n    at ")) << written.error;
	EXPECT_NE(written.error.find("assertion.hsc:10:18, in check\n    0x"), std::string::npos) << written.error;
}

/*
 * The same with debug info: each frame is named at run time, from the program's table of its
 * functions, and hemera --symbolize turns the offsets into files and lines from its PDB, assert
 * and check inlined into main.
 */
TEST(Hosted, NamesFramesWithDebugInfo)
{
	const HostedOutput written = run_hosted("assertion", hemera::TargetStackCheck::Off, 134, "", true);
	EXPECT_NE(written.error.find("  assertion.main+0x"), std::string::npos) << written.error;
	EXPECT_NE(written.error.find("(hemera --symbolize="), std::string::npos) << written.error;
	// The offsets the trace gave, one a line
	std::vector<std::string> offsets;
	std::istringstream lines(written.error);
	for (std::string line; std::getline(lines, line);) {
		if (line.starts_with("    0x")) {
			offsets.push_back(line.substr(4, line.find_first_of(" \r", 4) - 4));
		}
	}
	ASSERT_FALSE(offsets.empty()) << written.error;
	std::ostringstream symbolized;
	EXPECT_EQ(hemera::symbolize(written.executable, offsets, symbolized), 0);
	const std::string frames = symbolized.str();
	EXPECT_NE(frames.find("runtime.assert at <base>/runtime/assertion.hsc:"), std::string::npos) << frames;
	EXPECT_NE(frames.find("assertion.check at "), std::string::npos) << frames;
	EXPECT_NE(frames.find("assertion.hsc:10, inlined"), std::string::npos) << frames;
	EXPECT_NE(frames.find("assertion.main at "), std::string::npos) << frames;
}

/*
 * Every function base and std declare, used or not, generated for Windows, so what can't be
 * generated yet shows up before anything calls it. The program itself does nothing.
 */
TEST(Hosted, GeneratesEverything)
{
	run_hosted("everything", hemera::TargetStackCheck::Off, 42, "", false, true);
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
