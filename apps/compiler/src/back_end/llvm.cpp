#include "back_end/back_end.h"

#include <optional>
#include <string>
#include <system_error>

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

	BackendLLVM::BackendLLVM() = default;
	BackendLLVM::~BackendLLVM() = default;

	void BackendLLVM::destroy() {

	}

	void BackendLLVM::generate_object_file(llvm::Module& module) {
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

		//TODO(ches) decide this
		llvm::OptimizationLevel optimization_level = llvm::OptimizationLevel::O2;

		llvm::ModulePassManager MPM = PB.buildPerModuleDefaultPipeline(optimization_level);

		MPM.run(module, MAM);

		// Output the IR
		std::string filename = "output.o";
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

		destination.flush();

	}

	void BackendLLVM::initialize() {
		llvm::InitializeAllTargetInfos();
		llvm::InitializeAllTargets();
		llvm::InitializeAllTargetMCs();
		llvm::InitializeAllAsmPrinters();

		//TODO(ches) These need to come from command line args
		llvm::Triple::ArchType arch_type = llvm::Triple::ArchType::x86_64;
		llvm::Triple::SubArchType sub_arch_type = llvm::Triple::SubArchType::NoSubArch;
		llvm::Triple::VendorType vendor_type = llvm::Triple::VendorType::Intel;
		llvm::Triple::OSType os_type = llvm::Triple::OSType::Win32;

		llvm::Triple target_triple = llvm::Triple(arch_type, sub_arch_type, vendor_type, os_type);
		std::string target_lookup_error;
		const llvm::Target* target = llvm::TargetRegistry::lookupTarget(target_triple, target_lookup_error);

		//TODO(ches) update cpu and features
		std::string cpu = "generic";
		std::string features = "";
		llvm::TargetOptions opts;
		llvm::Reloc::Model reloc_model = llvm::Reloc::Model::PIC_;

		target_machine = target->createTargetMachine(
			target_triple, cpu, features, opts, reloc_model
		);
	}

	void BackendLLVM::link() {

	}

}
