#include "back_end/back_end.h"

#include <optional>
#include <string>
#include <system_error>

#include "error/reporting.h"
#include "util/logger.h"

#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassManager.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/TargetSelect.h"

namespace hemera {

	Backend::Backend() = default;
	Backend::~Backend() = default;

	BackendLLVM::BackendLLVM()
		: target_machine{ nullptr }
	{}
	BackendLLVM::~BackendLLVM() = default;

	static llvm::Triple::ArchType map_arch_type(ArchType architecture) {
		switch (architecture) {
			case ArchType::arm: return llvm::Triple::ArchType::arm;
			case ArchType::armeb: return llvm::Triple::ArchType::armeb;
			case ArchType::aarch64: return llvm::Triple::ArchType::aarch64;
			case ArchType::aarch64_be: return llvm::Triple::ArchType::aarch64_be;
			case ArchType::aarch64_32: return llvm::Triple::ArchType::aarch64_32;
			case ArchType::x86: return llvm::Triple::ArchType::x86;
			case ArchType::x86_64: return llvm::Triple::ArchType::x86_64;
		}
		LOG_FATAL("Unexpected architecture");
	}

	static llvm::Triple::EnvironmentType map_environment_type(
		EnvironmentType environment) {

		switch (environment) {
			case EnvironmentType::UnknownEnvironment:
				return llvm::Triple::EnvironmentType::UnknownEnvironment;
			case EnvironmentType::GNU:
				return llvm::Triple::EnvironmentType::GNU;
			case EnvironmentType::GNUT64:
				return llvm::Triple::EnvironmentType::GNUT64;
			case EnvironmentType::GNUEABI:
				return llvm::Triple::EnvironmentType::GNUEABI;
			case EnvironmentType::GNUEABIT64:
				return llvm::Triple::EnvironmentType::GNUEABIT64;
			case EnvironmentType::GNUEABIHF:
				return llvm::Triple::EnvironmentType::GNUEABIHF;
			case EnvironmentType::GNUEABIHFT64:
				return llvm::Triple::EnvironmentType::GNUEABIHFT64;
			case EnvironmentType::GNUF32:
				return llvm::Triple::EnvironmentType::GNUF32;
			case EnvironmentType::GNUF64:
				return llvm::Triple::EnvironmentType::GNUF64;
			case EnvironmentType::GNUSF:
				return llvm::Triple::EnvironmentType::GNUSF;
			case EnvironmentType::GNUX32:
				return llvm::Triple::EnvironmentType::GNUX32;
			case EnvironmentType::GNUILP32:
				return llvm::Triple::EnvironmentType::GNUILP32;
			case EnvironmentType::EABI:
				return llvm::Triple::EnvironmentType::EABI;
			case EnvironmentType::EABIHF:
				return llvm::Triple::EnvironmentType::EABIHF;
			case EnvironmentType::Musl:
				return llvm::Triple::EnvironmentType::Musl;
			case EnvironmentType::MuslABI64:
				return llvm::Triple::EnvironmentType::MuslABI64;
			case EnvironmentType::MuslEABI:
				return llvm::Triple::EnvironmentType::MuslEABI;
			case EnvironmentType::MuslEABIHF:
				return llvm::Triple::EnvironmentType::MuslEABIHF;
			case EnvironmentType::MuslF32:
				return llvm::Triple::EnvironmentType::MuslF32;
			case EnvironmentType::MuslSF:
				return llvm::Triple::EnvironmentType::MuslSF;
			case EnvironmentType::MuslX32:
				return llvm::Triple::EnvironmentType::MuslX32;
			case EnvironmentType::MSVC:
				return llvm::Triple::EnvironmentType::MSVC;
			case EnvironmentType::Itanium:
				return llvm::Triple::EnvironmentType::Itanium;
		}
		LOG_FATAL("Unexpected environment type");
	}

	static llvm::Triple::ObjectFormatType map_object_format_type(
		ObjectFormatType object_format) {

		switch (object_format) {
			case ObjectFormatType::UnknownObjectFormat:
				return llvm::Triple::ObjectFormatType::UnknownObjectFormat;
			case ObjectFormatType::COFF:
				return llvm::Triple::ObjectFormatType::COFF;
			case ObjectFormatType::ELF:
				return llvm::Triple::ObjectFormatType::ELF;
			case ObjectFormatType::MachO:
				return llvm::Triple::ObjectFormatType::MachO;
		}
		LOG_FATAL("Unexpected object format type");
	}

	static llvm::OptimizationLevel map_optimization_level(
		OptimizationLevel level) {

		switch (level) {
			case OptimizationLevel::O0: return llvm::OptimizationLevel::O0;
			case OptimizationLevel::O1: return llvm::OptimizationLevel::O1;
			case OptimizationLevel::O2: return llvm::OptimizationLevel::O2;
			case OptimizationLevel::O3: return llvm::OptimizationLevel::O3;
		}
		LOG_FATAL("Unexpected optimization level");
	}

	static llvm::Triple::OSType map_os_type(OSType os) {
		switch (os) {
			case OSType::UnknownOS: return llvm::Triple::OSType::UnknownOS;
			case OSType::Darwin: return llvm::Triple::OSType::Darwin;
			case OSType::FreeBSD: return llvm::Triple::OSType::FreeBSD;
			case OSType::Linux: return llvm::Triple::OSType::Linux;
			case OSType::MacOSX: return llvm::Triple::OSType::MacOSX;
			case OSType::NetBSD: return llvm::Triple::OSType::NetBSD;
			case OSType::OpenBSD: return llvm::Triple::OSType::OpenBSD;
			case OSType::UEFI: return llvm::Triple::OSType::UEFI;
			case OSType::Win32: return llvm::Triple::OSType::Win32;
			case OSType::Firmware: return llvm::Triple::OSType::Firmware;
		}
		LOG_FATAL("Unexpected OS type");
	}

	static llvm::Triple::SubArchType map_sub_arch_type(SubArchType subarch) {
		switch (subarch) {
			case SubArchType::NoSubArch:
				return llvm::Triple::SubArchType::NoSubArch;
			case SubArchType::ARMSubArch_v9_7a:
				return llvm::Triple::SubArchType::ARMSubArch_v9_7a;
			case SubArchType::ARMSubArch_v9_6a:
				return llvm::Triple::SubArchType::ARMSubArch_v9_6a;
			case SubArchType::ARMSubArch_v9_5a:
				return llvm::Triple::SubArchType::ARMSubArch_v9_5a;
			case SubArchType::ARMSubArch_v9_4a:
				return llvm::Triple::SubArchType::ARMSubArch_v9_4a;
			case SubArchType::ARMSubArch_v9_3a:
				return llvm::Triple::SubArchType::ARMSubArch_v9_3a;
			case SubArchType::ARMSubArch_v9_2a:
				return llvm::Triple::SubArchType::ARMSubArch_v9_2a;
			case SubArchType::ARMSubArch_v9_1a:
				return llvm::Triple::SubArchType::ARMSubArch_v9_1a;
			case SubArchType::ARMSubArch_v9:
				return llvm::Triple::SubArchType::ARMSubArch_v9;
			case SubArchType::ARMSubArch_v8_9a:
				return llvm::Triple::SubArchType::ARMSubArch_v8_9a;
			case SubArchType::ARMSubArch_v8_8a:
				return llvm::Triple::SubArchType::ARMSubArch_v8_8a;
			case SubArchType::ARMSubArch_v8_7a:
				return llvm::Triple::SubArchType::ARMSubArch_v8_7a;
			case SubArchType::ARMSubArch_v8_6a:
				return llvm::Triple::SubArchType::ARMSubArch_v8_6a;
			case SubArchType::ARMSubArch_v8_5a:
				return llvm::Triple::SubArchType::ARMSubArch_v8_5a;
			case SubArchType::ARMSubArch_v8_4a:
				return llvm::Triple::SubArchType::ARMSubArch_v8_4a;
			case SubArchType::ARMSubArch_v8_3a:
				return llvm::Triple::SubArchType::ARMSubArch_v8_3a;
			case SubArchType::ARMSubArch_v8_2a:
				return llvm::Triple::SubArchType::ARMSubArch_v8_2a;
			case SubArchType::ARMSubArch_v8_1a:
				return llvm::Triple::SubArchType::ARMSubArch_v8_1a;
			case SubArchType::ARMSubArch_v8:
				return llvm::Triple::SubArchType::ARMSubArch_v8;
			case SubArchType::ARMSubArch_v8r:
				return llvm::Triple::SubArchType::ARMSubArch_v8r;
			case SubArchType::ARMSubArch_v8m_baseline:
				return llvm::Triple::SubArchType::ARMSubArch_v8m_baseline;
			case SubArchType::ARMSubArch_v8m_mainline:
				return llvm::Triple::SubArchType::ARMSubArch_v8m_mainline;
			case SubArchType::ARMSubArch_v8_1m_mainline:
				return llvm::Triple::SubArchType::ARMSubArch_v8_1m_mainline;
			case SubArchType::ARMSubArch_v7:
				return llvm::Triple::SubArchType::ARMSubArch_v7;
			case SubArchType::ARMSubArch_v7em:
				return llvm::Triple::SubArchType::ARMSubArch_v7em;
			case SubArchType::ARMSubArch_v7m:
				return llvm::Triple::SubArchType::ARMSubArch_v7m;
			case SubArchType::ARMSubArch_v7s:
				return llvm::Triple::SubArchType::ARMSubArch_v7s;
			case SubArchType::ARMSubArch_v7k:
				return llvm::Triple::SubArchType::ARMSubArch_v7k;
			case SubArchType::ARMSubArch_v7ve:
				return llvm::Triple::SubArchType::ARMSubArch_v7ve;
			case SubArchType::ARMSubArch_v6:
				return llvm::Triple::SubArchType::ARMSubArch_v6;
			case SubArchType::ARMSubArch_v6m:
				return llvm::Triple::SubArchType::ARMSubArch_v6m;
			case SubArchType::ARMSubArch_v6k:
				return llvm::Triple::SubArchType::ARMSubArch_v6k;
			case SubArchType::ARMSubArch_v6t2:
				return llvm::Triple::SubArchType::ARMSubArch_v6t2;
			case SubArchType::ARMSubArch_v5:
				return llvm::Triple::SubArchType::ARMSubArch_v5;
			case SubArchType::ARMSubArch_v5te:
				return llvm::Triple::SubArchType::ARMSubArch_v5te;
			case SubArchType::ARMSubArch_v4t:
				return llvm::Triple::SubArchType::ARMSubArch_v4t;
			case SubArchType::AArch64SubArch_arm64e:
				return llvm::Triple::SubArchType::AArch64SubArch_arm64e;
			case SubArchType::AArch64SubArch_arm64ec:
				return llvm::Triple::SubArchType::AArch64SubArch_arm64ec;
			case SubArchType::AArch64SubArch_lfi:
				return llvm::Triple::SubArchType::AArch64SubArch_lfi;
		}
		LOG_FATAL("Unexpected subarch type");
	}

	static llvm::Triple::VendorType map_vendor_type(VendorType vendor) {
		switch (vendor) {
			case VendorType::UnknownVendor:
				return llvm::Triple::VendorType::UnknownVendor;
			case VendorType::Apple:
				return llvm::Triple::VendorType::Apple;
			case VendorType::PC:
				return llvm::Triple::VendorType::PC;
			case VendorType::AMD:
				return llvm::Triple::VendorType::AMD;
			case VendorType::Intel:
				return llvm::Triple::VendorType::Intel;
		}
		LOG_FATAL("Unexpected vendor type");
	}

	void BackendLLVM::destroy() {

	}

	bool BackendLLVM::generate_object_file(const Options& options,
		llvm::Module& module) {
		// Optimize the IR
		
		//NOTE(ches) the order is important here
		llvm::LoopAnalysisManager LAM;
		llvm::FunctionAnalysisManager FAM;
		llvm::CGSCCAnalysisManager CGAM;
		llvm::ModuleAnalysisManager MAM;

		llvm::PassBuilder PB;

		PB.registerModuleAnalyses(MAM);
		PB.registerCGSCCAnalyses(CGAM);
		PB.registerFunctionAnalyses(FAM);
		PB.registerLoopAnalyses(LAM);
		PB.crossRegisterProxies(LAM, FAM, CGAM, MAM);

		llvm::OptimizationLevel optimization_level =
			map_optimization_level(options.optimization_level);

		llvm::ModulePassManager MPM =
			PB.buildPerModuleDefaultPipeline(optimization_level);

		MPM.run(module, MAM);

		// Output the IR
		std::string filename = std::format("{}.o", options.output_name);
		std::error_code error_code;
		llvm::raw_fd_ostream destination(filename, error_code,
			llvm::sys::fs::OF_None);
		
		llvm::CGPassBuilderOption opts;
		llvm::MCContext context(target_machine->getTargetTriple(),
			target_machine->getMCAsmInfo(),
			target_machine->getMCRegisterInfo(),
			target_machine->getMCSubtargetInfo()
		);
		llvm::PassInstrumentationCallbacks pic;
		
		llvm::Error result = target_machine->buildCodeGenPipeline(MPM, MAM,
			destination, nullptr, llvm::CodeGenFileType::ObjectFile, opts,
			context, &pic);

		bool had_errors = false;
		llvm::handleAllErrors(std::move(result),
			[&output_name = options.output_name, &had_errors](
				const llvm::ErrorInfoBase& error_base) {
				report_error(ErrorCode::E5001, output_name, 0, 0,
					error_base.message());
				had_errors = true;
			});

		//TODO(ches) can we delete the .o output? Do we need to ourselves?

		destination.flush();

		return !had_errors;
	}

	bool BackendLLVM::initialize(const Options& options) {
		llvm::InitializeAllTargetInfos();
		llvm::InitializeAllTargets();
		llvm::InitializeAllTargetMCs();
		llvm::InitializeAllAsmPrinters();

		llvm::Triple::ArchType arch_type = map_arch_type(options.architecture);
		llvm::Triple::SubArchType sub_arch_type =
			map_sub_arch_type(options.subarchitecture);
		llvm::Triple::VendorType vendor_type = map_vendor_type(options.vendor);
		llvm::Triple::OSType os_type = map_os_type(options.os);
		llvm::Triple::EnvironmentType environment_type =
			map_environment_type(options.environment);
		llvm::Triple::ObjectFormatType object_format_type =
			map_object_format_type(options.object_format);

		llvm::Triple target_triple = llvm::Triple(arch_type, sub_arch_type,
			vendor_type, os_type, environment_type, object_format_type);

		std::string target_lookup_error;
		const llvm::Target* target =
			llvm::TargetRegistry::lookupTarget(target_triple,
				target_lookup_error);

		if (!target_lookup_error.empty()) {
			report_error(ErrorCode::E5000, options.output_name, 0, 0,
				target_lookup_error);
			return false;
		}

		std::string cpu = options.cpu;
		std::string features = options.cpu_features;
		llvm::TargetOptions opts;
		llvm::Reloc::Model reloc_model = llvm::Reloc::Model::PIC_;

		target_machine = target->createTargetMachine(
			target_triple, cpu, features, opts, reloc_model
		);

		return true;
	}

	void BackendLLVM::link() {

	}

}
