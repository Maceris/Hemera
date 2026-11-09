#include <filesystem>
#include <format>
#include <fstream>
#include <functional>
#include <iterator>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <vector>

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
#include "llvm/Object/ELFObjectFile.h"
#include "llvm/Object/ObjectFile.h"
#include "mlir/IR/BuiltinDialect.h"

static std::filesystem::path scenario(std::string_view name) {
	return std::filesystem::path(__FILE__).remove_filename() / "scenarios" / name;
}

// Compiles a scenario the whole way to an ELF at output, with the options configure sets.
static void build_elf(const std::filesystem::path& output, std::string_view name, bool generate_all,
	const std::function<void(hemera::Options&)>& configure) {
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;

	mlir::MLIRContext context;
	context.loadDialect<mlir::BuiltinDialect>();
	context.loadDialect<hmir::HemeraDialect>();
	mlir::OpBuilder builder(&context);
	mlir::ModuleOp module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "freestanding");
	auto program_info = std::make_unique<hemera::ProgramInfo>(&context, &builder, &module);

	std::filesystem::create_directories(output.parent_path());
	hemera::Options options;
	options.input = std::filesystem::canonical(scenario(name));
	// std, in the repository: apps/compiler/test/back_end/freestanding_test.cpp
	options.builtin_paths[hemera::BuiltinPackage::STD] = std::filesystem::canonical(
		std::filesystem::path(__FILE__).parent_path().parent_path().parent_path().parent_path().parent_path() / "std");
	options.generate_all = generate_all;
	options.output_name = output.string();
	options.vendor = hemera::VendorType::UnknownVendor;
	options.environment = hemera::EnvironmentType::UnknownEnvironment;
	options.object_format = hemera::ObjectFormatType::ELF;
	configure(options);
	const std::string object_file = std::format("{}.o", options.output_name);
	std::filesystem::remove(options.output_name);

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
	module.erase();
}

/*
 * Compiles the freestanding scenario the whole way to an ELF at output, the way SlopOS builds a
 * kernel: no startup code, no red zone, no SIMD, stack checks that trap, position-independent,
 * placed by a linker script.
 */
static void build_kernel(const std::filesystem::path& output, hemera::TargetStackCheck stack_check = hemera::TargetStackCheck::Trap,
	std::string_view name = "freestanding", bool generate_all = false) {
	build_elf(output, name, generate_all, [&](hemera::Options& options) {
		options.os = hemera::OSType::UnknownOS;
		options.cpu_features = "-mmx,-sse,-sse2,-avx,-avx2,+soft-float";
		options.red_zone = false;
		options.stack_check = stack_check;
		options.startup_code = false;
		options.entry = "kernel_entry";
		options.linker_script = std::filesystem::canonical(scenario("freestanding") / "linker.ld");
	});
}

static std::string bytes_of(const std::filesystem::path& file) {
	std::ifstream stream(file, std::ios::binary);
	return std::string(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
}

/*
 * A UEFI application's calls through .c function values, like the firmware's services, go through the shim for foreign
 * code, which follows UEFI's C convention, Microsoft's x64 one: five arguments leave one on the stack, above 32 bytes of
 * shadow space (docs/calling_convention.md, Calls to Foreign Code). System V's would leave none, and no shadow space for
 * the firmware to write its home area into. Running one takes firmware, like OVMF under QEMU; here the shim is checked.
 */
TEST(Freestanding, CallsUEFIFunctionValuesWithMicrosoftsConvention)
{
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;

	mlir::MLIRContext context;
	context.loadDialect<mlir::BuiltinDialect>();
	context.loadDialect<hmir::HemeraDialect>();
	mlir::OpBuilder builder(&context);
	mlir::ModuleOp module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "uefi_function_values");
	auto program_info = std::make_unique<hemera::ProgramInfo>(&context, &builder, &module);

	hemera::Options options;
	options.input = std::filesystem::canonical(scenario("uefi_function_values"));
	options.builtin_paths[hemera::BuiltinPackage::STD] = std::filesystem::canonical(
		std::filesystem::path(__FILE__).parent_path().parent_path().parent_path().parent_path().parent_path() / "std");
	options.output_name = (std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "uefi_function_values" / "uefi_function_values").string();
	options.os = hemera::OSType::UEFI;
	options.object_format = hemera::ObjectFormatType::COFF;
	options.vendor = hemera::VendorType::UnknownVendor;
	options.environment = hemera::EnvironmentType::UnknownEnvironment;
	options.generate_all = true;

	hemera::kick_off_processing(program_info.get(), &options);
	ASSERT_EQ(hemera::error_count(), 0);
	ASSERT_TRUE(hemera::generate_program(program_info.get(), options, module));
	llvm::LLVMContext llvm_context;
	std::unique_ptr<llvm::Module> lowered = hemera::lower_to_llvm(module, llvm_context, options);
	ASSERT_NE(lowered, nullptr);
	const std::string assembly = lowered->getModuleInlineAsm();
	const size_t shim = assembly.find("hemera.foreign_indirect.1:");
	ASSERT_NE(shim, std::string::npos) << assembly;
	const std::string body = assembly.substr(shim, assembly.find("retq", shim) - shim);
	// 32 bytes of shadow space and the stack argument, and the argument copied above the shadow space
	EXPECT_NE(body.find("subq $48, %rsp"), std::string::npos) << body;
	EXPECT_NE(body.find("movq 48(%rbp), %rax"), std::string::npos) << body;
	EXPECT_NE(body.find("movq %rax, 32(%rsp)"), std::string::npos) << body;
	module.erase();
}

/*
 * A freestanding kernel. Booting it takes Limine and QEMU, which SlopOS's harness has; here the ELF
 * is checked: its entry, and Limine's requests in their sections.
 */
TEST(Freestanding, BuildsKernel)
{
	const std::filesystem::path output = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "freestanding" / "kernel.elf";
	build_kernel(output);
	if (testing::Test::HasFatalFailure()) {
		return;
	}

	auto binary = llvm::object::ObjectFile::createObjectFile(output.string());
	ASSERT_TRUE(static_cast<bool>(binary)) << llvm::toString(binary.takeError());
	llvm::object::ObjectFile& elf = *binary->getBinary();
	EXPECT_TRUE(elf.isELF());
	std::set<std::string> sections;
	for (const llvm::object::SectionRef& section : elf.sections()) {
		auto name = section.getName();
		if (name) {
			sections.insert(name->str());
		}
	}
	EXPECT_TRUE(sections.contains(".limine_requests"));
	EXPECT_TRUE(sections.contains(".text"));
	// The entry function keeps its name, and the program starts there
	bool found_entry = false;
	uint64_t entry_address = 0;
	// Entry functions' generated code (docs/calling_convention.md, Entry Functions)
	std::set<std::string> generated{ "freestanding.breakpoint_entry", "freestanding.breakpoint_entry.paranoid",
		"freestanding.breakpoint_entry.vector.0", "freestanding.breakpoint_entry.vector.255", "freestanding.system_call",
		"hemera.return_to_user", "hemera.fiber_start", "hemera.fiber_resume", "hemera.fiber_suspend", "runtime.fiber_run" };
	for (const llvm::object::SymbolRef& symbol : elf.symbols()) {
		auto name = symbol.getName();
		auto address = symbol.getAddress();
		if (name && address && *name == "kernel_entry") {
			found_entry = true;
			entry_address = *address;
		}
		if (name) {
			generated.erase(name->str());
		}
	}
	EXPECT_TRUE(found_entry);
	EXPECT_TRUE(generated.empty()) << "missing " << (generated.empty() ? std::string() : *generated.begin());
	auto start = elf.getStartAddress();
	ASSERT_TRUE(static_cast<bool>(start));
	EXPECT_EQ(*start, entry_address);
	EXPECT_GE(entry_address, 0xffffffff80000000);
}

/*
 * The same program builds to the same bytes every time, wherever the output goes (docs/compilation.md,
 * Deterministic Output). The kernel's #externally_initialized requests are kept though nothing uses
 * them, which is where map order once leaked in. Builds that differ can still match by chance, so
 * this builds a few times.
 */
/*
 * Every function base and std declare, generated for a target with no operating system, so what
 * can't be generated yet, or what doesn't fall back without one, shows up before anything calls it.
 */
TEST(Freestanding, GeneratesEverything)
{
	const std::filesystem::path output = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "everything_freestanding" / "kernel.elf";
	build_kernel(output, hemera::TargetStackCheck::Trap, "everything_freestanding", true);
}

TEST(Freestanding, BuildsTheSameEveryTime)
{
	const std::filesystem::path folder = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "deterministic";
	std::string first;
	for (int i = 0; i < 4; ++i) {
		const std::filesystem::path output = folder / std::format("build_{}", i) / std::format("kernel_{}.elf", i);
		build_kernel(output);
		if (testing::Test::HasFatalFailure()) {
			return;
		}
		const std::string bytes = bytes_of(output);
		ASSERT_FALSE(bytes.empty());
		if (i == 0) {
			first = bytes;
		}
		else {
			EXPECT_TRUE(bytes == first) << output.string() << " differs from the first build";
		}
	}
}

/*
 * With morestack instead of a trap, a function without room calls morestack (docs/calling_convention.md,
 * Growing the Stack), which the compiler makes: the kernel links with it.
 */
TEST(Freestanding, BuildsWithMorestack)
{
	const std::filesystem::path output = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "morestack" / "kernel.elf";
	build_kernel(output, hemera::TargetStackCheck::Morestack);
	if (testing::Test::HasFatalFailure()) {
		return;
	}
	auto binary = llvm::object::ObjectFile::createObjectFile(output.string());
	ASSERT_TRUE(static_cast<bool>(binary)) << llvm::toString(binary.takeError());
	bool found = false;
	for (const llvm::object::SymbolRef& symbol : binary->getBinary()->symbols()) {
		auto name = symbol.getName();
		found = found || (name && *name == "hemera.morestack");
	}
	EXPECT_TRUE(found);
}

// A number of count bytes, little-endian, at at in bytes, moving at past it; 0 past the end.
static uint64_t read_number(const std::string& bytes, size_t& at, size_t count) {
	uint64_t value = 0;
	for (size_t i = 0; i < count && at + i < bytes.size(); ++i) {
		value |= static_cast<uint64_t>(static_cast<uint8_t>(bytes[at + i])) << (8 * i);
	}
	at += count;
	return value;
}

static std::string read_name(const std::string& bytes, size_t& at) {
	const size_t count = read_number(bytes, at, 4);
	const std::string name = at + count <= bytes.size() ? bytes.substr(at, count) : std::string();
	at += count;
	return name;
}

/*
 * A SlopOS program built with debug info keeps none of it (docs/compilation.md, Debug Info): its DWARF goes in
 * <name>.debug beside it, an ELF of the program linked with it, after "HDBG", and then the debug table, which has main's
 * parameters with their argument numbers, each with its type's schema.
 */
TEST(Freestanding, SplitsSlopOSDebugInfo)
{
	const std::filesystem::path output = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "slop_os_debug" / "program.elf";
	const std::filesystem::path debug = std::filesystem::path(output).replace_extension(".debug");
	std::filesystem::remove(debug);
	build_elf(output, "slop_os_program", false, [](hemera::Options& options) {
		options.os = hemera::OSType::SlopOS;
		options.cpu = "x86-64-v3";
		options.relocation_model = hemera::TargetRelocationModel::PositionIndependent;
		options.debug_info = true;
	});
	if (testing::Test::HasFatalFailure()) {
		return;
	}
	auto has_dwarf = [](const std::filesystem::path& file) {
		auto binary = llvm::object::ObjectFile::createObjectFile(file.string());
		if (!binary) {
			llvm::consumeError(binary.takeError());
			return false;
		}
		for (const llvm::object::SectionRef& section : binary->getBinary()->sections()) {
			auto name = section.getName();
			if (name && *name == ".debug_info") {
				return true;
			}
		}
		return false;
	};
	EXPECT_FALSE(has_dwarf(output)) << "the program keeps its DWARF";
	const std::string bytes = bytes_of(debug);
	ASSERT_GE(bytes.size(), 16u) << "no debug file";
	EXPECT_EQ(bytes.substr(0, 4), "HDBG");
	size_t at = 4;
	EXPECT_EQ(read_number(bytes, at, 2), 1u);
	at = 8;
	const size_t elf_size = read_number(bytes, at, 8);
	ASSERT_LE(16 + elf_size, bytes.size());
	const std::filesystem::path elf = std::filesystem::path(output).replace_extension(".debug.elf");
	{
		std::ofstream out(elf, std::ios::binary | std::ios::trunc);
		out << bytes.substr(16, elf_size);
	}
	EXPECT_TRUE(has_dwarf(elf)) << "the debug file's ELF has no DWARF";
	// The table
	at = 16 + elf_size;
	ASSERT_EQ(bytes.substr(at, 4), "HDBT");
	at += 4;
	EXPECT_EQ(read_number(bytes, at, 2), 1u);
	std::vector<std::string> schemas(read_number(bytes, at, 4));
	for (std::string& schema : schemas) {
		const size_t size = read_number(bytes, at, 4);
		schema = bytes.substr(at, size);
		at += size;
		EXPECT_EQ(schema.substr(0, 4), "HSCH");
	}
	std::map<std::string, std::pair<uint64_t, std::string>> main_locals;
	const size_t functions = read_number(bytes, at, 4);
	for (size_t i = 0; i < functions && at < bytes.size(); ++i) {
		const std::string function = read_name(bytes, at);
		const size_t locals = read_number(bytes, at, 4);
		for (size_t j = 0; j < locals && at < bytes.size(); ++j) {
			const std::string name = read_name(bytes, at);
			read_number(bytes, at, 4);
			const uint64_t arg = read_number(bytes, at, 4);
			const size_t place = read_number(bytes, at, 4);
			ASSERT_LT(place, schemas.size());
			if (function.find("main") != std::string::npos && function.find("slop_os_program") != std::string::npos) {
				main_locals[name] = { arg, schemas[place] };
			}
		}
	}
	// The named types, the carrier block's among them
	std::set<std::string> named;
	const size_t named_count = read_number(bytes, at, 4);
	for (size_t i = 0; i < named_count && at < bytes.size(); ++i) {
		named.insert(read_name(bytes, at));
		EXPECT_LT(read_number(bytes, at, 4), schemas.size());
	}
	EXPECT_TRUE(named.contains("runtime.CarrierBlock"));
	EXPECT_EQ(at, bytes.size()) << "the table has bytes after its named types";
	ASSERT_TRUE(main_locals.contains("count")) << "main's count isn't in the table";
	EXPECT_EQ(main_locals["count"].first, 1u);
	EXPECT_EQ(main_locals["label"].first, 2u);
	EXPECT_EQ(main_locals["verbose"].first, 3u);
	ASSERT_TRUE(main_locals.contains("values"));
	EXPECT_EQ(main_locals["values"].first, 0u);
	// usize: an Integer (10) of 8 bytes, unsigned, the system's endianness
	const std::string usize = main_locals["count"].second;
	ASSERT_EQ(usize.size(), 4u + 2 + 4 + 1 + 8 + 2);
	EXPECT_EQ(static_cast<uint8_t>(usize[10]), 10u);
	EXPECT_EQ(static_cast<uint8_t>(usize[11]), 8u);
	EXPECT_EQ(static_cast<uint8_t>(usize[19]), 0u);
	EXPECT_EQ(static_cast<uint8_t>(usize[20]), 3u);
	// bool?: a Union (16) holding a Boolean
	EXPECT_EQ(static_cast<uint8_t>(main_locals["verbose"].second[10]), 16u);
}

/*
 * A program for SlopOS: a position-independent executable its loader relocates, whose only relocations
 * are relative ones, entered at the generated entry, which takes the process's startup block.
 */
TEST(Freestanding, BuildsSlopOSProgram)
{
	const std::filesystem::path output = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "slop_os_program" / "program.elf";
	build_elf(output, "slop_os_program", false, [](hemera::Options& options) {
		options.os = hemera::OSType::SlopOS;
		options.cpu = "x86-64-v3";
		options.relocation_model = hemera::TargetRelocationModel::PositionIndependent;
	});
	if (testing::Test::HasFatalFailure()) {
		return;
	}
	auto binary = llvm::object::ObjectFile::createObjectFile(output.string());
	ASSERT_TRUE(static_cast<bool>(binary)) << llvm::toString(binary.takeError());
	auto* elf = llvm::dyn_cast<llvm::object::ELF64LEObjectFile>(binary->getBinary());
	ASSERT_NE(elf, nullptr);
	EXPECT_EQ(elf->getELFFile().getHeader().e_type, llvm::ELF::ET_DYN);
	uint64_t entry_address = 0;
	for (const llvm::object::SymbolRef& symbol : elf->symbols()) {
		auto name = symbol.getName();
		auto address = symbol.getAddress();
		if (name && address && *name == "hemera_entry") {
			entry_address = *address;
		}
	}
	auto start = elf->getStartAddress();
	ASSERT_TRUE(static_cast<bool>(start));
	EXPECT_NE(entry_address, 0u);
	EXPECT_EQ(*start, entry_address);
	size_t relocations = 0;
	for (const llvm::object::SectionRef& section : elf->sections()) {
		auto name = section.getName();
		if (!name || *name != ".rela.dyn") {
			continue;
		}
		for (const llvm::object::RelocationRef& relocation : section.relocations()) {
			EXPECT_EQ(relocation.getType(), llvm::ELF::R_X86_64_RELATIVE);
			++relocations;
		}
	}
	EXPECT_GT(relocations, 0u);
}

/*
 * A SlopOS program whose main gives back a Result too large for registers builds: the entry makes the memory it's
 * given back through, and hands it to the runtime's os_entry_result (docs/compilation.md, Entry Results).
 */
TEST(Freestanding, BuildsSlopOSProgramGivingAResult)
{
	const std::filesystem::path output = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "slop_os_result" / "program.elf";
	build_elf(output, "slop_os_result", false, [](hemera::Options& options) {
		options.os = hemera::OSType::SlopOS;
		options.cpu = "x86-64-v3";
		options.relocation_model = hemera::TargetRelocationModel::PositionIndependent;
	});
	if (testing::Test::HasFatalFailure()) {
		return;
	}
	auto binary = llvm::object::ObjectFile::createObjectFile(output.string());
	ASSERT_TRUE(static_cast<bool>(binary)) << llvm::toString(binary.takeError());
	auto* elf = llvm::dyn_cast<llvm::object::ELF64LEObjectFile>(binary->getBinary());
	ASSERT_NE(elf, nullptr);
	bool has_entry = false;
	for (const llvm::object::SymbolRef& symbol : elf->symbols()) {
		auto name = symbol.getName();
		if (name && *name == "hemera_entry") {
			has_entry = true;
		}
	}
	EXPECT_TRUE(has_entry);
}
