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
#include "back_end/check_interface.h"
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
#include "llvm/Object/COFFImportFile.h"
#include "llvm/Support/Program.h"
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
	std::string_view arguments = "", bool debug_info = false, bool generate_all = false, bool valgrind_secrets = false,
	const std::vector<std::filesystem::path>& library_paths = {}, bool test = false, std::string_view test_filter = "",
	std::string_view fuzz = "", bool model_checked = false, std::string_view cpu = "")
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
	const std::filesystem::path output_folder = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR)
		/ (cpu.empty() ? std::string(name) : std::format("{}_{}", name, cpu));
	std::filesystem::create_directories(output_folder);
	hemera::Options options;
	options.input = std::filesystem::canonical(scenario(name));
	options.builtin_paths[hemera::BuiltinPackage::STD] = std::filesystem::canonical(std_folder());
	options.output_name = (output_folder / name).string();
	options.stack_check = stack_check;
	options.model_checked = model_checked;
	options.cpu = cpu;
	options.debug_info = debug_info;
	options.generate_all = generate_all;
	options.valgrind_secrets = valgrind_secrets;
	options.library_paths = library_paths;
	// hemera --test: the package's #test functions run in place of its entry (docs/testing.md)
	if (test) {
		options.test = true;
		options.entry = std::string(hemera::TEST_ENTRY);
		options.test_filter = test_filter;
	}
	/*
	 * hemera --fuzz: the one test fuzzed from a fixed seed, a few seconds at most, its folder made afresh beside the
	 * program, so a run finds what it finds the same way every time
	 */
	if (!fuzz.empty()) {
		options.test = true;
		options.entry = std::string(hemera::TEST_ENTRY);
		options.fuzz = fuzz;
		options.fuzz_seed = 1;
		options.fuzz_seconds = 60;
		options.fuzz_runs = 2'000'000;
		const std::filesystem::path folder = output_folder / "fuzz";
		std::filesystem::remove_all(folder);
		options.fuzz_folder = folder.generic_string();
	}
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

/*
 * A package built from the folder its sources are in, to output_name, for Windows or Linux, with or without debug info,
 * without running it: whether it built.
 */
static bool build_from(const std::filesystem::path& sources, const std::filesystem::path& output_name, bool linux, bool debug_info)
{
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;
	mlir::MLIRContext context;
	context.loadDialect<mlir::BuiltinDialect>();
	context.loadDialect<hmir::HemeraDialect>();
	mlir::OpBuilder builder(&context);
	mlir::ModuleOp module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "copied");
	auto program_info = std::make_unique<hemera::ProgramInfo>(&context, &builder, &module);

	std::filesystem::create_directories(output_name.parent_path());
	hemera::Options options;
	options.input = std::filesystem::canonical(sources);
	options.builtin_paths[hemera::BuiltinPackage::STD] = std::filesystem::canonical(std_folder());
	options.output_name = output_name.string();
	options.stack_check = hemera::TargetStackCheck::Off;
	options.debug_info = debug_info;
	if (linux) {
		options.os = hemera::OSType::Linux;
		options.object_format = hemera::ObjectFormatType::ELF;
		options.vendor = hemera::VendorType::UnknownVendor;
		options.environment = hemera::EnvironmentType::GNU;
	}
	const std::string object_file = std::format("{}.o", options.output_name);
	hemera::kick_off_processing(program_info.get(), &options);
	if (hemera::error_count() != 0 || !hemera::generate_program(program_info.get(), options, module)) {
		return false;
	}
	llvm::LLVMContext llvm_context;
	std::unique_ptr<llvm::Module> lowered = hemera::lower_to_llvm(module, llvm_context, options);
	if (lowered == nullptr) {
		return false;
	}
	hemera::BackendLLVM backend;
	const bool built = backend.initialize(options) && backend.generate_object_file(options, *lowered, object_file);
	if (built) {
		backend.link(options, object_file);
	}
	backend.destroy();
	module.erase();
	return built && hemera::error_count() == 0;
}

/*
 * docs/compilation.md, Deterministic Output: one package's sources in two folders, at different depths, built to the
 * same output path for Windows and for Linux, with and without debug info, give the same bytes, PDB and all. Its
 * #caller_location and debug info name its files relative to it, and base's and std's as <base>/... and <std>/....
 */
TEST(Hosted, BuildsTheSameWhereverTheSourcesAre)
{
	const std::filesystem::path root = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "sources_anywhere";
	std::filesystem::remove_all(root);
	const std::filesystem::path first = root / "first" / "assertion";
	const std::filesystem::path second = root / "second" / "deeper" / "assertion";
	for (const std::filesystem::path& copy : { first, second }) {
		std::filesystem::create_directories(copy);
		std::filesystem::copy(scenario("assertion"), copy, std::filesystem::copy_options::recursive);
	}
	for (const bool linux : { false, true }) {
		for (const bool debug_info : { false, true }) {
			const std::filesystem::path output = root / "out" / "program";
			const std::filesystem::path program = linux ? output : std::filesystem::path(output.string() + ".exe");
			const std::filesystem::path pdb = std::filesystem::path(output.string() + ".pdb");
			ASSERT_TRUE(build_from(first, output, linux, debug_info));
			const std::string built = read_file(program);
			const std::string debug = !linux && debug_info ? read_file(pdb) : std::string();
			ASSERT_FALSE(built.empty());
			ASSERT_TRUE(build_from(second, output, linux, debug_info));
			EXPECT_TRUE(read_file(program) == built) << (linux ? "Linux" : "Windows") << (debug_info ? ", debug info" : "");
			if (!linux && debug_info) {
				EXPECT_TRUE(read_file(pdb) == debug) << "the PDB differs";
			}
			// Nothing in it says where the sources were
			EXPECT_EQ(built.find("sources_anywhere"), std::string::npos) << (linux ? "Linux" : "Windows") << (debug_info ? ", debug info" : "");
		}
	}
}

/*
 * A program large enough to be generated in parts, with debug info, built twice the same way: the program and
 * its PDB are the same bytes each time, with no link time in them (docs/compilation.md, Generating in Parallel).
 */
TEST(Hosted, BuildsTheSameEveryTime)
{
	const HostedOutput first = run_hosted("curves", hemera::TargetStackCheck::Off, 0, "", true, false, false, {}, true);
	const std::filesystem::path pdb = std::filesystem::path(first.executable).replace_extension(".pdb");
	const std::string program = read_file(first.executable);
	const std::string debug_info = read_file(pdb);
	ASSERT_FALSE(program.empty());
	ASSERT_FALSE(debug_info.empty());
	const HostedOutput second = run_hosted("curves", hemera::TargetStackCheck::Off, 0, "", true, false, false, {}, true);
	EXPECT_TRUE(read_file(second.executable) == program) << "the program differs from the first build";
	EXPECT_TRUE(read_file(pdb) == debug_info) << "its PDB differs from the first build";
}

// Results and parameters too large for registers, through pointers (docs/calling_convention.md, Large Values).
TEST(Hosted, PassesLargeValues)
{
	run_hosted("large_values", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
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
	run_hosted("fibers", hemera::TargetStackCheck::Morestack, 0, "", false, false, false, {}, true);
}

/*
 * Threads on Windows, each with its own carrier block: a plain main thread, two threads sharing
 * one std/fiber pool and three sharing another, and a thread without a pool. Built with morestack,
 * so stacks grow onto segments allocated as they're needed.
 */
TEST(Hosted, RunsThreads)
{
	run_hosted("threads", hemera::TargetStackCheck::Morestack, 0, "", false, false, false, {}, true);
}

/*
 * #foreign functions taking a cstring, optional pointers and a function value C calls back, each one register as C
 * sees them (docs/directives.md, #foreign).
 */
TEST(Hosted, PassesPointersToForeignFunctions)
{
	run_hosted("foreign_pointers", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// The hosted context's allocator, from several threads at once.
TEST(Hosted, AllocatesFromThreads)
{
	run_hosted("heap", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// std/containers, which need no allocator.
TEST(Hosted, UsesContainers)
{
	run_hosted("containers", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Format string options, in base's output_format and std's text_buffer (docs/format_strings.md).
TEST(Hosted, FormatsWithOptions)
{
	run_hosted("format", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// using on named fields: through pointers, and structs held in place (docs/types.md, Structs).
TEST(Hosted, UsesThroughFields)
{
	run_hosted("using_fields", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Generic arguments given with mut, and instances given mut becoming read-only (docs/types.md, Mutability).
TEST(Hosted, GivesMutToGenerics)
{
	run_hosted("mut_arguments", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Owned types: released, moved, taken, shared, in arrays and matches (docs/memory.md, Owned Types).
TEST(Hosted, ReleasesOwners)
{
	run_hosted("owned", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// std/unicode: UTF-8, every case of the UCD's GraphemeBreakTest.txt, the columns clusters take, and normalization
// against NormalizationTest.txt, with case folding.
TEST(Hosted, SplitsGraphemeClusters)
{
	run_hosted("unicode", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// std/locale: numbers, dates and times as each locale writes them, and the locale in effect from the context.
TEST(Hosted, FormatsForLocales)
{
	run_hosted("locale", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

/*
 * Two instances of a generic whose parameter is an optional of a generic alias, each with its own: the instances once
 * shared one about half the time, when an alias was keyed before it knew what it named, so it's built several times.
 */
TEST(Hosted, KeepsGenericAliasArgumentsApart)
{
	for (int build = 0; build < 8; ++build) {
		run_hosted("generic_alias_arguments", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
	}
}

// Arguments and indexes in parentheses, and OS compared with an enum as a generic's argument.
TEST(Hosted, TakesParenthesizedArguments)
{
	run_hosted("parenthesized_arguments", hemera::TargetStackCheck::Off);
}

// #tags(...) and property tests: which tags a run leaves out, and failing cases shrunk to the smallest (docs/testing.md).
TEST(Hosted, RunsPropertyTestsAndTags)
{
	run_hosted("property_tests", hemera::TargetStackCheck::Off);
}

// A model-checked build (docs/testing.md, Model Checking): a lost update found with its schedule, atomic increments and a
// SpinLock that count right under every schedule, weak memory's relaxed message passing found, its released one not, and
// std's own: SharedPtr's counts and the fiber pool's carrier queues. Fibers grow their stacks in segments, as the checker's threads
// are fibers.
TEST(Hosted, ModelChecksAtomics)
{
	const HostedOutput checked = run_hosted("model_checking", hemera::TargetStackCheck::Morestack, 42, "", false, false, false, {}, false, "",
		"", true);
	EXPECT_NE(checked.output.find("found in execution"), std::string::npos) << checked.output;
	EXPECT_NE(checked.output.find("8 tests: 8 passed, 0 failed"), std::string::npos) << checked.output;
}

/*
 * base/intrinsics' float functions and bit counts: built for x86-64's first CPUs, without SSE4.1 and FMA, they round by
 * adding and fuse in software; for x86-64-v3, by instructions, and the software is held to them bit for bit.
 */
TEST(Hosted, RoundsAndFusesFloats)
{
	for (const std::string_view cpu : { "generic", "x86-64-v3" }) {
		const HostedOutput checked = run_hosted("float_intrinsics", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true,
			"", "", false, cpu);
		EXPECT_NE(checked.output.find("27 tests: 27 passed, 0 failed"), std::string::npos) << cpu << ": " << checked.output;
	}
}

// std/linear_algebra: vectors' functions, quaternions, determinants, inverses, and the transforms against where they put points.
TEST(Hosted, UsesLinearAlgebra)
{
	const HostedOutput checked = run_hosted("linear_algebra", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
	EXPECT_NE(checked.output.find("6 tests: 6 passed, 0 failed"), std::string::npos) << checked.output;
}

// Matrices: literals row by row, stored column by column, the products, transpose, identity, casts and draws.
TEST(Hosted, ComputesWithMatrices)
{
	const HostedOutput checked = run_hosted("matrices", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
	EXPECT_NE(checked.output.find("6 tests: 6 passed, 0 failed"), std::string::npos) << checked.output;
}

// Fixed arrays as vectors: element-wise arithmetic, at any length, and swizzles read and assigned through.
TEST(Hosted, DoesArithmeticOnArrays)
{
	const HostedOutput checked = run_hosted("array_arithmetic", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
	EXPECT_NE(checked.output.find("6 tests: 6 passed, 0 failed"), std::string::npos) << checked.output;
}

/*
 * std/math: each function within its ulp bound of references worked out in far more precision (float_math's
 * make_references.py), special values, identities, and parsing correctly rounded, the slow path's halfway cases too;
 * f32's kernels and vectors' lanes; and std/math/fast within its bounds.
 */
TEST(Hosted, ComputesFloatMath)
{
	const HostedOutput checked = run_hosted("float_math", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
	EXPECT_NE(checked.output.find("1333 tests: 1333 passed, 0 failed"), std::string::npos) << checked.output;
}

// std/tls: RFC 8448's Simple 1-RTT Handshake replayed as a client and as a server, and a client and a server in
// memory over each suite, Ed25519, a HelloRetryRequest, KeyUpdate and close_notify; chains refused for each reason, a
// changed record refused, a server without a chain refused, ALPN and exported keys, and random bytes taken without
// harm.
TEST(Hosted, SpeaksTls)
{
	const HostedOutput checked = run_hosted("tls", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
	EXPECT_NE(checked.output.find("10 tests: 10 passed, 0 failed"), std::string::npos) << checked.output;
}

// std/ntp: NTP's timestamps, offset and delay; NTS-KE's request and responses; and NTP with NTS against a server played
// in the test, its answers taken, or refused as forged, changed, for another request, a NAK or unsynchronized.
TEST(Hosted, SpeaksNtpWithNts)
{
	const HostedOutput checked = run_hosted("ntp", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
	EXPECT_NE(checked.output.find("5 tests: 5 passed, 0 failed"), std::string::npos) << checked.output;
}

// The network protocol's policies (std/os/slop_os/network): public addresses, what a policy allows, narrowing, and
// rules by name, which never reach an address that isn't public unless a range names it.
TEST(Hosted, ChecksNetworkPolicies)
{
	const HostedOutput checked = run_hosted("network_policy", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
	EXPECT_NE(checked.output.find("7 tests: 7 passed, 0 failed"), std::string::npos) << checked.output;
}

// Fuzz targets run as property tests: the schema reader's, and one only fuzzing finds a failure in.
TEST(Hosted, RunsFuzzTargetsAsTests)
{
	run_hosted("fuzz_targets", hemera::TargetStackCheck::Off);
}

/*
 * hemera --fuzz: coverage guides the fuzzer to four bytes in a row, which inputs drawn at random would take billions
 * of tries to come on, and the input it reports is shrunk to just them.
 */
TEST(Hosted, FuzzesWithCoverage)
{
	const HostedOutput fuzzed = run_hosted("fuzz_targets", hemera::TargetStackCheck::Off, 1, "", false, false, false, {}, false, "",
		"finds_the_magic");
	EXPECT_NE(fuzzed.output.find("test finds_the_magic ... FAILED"), std::string::npos) << fuzzed.output;
	EXPECT_NE(fuzzed.output.find("note: drew [72, 69, 77, 82]"), std::string::npos) << fuzzed.output;
	EXPECT_NE(fuzzed.output.find("found by fuzzing"), std::string::npos) << fuzzed.output;
}

// #test(CASES): a test run once for each case of a constant array, each its own test (docs/testing.md).
TEST(Hosted, RunsTestsOverCases)
{
	run_hosted("test_cases", hemera::TargetStackCheck::Off);
}

// std/testing: #test functions found through reflection, their assertions, and the runner's report (docs/testing.md).
TEST(Hosted, RunsTests)
{
	run_hosted("testing", hemera::TargetStackCheck::Off);
}

// hemera --test: the same package's tests run by the entry --test adds, reported to standard output, 1 when one failed.
TEST(Hosted, BuildsTestPrograms)
{
	const HostedOutput all = run_hosted("testing", hemera::TargetStackCheck::Off, 1, "", false, false, false, {}, true);
	EXPECT_NE(all.output.find("test reports_failures ... FAILED\n"), std::string::npos) << all.output;
	EXPECT_NE(all.output.find("        expected 13, got 12\n"), std::string::npos) << all.output;
	EXPECT_NE(all.output.find("4 tests: 1 passed, 2 failed, 1 skipped\n"), std::string::npos) << all.output;
	const HostedOutput filtered = run_hosted("testing", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true, "digits");
	EXPECT_EQ(filtered.output, "test parses_digits ... ok\n1 test: 1 passed, 0 failed, 3 filtered out\n");
}

// std/time_zones: TZif data parsed, and offsets from its transitions and its footer's POSIX TZ rule, north and south.
TEST(Hosted, ReadsTimeZones)
{
	run_hosted("time_zones", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/documentation.md: documentation comments read back at compile time, through reflection.
TEST(Hosted, ReadsDocumentation)
{
	run_hosted("documentation", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// std/regex: linear-time matching, leftmost-first, with captures, classes, anchors, repetition and errors.
TEST(Hosted, MatchesRegularExpressions)
{
	run_hosted("regex", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// std/memory's Arena: bumping, giving back the newest block, chunks, marks and resets (docs/memory.md, Allocators).
TEST(Hosted, AllocatesFromArenas)
{
	run_hosted("arena", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// std/memory's SharedPtr, WeakPtr and LocalPtr (docs/memory.md, Shared Ownership).
TEST(Hosted, SharesOwnership)
{
	run_hosted("shared", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Defaults in function types: through names, values, fields and an Allocator (docs/functions.md).
TEST(Hosted, UsesFunctionTypesDefaults)
{
	run_hosted("function_type_defaults", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Optional function types written in place: (fn(n: int) -> int)? (docs/functions.md).
TEST(Hosted, TakesOptionalFunctions)
{
	run_hosted("optional_functions", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Optionals that start zeroed are None: left out of a literal, in an array, declared without a value (docs/types.md, Optional Types).
TEST(Hosted, StartsOptionalsAsNone)
{
	run_hosted("optional_defaults", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Results whose types are in parentheses, like an optional view ((mut u8[])?), alone, named and listed.
TEST(Hosted, ReturnsParenthesizedTypes)
{
	run_hosted("parenthesized_results", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// std/crypto's ChaCha20-Poly1305 and AES-256-GCM, with and without AES-NI, against known values.
TEST(Hosted, AuthenticatedEncryption)
{
	run_hosted("aead", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// std/crypto's X25519 and Ed25519 against known values, with bad keys and signatures refused.
TEST(Hosted, Curves)
{
	run_hosted("curves", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// std/crypto's Argon2id against known values, its memory from new_array, and bad parameters refused.
TEST(Hosted, PasswordHashes)
{
	run_hosted("argon2", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
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
	run_hosted("wycheproof", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

/*
 * std/crypto's primitives for TLS and NTS against Project Wycheproof's vectors: SHA-384's HMAC and
 * HKDF, AES-128-GCM, AES-SIV, P-256's ECDH and ECDSA, P-384's ECDSA, and RSA's signatures.
 */
TEST(Hosted, WycheproofForTls)
{
	run_hosted("wycheproof_tls", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

/*
 * std/crypto's DER, PEM and X.509: chains from a test authority validated to their anchors, bad ones
 * refused for their reasons, and host names matched.
 */
TEST(Hosted, Certificates)
{
	run_hosted("x509", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// std/crypto's hashes, HMAC and HKDF against known values (std/crypto).
TEST(Hosted, Hashes)
{
	run_hosted("hashes", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Secrets: constant-time comparisons, choices without a branch, and wiping (docs/memory.md, Secrets).
TEST(Hosted, KeepsSecrets)
{
	run_hosted("secrets", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// for loops with #reverse, last to first (docs/control_flow.md, Range-based for).
TEST(Hosted, ReversesLoops)
{
	run_hosted("reverse_loops", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// switch with #fall_through, chained, stopped by break, and in a loop (docs/control_flow.md, Switch).
TEST(Hosted, FallsThroughCases)
{
	run_hosted("fall_through", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Endian-specific integers and floats in their own byte order, read and computed as their native types (docs/types.md).
TEST(Hosted, StoresEndianSpecificTypesInTheirOrder)
{
	run_hosted("endian_types", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// A ring linked by relative pointers, copied whole and walked at its new address (docs/types.md, Relative Pointers).
TEST(Hosted, FollowsRelativePointersWhereTheyAre)
{
	run_hosted("relative_pointers", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// A relative pointer set to point at itself, offset 0, fails the store's check (docs/types.md, Relative Pointers).
TEST(Hosted, RefusesARelativePointerToItself)
{
	const HostedOutput written = run_hosted("relative_to_itself", hemera::TargetStackCheck::Off, 134);
	EXPECT_TRUE(written.error.starts_with("assertion failed: a relative pointer is set to point at itself")) << written.error;
	EXPECT_NE(written.error.find("relative_to_itself.hsc:19:"), std::string::npos) << written.error;
}

// match and switch on strings, including #fall_through and case _ (docs/control_flow.md).
TEST(Hosted, MatchesStrings)
{
	run_hosted("string_cases", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// OS and TARGET_ARCH compared where the program runs, and in constants, as #if compares them.
TEST(Hosted, ComparesTargetConstants)
{
	run_hosted("target_constants", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Fixed arrays, structs and tagged unions compared with == and != (docs/types.md, Equality).
TEST(Hosted, ComparesArraysStructsAndUnions)
{
	run_hosted("equality", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Two optionals compared, equal when both hold nothing or both hold equal values (docs/types.md, Optionals).
TEST(Hosted, ComparesOptionals)
{
	run_hosted("optional_comparisons", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Type values with == and types_are_aliases, at compile time and run time (docs/types.md, Comparing Type Values).
TEST(Hosted, ComparesTypeValues)
{
	run_hosted("type_values", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// new's and new_array's values, static arrays of structs and generics' variables start with their fields' defaults, as
// has_defaults says (docs/types.md, Structs).
TEST(Hosted, StartsNewValuesWithDefaults)
{
	run_hosted("new_defaults", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Struct fields defaulting to floats, strings, functions and named constants of any type (docs/types.md, Structs).
TEST(Hosted, DefaultsFieldsToAnyConstant)
{
	run_hosted("field_defaults", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// #run as an array's count, multi-dimensional array types as values, a string literal's members, #file_path.
TEST(Hosted, ComputesConstantSizes)
{
	run_hosted("constant_sizes", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Complex numbers and quaternions: imaginary literals, arithmetic, parts, mixing, casts, std's conjugate and magnitude.
TEST(Hosted, ComputesWithComplexNumbersAndQuaternions)
{
	run_hosted("composites", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Variadic parameters with others after them, split where a value stops fitting (docs/functions.md, Variable Arguments).
TEST(Hosted, SplitsVariadicGroups)
{
	run_hosted("variadic_groups", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// ~ of an untyped constant, worked out in the type it's used as (docs/operators.md).
TEST(Hosted, ComplementsConstantsInTheirType)
{
	run_hosted("complement_constants", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Several names in one declaration, each with its value (docs/functions.md).
TEST(Hosted, DeclaresSeveralNames)
{
	run_hosted("several_names", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Pointers to mut views, the view's own mut kept in parentheses (docs/types.md, Mutability).
TEST(Hosted, PointsToMutViews)
{
	run_hosted("mut_view_pointers", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// #insert and macro calls in generic bodies, expanded for each instance (docs/compilation.md, Code Values).
TEST(Hosted, InsertsIntoGenericBodies)
{
	run_hosted("generic_insertions", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Types declared inside functions, seen in their blocks, each generic instance's its own (docs/types.md).
TEST(Hosted, DeclaresTypesInFunctions)
{
	run_hosted("local_types", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// std/reflection's as_text, numbers written into storage the caller gives.
TEST(Hosted, WritesValuesAsText)
{
	run_hosted("reflection_text", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// #union struct literals, setting the member they name (docs/types.md, Structs).
TEST(Hosted, BuildsUnionLiterals)
{
	run_hosted("union_literals", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// b16, b32 and b64 with !, widened and as conditions (docs/types.md).
TEST(Hosted, NegatesWideBooleans)
{
	run_hosted("wide_booleans", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Multiline strings: their lines joined by newlines, as written (docs/types.md, Strings).
TEST(Hosted, JoinsMultilineStrings)
{
	run_hosted("multiline_strings", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// The memory functions the compiler defines, memcpy, memmove and memset a word at a time where they can, against a
// byte at a time at every alignment.
TEST(Hosted, CopiesAndFillsMemory)
{
	const HostedOutput checked = run_hosted("memory_functions", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
	EXPECT_NE(checked.output.find("3 tests: 3 passed, 0 failed"), std::string::npos) << checked.output;
}

// Vectors, their intrinsics, and AES-NI and PCLMULQDQ where the CPU has them (docs/types.md, Vectors).
TEST(Hosted, RunsVectors)
{
	run_hosted("vectors", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Integer literals at the edges of their types' ranges, kept exactly (docs/types.md, Number Formats).
TEST(Hosted, KeepsIntegerLiterals)
{
	run_hosted("integer_ranges", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// std/os's run_process: output, error output, exit codes, a missing program, and quoting.
TEST(Hosted, RunsProcesses)
{
	run_hosted("processes", hemera::TargetStackCheck::Off);
}

// std/maps' HashMap, made with the hash function it uses: std's, and one of its own.
TEST(Hosted, UsesHashMaps)
{
	run_hosted("maps", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/compilation.md, Code Values: quotes made at compile time, with code, types and literals spliced in.
TEST(Hosted, MakesCodeValues)
{
	run_hosted("code_values", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/compilation.md, Code Values: code made at compile time, put in a body as statements and expressions.
TEST(Hosted, InsertsCode)
{
	run_hosted("inserted_code", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/compilation.md, Code Values: declarations at the top level, fields, variants, members, patterns and cases.
TEST(Hosted, InsertsDeclarations)
{
	run_hosted("inserted_declarations", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// A name two imports declare, which the package's own #insert declares too: its own, whenever the insert is done.
TEST(Hosted, PrefersInsertedOverImports)
{
	run_hosted("inserted_over_imports", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

/*
 * docs/memory.md, Secrets: an optional and a result of a #secret type given back and branched on, or_return's fallback
 * leaving what it gives public, and a #secret type's memory wiped before it's freed.
 */
TEST(Hosted, HoldsSecrets)
{
	run_hosted("secret_holders", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

/*
 * docs/memory.md, Pointers to the Stack: what calls give back, from their bodies: given views of the stack, giving back
 * what's on the heap, kept by an #escaping parameter and returned, through calls that call each other.
 */
TEST(Hosted, ReturnsFromTheHeap)
{
	run_hosted("returns_from_heap", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

/*
 * docs/control_flow.md, Compute Blocks: give from loops and nested blocks, break and continue passing through, what's
 * deferred running as give leaves, or_else's fallback that returns, and a match arm's value.
 */
TEST(Hosted, ComputesValues)
{
	run_hosted("compute_blocks", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/compilation.md, Code Values: #insert among a generic struct's fields and a generic union's variants.
TEST(Hosted, InsertsIntoGenericTypes)
{
	run_hosted("generic_type_insertions", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

/*
 * docs/types.md, Types Declared in Functions: generic types declared in a function, generic or not, using the
 * function's parameters, with two of its instances checked at once.
 */
TEST(Hosted, DeclaresGenericTypesInFunctions)
{
	run_hosted("local_generic_types", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// runtime.in_image: whether an address is in the program's image, from its headers, as a literal is and the heap isn't.
TEST(Hosted, FindsWhatsInTheImage)
{
	run_hosted("in_image", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/types.md, Schemas: std's schema, a type's canonical description and its hash, alike at compile and run time;
// values rendered back by their schemas; and base's BLAKE3 against std's.
TEST(Hosted, HashesSchemas)
{
	run_hosted("schemas", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// std's c_string: a cstring's length and text, looking no further than a limit for its zero.
TEST(Hosted, ReadsCStringsWithinALimit)
{
	run_hosted("c_strings", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/types.md, Structs (#union): constants of #union structs, given members overlapping others.
TEST(Hosted, MakesUnionConstants)
{
	run_hosted("union_constants", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/types.md, Optionals: constants holding optionals of structs, in structs and arrays, which take each Some's shape.
TEST(Hosted, MakesOptionalConstants)
{
	run_hosted("optional_constants", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/operators.md, Optional operators: a member, an element or a chain of them after ?, like f()?.x.
TEST(Hosted, ReadsWhatUnwrapGives)
{
	run_hosted("unwrap_member", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Compile-time code describing a type waits for what's held by value, like a call's Result and its Ok's struct.
TEST(Hosted, DescribesWhenLaidOut)
{
	run_hosted("described_when_laid_out", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

/*
 * An #insert describing a type that points back at the struct it's in: not waited for, and that struct's
 * description, made while it was still being made, is made again once it's whole.
 */
TEST(Hosted, DescribesWhileInserting)
{
	run_hosted("described_while_inserting", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/operators.md, docs/functions.md: members of parentheses, generic variants, shorthands, nested functions.
TEST(Hosted, HandlesExpressionForms)
{
	run_hosted("expression_forms", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/types.md, Mutability: what can be changed only when given mut.
TEST(Hosted, ChangesOnlyWhatsMut)
{
	run_hosted("mutability", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/compilation.md, Code Values: enum members and fields named by #insert in a quote, and reached by one.
TEST(Hosted, InsertsMemberNames)
{
	run_hosted("inserted_member_names", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/compilation.md, Macros: #macro functions called with !, their code put in place hygienically.
TEST(Hosted, ExpandsMacros)
{
	run_hosted("macros", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// docs/compilation.md, Code Values: functions made from a table, with names, parameters and arguments made from data.
TEST(Hosted, GeneratesFunctions)
{
	run_hosted("generated_functions", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
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
	run_hosted("constraints", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// The hosted context's clock and random numbers, from the system.
TEST(Hosted, UsesSystemClockAndRandom)
{
	run_hosted("system", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
}

// Dynamic arrays, from a counting allocator that checks every block is given back.
TEST(Hosted, UsesDynamicArrays)
{
	run_hosted("arrays", hemera::TargetStackCheck::Off, 0, "", false, false, false, {}, true);
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
	// What a run that stopped part way left behind, which the program would find already there
	for (const char* left : { "hemera_files_test", "hemera_directory_test", "hemera_directory_moved" }) {
		std::error_code ignored;
		std::filesystem::remove_all(left, ignored);
	}
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

// A typed library built from the package in sources to output_name, for Windows, in the caller's string cache: whether it built.
static bool build_typed_library(const std::filesystem::path& sources, const std::string& output_name)
{
	hemera::reset_reporting_storage();
	mlir::MLIRContext context;
	context.loadDialect<mlir::BuiltinDialect>();
	context.loadDialect<hmir::HemeraDialect>();
	mlir::OpBuilder builder(&context);
	mlir::ModuleOp module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "library");
	auto program_info = std::make_unique<hemera::ProgramInfo>(&context, &builder, &module);
	hemera::Options options;
	options.input = std::filesystem::canonical(sources);
	options.builtin_paths[hemera::BuiltinPackage::STD] = std::filesystem::canonical(std_folder());
	options.output_name = output_name;
	options.stack_check = hemera::TargetStackCheck::Off;
	options.typed_library = true;
	options.startup_code = false;
	options.relocation_model = hemera::TargetRelocationModel::PositionIndependent;
	const std::string object_file = std::format("{}.o", output_name);
	hemera::kick_off_processing(program_info.get(), &options);
	if (hemera::error_count() != 0 || !hemera::generate_program(program_info.get(), options, module)) {
		return false;
	}
	llvm::LLVMContext llvm_context;
	std::unique_ptr<llvm::Module> lowered = hemera::lower_to_llvm(module, llvm_context, options);
	if (lowered == nullptr) {
		return false;
	}
	hemera::BackendLLVM backend;
	const bool built = backend.initialize(options) && backend.generate_object_file(options, *lowered, object_file);
	if (built) {
		backend.link(options, object_file);
	}
	backend.destroy();
	module.erase();
	return built && hemera::error_count() == 0;
}

/*
 * docs/compilation.md, Typed Libraries: a build package that builds a typed library and a program calling it, which
 * loads the library, checks its imports against the library's interface record and calls through it.
 */
TEST(Build, LinksTypedLibraries)
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

	const std::filesystem::path output_folder = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "typed_libraries";
	std::filesystem::create_directories(output_folder);
	const std::string library = (output_folder / "maths").string();
	const std::string program = (output_folder / "program").string();
	std::filesystem::remove(library + ".dll");
	std::filesystem::remove(program + ".exe");
	hemera::Options options;
	options.input = std::filesystem::canonical(scenario("typed_libraries") / "build");
	options.builtin_paths[hemera::BuiltinPackage::STD] = std::filesystem::canonical(std_folder());
	options.output_name = (output_folder / "build").string();
	options.settings = { { "library", library }, { "program", program } };

	hemera::kick_off_processing(program_info.get(), &options);
	ASSERT_EQ(hemera::error_count(), 0) << "first error: " << static_cast<int>(hemera::error_list()->front());
	ASSERT_EQ(hemera::build_registry().targets.size(), 2u);
	hemera::Allocator<> alloc;
	EXPECT_TRUE(hemera::build_targets(program_info.get(), options, alloc));
	EXPECT_EQ(hemera::error_count(), 0);
	EXPECT_EQ(std::system(std::format("\"{}.exe\"", program).c_str()), 42);

	// Kept, to check the others against
	const std::string first = (output_folder / "first_maths.dll").string();
	std::filesystem::copy_file(library + ".dll", first, std::filesystem::copy_options::overwrite_existing);
	std::ostringstream same;
	EXPECT_EQ(hemera::check_interface(first, library + ".dll", same), 0) << same.str();

	// Built again with one more export: it can stand in, and the program runs with it
	hemera::reset_build_registry();
	ASSERT_TRUE(build_typed_library(scenario("typed_libraries") / "grown_maths", library));
	std::ostringstream grown;
	EXPECT_EQ(hemera::check_interface(first, library + ".dll", grown), 0) << grown.str();
	EXPECT_EQ(std::system(std::format("\"{}.exe\"", program).c_str()), 42);

	// Built again with add's type changed, where the program loads it: refused, naming add, and by the check too
	hemera::reset_build_registry();
	ASSERT_TRUE(build_typed_library(scenario("typed_libraries") / "changed_maths", library));
	std::ostringstream changed;
	EXPECT_EQ(hemera::check_interface(first, library + ".dll", changed), 1);
	EXPECT_NE(changed.str().find("add: its type changed"), std::string::npos) << changed.str();
	const std::filesystem::path error_file = output_folder / "error.txt";
	EXPECT_EQ(std::system(std::format("\"\"{}.exe\" 2> \"{}\"\"", program, error_file.string()).c_str()), 1);
	const std::string error = read_file(error_file);
	EXPECT_NE(error.find("can't bind add from the library maths.dll: it exports it with another type"), std::string::npos) << error;
	module.erase();
}

/*
 * The parallel build scenario's build package, checked, then its targets built with jobs at once, the outputs in
 * build_parallel's output folder: whether the build worked.
 */
static bool build_at_once(uint32_t jobs, bool broken) {
	hemera::reset_reporting_storage();
	hemera::reset_build_registry();

	mlir::MLIRContext context;
	context.loadDialect<mlir::BuiltinDialect>();
	context.loadDialect<hmir::HemeraDialect>();
	mlir::OpBuilder builder(&context);
	mlir::ModuleOp module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "build");
	auto program_info = std::make_unique<hemera::ProgramInfo>(&context, &builder, &module);

	const std::filesystem::path output_folder = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "build_parallel";
	std::filesystem::create_directories(output_folder);
	hemera::Options options;
	options.input = std::filesystem::canonical(scenario("build_parallel") / "build");
	options.output_name = (output_folder / "build").string();
	options.jobs = jobs;
	for (int i = 0; i < 4; ++i) {
		const std::string output = (output_folder / std::format("app_{}", i)).string();
		std::filesystem::remove(output + ".exe");
		options.settings.emplace_back(std::format("output_{}", i), output);
	}
	options.settings.emplace_back("broken", broken ? "yes" : "no");
	options.settings.emplace_back("broken_output", (output_folder / "broken").string());

	hemera::kick_off_processing(program_info.get(), &options);
	if (hemera::error_count() != 0) {
		module.erase();
		return false;
	}
	hemera::Allocator<> alloc;
	const bool built = hemera::build_targets(program_info.get(), options, alloc);
	hemera::reset_build_registry();
	module.erase();
	return built;
}

static std::string parallel_output(int i) {
	return (std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "build_parallel" / std::format("app_{}.exe", i)).string();
}

// docs/compilation.md, Build Packages: targets built at once, each with its own settings.
TEST(Build, BuildsTargetsAtOnce)
{
	StringCacheGuard string_cache;
	ASSERT_TRUE(build_at_once(4, false));
	EXPECT_EQ(hemera::error_count(), 0);
	for (int i = 0; i < 4; ++i) {
		EXPECT_EQ(std::system(std::format("\"{}\"", parallel_output(i)).c_str()), 10 + i) << parallel_output(i);
	}
}

// Built at once, the outputs are what they are built one at a time (docs/compilation.md, Deterministic Output).
TEST(Build, BuildsTheSameAtOnce)
{
	StringCacheGuard string_cache;
	ASSERT_TRUE(build_at_once(1, false));
	std::vector<std::string> one_at_a_time;
	for (int i = 0; i < 4; ++i) {
		std::ifstream file(parallel_output(i), std::ios::binary);
		one_at_a_time.emplace_back(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
	}
	ASSERT_TRUE(build_at_once(4, false));
	for (int i = 0; i < 4; ++i) {
		std::ifstream file(parallel_output(i), std::ios::binary);
		const std::string at_once((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
		EXPECT_FALSE(at_once.empty());
		EXPECT_TRUE(at_once == one_at_a_time[static_cast<size_t>(i)]) << parallel_output(i) << " differs";
	}
}

/*
 * A #foreign function that can't be generated yet, generated apart from any body (--generate-all): its error names the
 * file it's declared in.
 */
TEST(Hosted, ReportsForeignFunctionsInTheirOwnFile)
{
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;

	mlir::MLIRContext context;
	context.loadDialect<mlir::BuiltinDialect>();
	context.loadDialect<hmir::HemeraDialect>();
	mlir::OpBuilder builder(&context);
	mlir::ModuleOp module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "foreign_by_value");
	auto program_info = std::make_unique<hemera::ProgramInfo>(&context, &builder, &module);

	hemera::Options options;
	options.input = std::filesystem::canonical(scenario("foreign_by_value"));
	options.builtin_paths[hemera::BuiltinPackage::STD] = std::filesystem::canonical(std_folder());
	options.output_name = (std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "foreign_by_value").string();
	options.generate_all = true;

	hemera::ReportScope scope;
	hemera::set_report_scope(&scope);
	hemera::kick_off_processing(program_info.get(), &options);
	EXPECT_EQ(hemera::error_count(), 0);
	EXPECT_FALSE(hemera::generate_program(program_info.get(), options, module));
	hemera::set_report_scope(nullptr);
	const std::string reported = scope.output + scope.errors_output;
	EXPECT_NE(reported.find("foreign_by_value.hsc(14,30): error E5002"), std::string::npos) << reported;

	module.erase();
}

/*
 * A folder of its own holding hemera_library_paths.lib, an import library for kernel32's GetCurrentProcessId, which
 * scenarios/library_paths calls: a library the linker finds only when it's told where.
 */
static std::filesystem::path library_paths_folder() {
	const std::filesystem::path folder = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "library_paths" / "libs";
	std::filesystem::create_directories(folder);
	llvm::object::COFFShortExport process_id;
	process_id.Name = "GetCurrentProcessId";
	llvm::Error error = llvm::object::writeImportLibrary("kernel32.dll", (folder / "hemera_library_paths.lib").string(), { process_id },
		llvm::COFF::IMAGE_FILE_MACHINE_AMD64, false);
	EXPECT_FALSE(static_cast<bool>(error)) << llvm::toString(std::move(error));
	return std::filesystem::canonical(folder);
}

// docs/compilation.md, Linking: --library-path's folders, where the linker finds a #library's import library.
TEST(Hosted, FindsLibrariesInLibraryPaths)
{
	run_hosted("library_paths", hemera::TargetStackCheck::Off, 42, "", false, false, false, { library_paths_folder() });
}

// A target's library_paths, which a build package gives, reaching its linker.
TEST(Build, PassesLibraryPathsToTargets)
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

	const std::filesystem::path libraries = library_paths_folder();
	const std::filesystem::path output_folder = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "library_paths" / "build";
	std::filesystem::create_directories(output_folder);
	const std::string output = (output_folder / "library_paths").string();
	std::filesystem::remove(output + ".exe");
	hemera::Options options;
	options.input = std::filesystem::canonical(scenario("library_paths_build") / "build");
	options.output_name = (output_folder / "build").string();
	options.builtin_paths[hemera::BuiltinPackage::STD] = std::filesystem::canonical(std_folder());
	options.settings = { { "output", output }, { "libs", libraries.string() } };

	hemera::kick_off_processing(program_info.get(), &options);
	ASSERT_EQ(hemera::error_count(), 0) << "first error: " << static_cast<int>(hemera::error_list()->front());
	ASSERT_EQ(hemera::build_registry().targets.size(), 1u);
	hemera::Allocator<> alloc;
	EXPECT_TRUE(hemera::build_targets(program_info.get(), options, alloc));
	EXPECT_EQ(hemera::error_count(), 0);
	EXPECT_EQ(std::system(std::format("\"{}.exe\"", output).c_str()), 42);

	hemera::reset_build_registry();
	module.erase();
}

// A target that doesn't check fails the build, reporting its own error once, and the others still build.
TEST(Build, ReportsEachTargetsErrors)
{
	StringCacheGuard string_cache;
	hemera::disable_reporting_printing();
	EXPECT_FALSE(build_at_once(4, true));
	hemera::enable_reporting_printing();
	ASSERT_NE(hemera::error_list(), nullptr);
	EXPECT_EQ(hemera::error_list()->size(), 1u);
	EXPECT_EQ(std::count(hemera::error_list()->begin(), hemera::error_list()->end(), hemera::ErrorCode::E4008), 1);
	for (int i = 0; i < 4; ++i) {
		EXPECT_EQ(std::system(std::format("\"{}\"", parallel_output(i)).c_str()), 10 + i) << parallel_output(i);
	}
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

/*
 * What add_target reads that only shows in what's built: a configuration that doesn't follow the debug info, which the
 * target's code reads; a linker by its path, here lld-link copied under a name of its own, and one by a name not on the
 * PATH, whose target fails to link; and a max_frame_size that a function's frame is larger than, which is its target's
 * error. The other targets still build.
 */
TEST(Build, ReadsTargetOptions)
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

	const std::filesystem::path output_folder = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "target_options";
	std::filesystem::create_directories(output_folder / "linker");
	// lld picks its flavor from its name, which ends in link
	llvm::ErrorOr<std::string> lld_link = llvm::sys::findProgramByName("lld-link");
	ASSERT_TRUE(static_cast<bool>(lld_link));
	const std::filesystem::path linker = output_folder / "linker" / "custom-link.exe";
	std::filesystem::copy_file(*lld_link, linker, std::filesystem::copy_options::overwrite_existing);
	const std::string configured = (output_folder / "configured").string();
	const std::string unlinked = (output_folder / "unlinked").string();
	const std::string framed = (output_folder / "framed").string();
	for (const std::string& output : { configured, unlinked, framed }) {
		std::filesystem::remove(output + ".exe");
	}
	hemera::Options options;
	options.input = std::filesystem::canonical(scenario("target_options") / "build");
	options.output_name = (output_folder / "build").string();
	options.settings = { { "configured_output", configured }, { "unlinked_output", unlinked }, { "framed_output", framed },
		{ "linker", linker.string() } };

	hemera::kick_off_processing(program_info.get(), &options);
	ASSERT_EQ(hemera::error_count(), 0) << "first error: " << static_cast<int>(hemera::error_list()->front());
	ASSERT_EQ(hemera::build_registry().targets.size(), 3u);
	hemera::disable_reporting_printing();
	hemera::Allocator<> alloc;
	EXPECT_FALSE(hemera::build_targets(program_info.get(), options, alloc));
	hemera::enable_reporting_printing();
	ASSERT_NE(hemera::error_list(), nullptr);
	std::string reported;
	for (const std::string& message : *hemera::error_messages()) {
		reported += message + '\n';
	}
	EXPECT_EQ(hemera::error_list()->size(), 2u) << reported;
	EXPECT_EQ(std::count(hemera::error_list()->begin(), hemera::error_list()->end(), hemera::ErrorCode::E7000), 1) << reported;
	EXPECT_EQ(std::count(hemera::error_list()->begin(), hemera::error_list()->end(), hemera::ErrorCode::E6001), 1) << reported;
	EXPECT_NE(reported.find("hemera-no-such-linker isn't on the PATH"), std::string::npos) << reported;
	EXPECT_NE(reported.find("framed.fill's stack frame is"), std::string::npos) << reported;
	EXPECT_NE(reported.find("more than the target's max_frame_size of 16384"), std::string::npos) << reported;
	EXPECT_FALSE(std::filesystem::exists(unlinked + ".exe"));
	EXPECT_FALSE(std::filesystem::exists(framed + ".exe"));
	EXPECT_EQ(std::system(std::format("\"{}.exe\"", configured).c_str()), 42);

	hemera::reset_build_registry();
	module.erase();
}
