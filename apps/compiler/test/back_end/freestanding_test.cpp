#include <filesystem>
#include <format>
#include <memory>
#include <set>
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
#include "llvm/Object/ObjectFile.h"
#include "mlir/IR/BuiltinDialect.h"

static std::filesystem::path scenario(std::string_view name) {
	return std::filesystem::path(__FILE__).remove_filename() / "scenarios" / name;
}

/*
 * A freestanding kernel, compiled the whole way to an ELF the way SlopOS builds one: no startup
 * code, no red zone, no SIMD, stack checks that trap, position-independent, placed by a linker
 * script. Booting it takes Limine and QEMU, which SlopOS's harness has; here the ELF is checked:
 * its entry, and Limine's requests in their sections.
 */
TEST(Freestanding, BuildsKernel)
{
	hemera::reset_reporting_storage();
	StringCacheGuard string_cache;

	mlir::MLIRContext context;
	context.loadDialect<mlir::BuiltinDialect>();
	context.loadDialect<hmir::HemeraDialect>();
	mlir::OpBuilder builder(&context);
	mlir::ModuleOp module = mlir::ModuleOp::create(builder, builder.getUnknownLoc(), "freestanding");
	auto program_info = std::make_unique<hemera::ProgramInfo>(&context, &builder, &module);

	const std::filesystem::path output_folder = std::filesystem::path(HEMERA_TEST_OUTPUT_DIR) / "freestanding";
	std::filesystem::create_directories(output_folder);
	hemera::Options options;
	options.input = std::filesystem::canonical(scenario("freestanding"));
	options.output_name = (output_folder / "kernel.elf").string();
	options.os = hemera::OSType::UnknownOS;
	options.vendor = hemera::VendorType::UnknownVendor;
	options.environment = hemera::EnvironmentType::UnknownEnvironment;
	options.object_format = hemera::ObjectFormatType::ELF;
	options.cpu_features = "-mmx,-sse,-sse2,-avx,-avx2,+soft-float";
	options.red_zone = false;
	options.stack_check = hemera::TargetStackCheck::Trap;
	options.startup_code = false;
	options.entry = "kernel_entry";
	options.linker_script = std::filesystem::canonical(scenario("freestanding") / "linker.ld");
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

	auto binary = llvm::object::ObjectFile::createObjectFile(options.output_name);
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
	for (const llvm::object::SymbolRef& symbol : elf.symbols()) {
		auto name = symbol.getName();
		auto address = symbol.getAddress();
		if (name && address && *name == "kernel_entry") {
			found_entry = true;
			entry_address = *address;
		}
	}
	EXPECT_TRUE(found_entry);
	auto start = elf.getStartAddress();
	ASSERT_TRUE(static_cast<bool>(start));
	EXPECT_EQ(*start, entry_address);
	EXPECT_GE(entry_address, 0xffffffff80000000);

	module.erase();
}
