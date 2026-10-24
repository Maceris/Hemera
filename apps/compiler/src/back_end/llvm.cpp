#include "back_end/back_end.h"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <format>
#include <optional>
#include <string>
#include <system_error>
#include <thread>
#include <vector>

#include "error/reporting.h"
#include "middle_end/generate.h"
#include "util/logger.h"
#include "util/phase_timer.h"

#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/CodeGen/BasicBlockSectionsProfileReader.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/MachineFunctionAnalysis.h"
#include "llvm/CodeGen/MachineFunctionAnalysisManager.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassManager.h"
#include "llvm/IR/Verifier.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Object/ModuleSymbolTable.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Program.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Target/TargetLoweringObjectFile.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Transforms/IPO/Annotation2Metadata.h"
#include "llvm/Transforms/IPO/ForceFunctionAttrs.h"
#include "llvm/Transforms/IPO/GlobalDCE.h"
#include "llvm/Transforms/IPO/MemProfContextDisambiguation.h"
#include "llvm/Transforms/Utils/SplitModule.h"

namespace hemera {

	Backend::Backend() = default;
	Backend::~Backend() = default;

	BackendLLVM::BackendLLVM()
		: target{ nullptr }
		, target_machine{ nullptr }
	{}
	BackendLLVM::~BackendLLVM() = default;

	static llvm::Triple::ArchType map_arch_type(ArchType architecture) {
		switch (architecture) {
			case ArchType::arm: return llvm::Triple::ArchType::arm;
			case ArchType::aarch64: return llvm::Triple::ArchType::aarch64;
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
			// LLVM doesn't know it: code for no particular OS, in ELF
			case OSType::SlopOS: return llvm::Triple::OSType::UnknownOS;
			case OSType::UEFI: return llvm::Triple::OSType::UEFI;
			case OSType::Win32: return llvm::Triple::OSType::Win32;
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

	/*
	 * How many parts to generate machine code for at once: one for a small module, since splitting costs a
	 * copy of the module for each part, and for an object file asked for on its own (-c), which is one file.
	 */
	static unsigned code_generation_parts(const Options& options, const llvm::Module& module) {
		// Instructions a part should have at least, to be worth a thread
		constexpr size_t PART_INSTRUCTIONS = 2500;
		constexpr unsigned MOST_PARTS = 8;
		if (options.build_extent < BuildExtent::LINK) {
			return 1;
		}
		size_t instructions = 0;
		for (const llvm::Function& function : module) {
			instructions += function.getInstructionCount();
		}
		const unsigned threads = std::max(1u, std::thread::hardware_concurrency());
		return static_cast<unsigned>(std::clamp<size_t>(instructions / PART_INSTRUCTIONS, 1, std::min(MOST_PARTS, threads)));
	}

	/*
	 * A simplified module's late optimizations and machine code, done in parts at once (like LLVM's splitCodeGen,
	 * for LTO): split by function, with what each part uses from another made external, each part written as
	 * bitcode and read back into a context of its own, since a context can't be shared between threads, then
	 * given its own target machine, optimized function by function (the second half of the default pipeline,
	 * after inlining has been done across the whole module) and generated into its object file. Module-level
	 * assembly goes in the first part. Which part a function goes in depends only on the module, so the program
	 * is the same every time.
	 */
	static bool generate_in_parts(const llvm::Target* target, const llvm::TargetMachine* machine, llvm::Module& module,
		unsigned parts, llvm::OptimizationLevel level, std::string_view output_name, std::vector<std::string>& objects) {

		/*
		 * The module's assembly, which goes in the first part, defines functions others call, like #foreign
		 * functions' shims and fibers' switches, without making them global, since one object file had them all
		 */
		std::string globals;
		llvm::ModuleSymbolTable::CollectAsmSymbols(module, [&](llvm::StringRef name, llvm::object::BasicSymbolRef::Flags flags) {
			const bool local = (flags & (llvm::object::BasicSymbolRef::SF_Global | llvm::object::BasicSymbolRef::SF_Undefined)) == 0;
			if (local && !name.empty() && !name.starts_with(".L")) {
				globals += std::format("\t.globl {}\n", name.str());
			}
		});
		if (!globals.empty()) {
			module.appendModuleInlineAsm(globals);
		}

		std::vector<llvm::SmallString<0>> bitcode;
		llvm::SplitModule(module, parts, [&](std::unique_ptr<llvm::Module> part) {
			llvm::SmallString<0> buffer;
			llvm::raw_svector_ostream stream(buffer);
			llvm::WriteBitcodeToFile(*part, stream);
			bitcode.push_back(std::move(buffer));
		}, false);

		// Each part's object file, opened first, so one that can't be written is reported as the whole one's is
		std::vector<std::unique_ptr<llvm::raw_fd_ostream>> destinations;
		for (size_t i = 0; i < bitcode.size(); ++i) {
			objects.push_back(std::format("{}.part{}.o", output_name, i));
			std::error_code error;
			destinations.push_back(std::make_unique<llvm::raw_fd_ostream>(objects[i], error, llvm::sys::fs::OF_None));
			if (error) {
				report_error(ErrorCode::E6000, objects[i], 0, 0, error.message());
				return false;
			}
		}
		std::vector<std::string> errors(bitcode.size());
		std::vector<std::thread> threads;
		for (size_t i = 0; i < bitcode.size(); ++i) {
			threads.emplace_back([&, i]() {
				llvm::LLVMContext context;
				llvm::Expected<std::unique_ptr<llvm::Module>> part = llvm::parseBitcodeFile(
					llvm::MemoryBufferRef(llvm::StringRef(bitcode[i].data(), bitcode[i].size()), "part"), context);
				if (!part) {
					errors[i] = llvm::toString(part.takeError());
					return;
				}
				std::unique_ptr<llvm::TargetMachine> part_machine(target->createTargetMachine(machine->getTargetTriple(),
					machine->getTargetCPU(), machine->getTargetFeatureString(), machine->Options, machine->getRelocationModel(),
					machine->getCodeModel(), machine->getOptLevel()));
				if (level != llvm::OptimizationLevel::O0) {
					llvm::LoopAnalysisManager loops;
					llvm::FunctionAnalysisManager functions;
					llvm::CGSCCAnalysisManager call_graph;
					llvm::ModuleAnalysisManager modules;
					llvm::PassBuilder builder(part_machine.get());
					builder.registerModuleAnalyses(modules);
					builder.registerCGSCCAnalyses(call_graph);
					builder.registerFunctionAnalyses(functions);
					builder.registerLoopAnalyses(loops);
					builder.crossRegisterProxies(loops, functions, call_graph, modules);
					builder.buildModuleOptimizationPipeline(level, llvm::ThinOrFullLTOPhase::None).run(**part, modules);
				}
				llvm::legacy::PassManager passes;
				if (part_machine->addPassesToEmitFile(passes, *destinations[i], nullptr, llvm::CodeGenFileType::ObjectFile)) {
					errors[i] = "the target can't generate an object file";
					return;
				}
				passes.run(**part);
				destinations[i]->flush();
			});
		}
		for (std::thread& thread : threads) {
			thread.join();
		}
		// The first, since the parts fail alike, like all their files being in a folder that isn't there
		for (const std::string& error : errors) {
			if (!error.empty()) {
				report_error(ErrorCode::E5001, output_name, 0, 0, error);
				return false;
			}
		}
		return true;
	}

	bool BackendLLVM::generate_object_file(const Options& options,
		llvm::Module& module, std::string_view output_name) {
		// Optimize the IR

		module.setTargetTriple(target_machine->getTargetTriple());
		module.setDataLayout(target_machine->createDataLayout());
		libraries.clear();
		if (llvm::NamedMDNode* list = module.getNamedMetadata(LIBRARIES_METADATA)) {
			for (llvm::MDNode* library : list->operands()) {
				if (library->getNumOperands() == 1) {
					if (auto* name = llvm::dyn_cast<llvm::MDString>(library->getOperand(0))) {
						libraries.push_back(name->getString().str());
					}
				}
			}
		}

		//NOTE(ches) the order is important here
		llvm::LoopAnalysisManager loop_analysis_manager;
		llvm::FunctionAnalysisManager function_analysis_manager;
		llvm::CGSCCAnalysisManager call_graph_analysis_manager;
		llvm::ModuleAnalysisManager module_analysis_manager;

		llvm::MachineModuleInfo machine_module_info(target_machine);
		llvm::MachineModuleAnalysis machine_module_analysis(machine_module_info);
		llvm::MachineFunctionAnalysisManager machine_function_analysis_manager;
		llvm::MachineFunctionAnalysis machine_function_analysis(*target_machine);
		llvm::BasicBlockSectionsProfileReaderAnalysis basic_block_sections_profile_reader_analysis(*target_machine);

		// With the target machine, so the passes cost things as the target does: what's worth inlining or
		// vectorizing, and whether functions with different #target_features can be inlined into each other
		llvm::PassBuilder pass_builder(target_machine);

		pass_builder.registerModuleAnalyses(module_analysis_manager);
		pass_builder.registerCGSCCAnalyses(call_graph_analysis_manager);
		pass_builder.registerFunctionAnalyses(function_analysis_manager);
		pass_builder.registerMachineFunctionAnalyses(machine_function_analysis_manager);
		pass_builder.registerLoopAnalyses(loop_analysis_manager);
		pass_builder.crossRegisterProxies(loop_analysis_manager,
			function_analysis_manager,
			call_graph_analysis_manager,
			module_analysis_manager,
			&machine_function_analysis_manager
		);
		
		module_analysis_manager.registerPass([&] { return machine_module_analysis; });
		function_analysis_manager.registerPass([&] { return machine_function_analysis; });
		function_analysis_manager.registerPass([&] { return basic_block_sections_profile_reader_analysis; });

		llvm::OptimizationLevel optimization_level =
			map_optimization_level(options.optimization_level);

		/*
		 * A large module: simplified whole, inlining across all of it, with the functions that leaves unused
		 * dropped, then optimized function by function and generated in parts at once
		 */
		objects.clear();
		if (const unsigned parts = code_generation_parts(options, module); parts > 1) {
			if (optimization_level != llvm::OptimizationLevel::O0) {
				llvm::ModulePassManager simplification;
				simplification.addPass(llvm::MemProfRemoveInfo());
				simplification.addPass(llvm::Annotation2MetadataPass());
				simplification.addPass(llvm::ForceFunctionAttrsPass());
				simplification.addPass(pass_builder.buildModuleSimplificationPipeline(optimization_level, llvm::ThinOrFullLTOPhase::None));
				simplification.addPass(llvm::GlobalDCEPass());
				PhaseTimer timer(options.time_phases, std::format("  simplify the whole of {}", std::filesystem::path(output_name).filename().string()));
				simplification.run(module, module_analysis_manager);
			}
			PhaseTimer timer(options.time_phases, std::format("  optimize and assemble {} in {} parts", std::filesystem::path(output_name).filename().string(), parts));
			return generate_in_parts(target, target_machine, module, parts, optimization_level, output_name, objects);
		}

		llvm::ModulePassManager module_pass_manager =
			pass_builder.buildPerModuleDefaultPipeline(optimization_level);
		objects.push_back(std::string(output_name));

		// Setup the IR output
		std::error_code error_code;
		llvm::raw_fd_ostream destination(output_name, error_code,
			llvm::sys::fs::OF_None);
		// Like a folder that isn't there: reported, rather than writing to a stream that never opened
		if (error_code) {
			report_error(ErrorCode::E6000, output_name, 0, 0, error_code.message());
			return false;
		}
		
		llvm::SourceMgr source_manager;
		llvm::MCRegisterInfo* mc_register_info = target->createMCRegInfo(*target_triple);
		llvm::MCTargetOptions mc_target_options;
		llvm::MCAsmInfo* mc_asm_info = target->createMCAsmInfo(
			*mc_register_info,
			*target_triple,
			mc_target_options
		);
		llvm::MCSubtargetInfo* mc_subtarget_info = target->createMCSubtargetInfo(
			*target_triple, 
			target_machine->getTargetCPU(), 
			target_machine->getTargetFeatureString()
		);
		llvm::MCContext mc_context(
			*target_triple,
			*mc_asm_info,
			*mc_register_info,
			*mc_subtarget_info,
			&source_manager
		);
		const bool is_PIC = true;// Position Independent Code
		const bool is_large_code_model = false; // Large memory model
		llvm::MCObjectFileInfo* mc_object_file_info = 
			target->createMCObjectFileInfo(mc_context, is_PIC, 
				is_large_code_model);
		mc_context.setObjectFileInfo(mc_object_file_info);

		llvm::CGPassBuilderOption code_gen_pass_builder_option;
		llvm::PassInstrumentationCallbacks pass_instrumentation_callbacks;
		llvm::Error result = target_machine->buildCodeGenPipeline(
			module_pass_manager,
			module_analysis_manager,
			destination,
			nullptr,
			llvm::CodeGenFileType::ObjectFile,
			code_gen_pass_builder_option,
			mc_context,
			&pass_instrumentation_callbacks
		);

		// Run everything
		module_pass_manager.run(module, module_analysis_manager);

		bool had_errors = false;
		llvm::handleAllErrors(std::move(result),
			[&output_name, &had_errors](
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
		// For inline assembly, which intrinsics compile to
		llvm::InitializeAllAsmParsers();

		llvm::Triple::ArchType arch_type = map_arch_type(options.architecture);
		llvm::Triple::SubArchType sub_arch_type =
			map_sub_arch_type(options.subarchitecture);
		llvm::Triple::VendorType vendor_type = map_vendor_type(options.vendor);
		llvm::Triple::OSType os_type = map_os_type(options.os);
		llvm::Triple::EnvironmentType environment_type =
			map_environment_type(options.environment);
		llvm::Triple::ObjectFormatType object_format_type =
			map_object_format_type(options.object_format);

		target_triple = new llvm::Triple(
			arch_type,
			sub_arch_type,
			vendor_type,
			os_type,
			environment_type,
			object_format_type
		);

		std::string target_lookup_error;
		target = llvm::TargetRegistry::lookupTarget(*target_triple,
				target_lookup_error);

		if (!target_lookup_error.empty()) {
			report_error(ErrorCode::E5000, options.output_name, 0, 0,
				target_lookup_error);
			return false;
		}

		std::string cpu = options.cpu;
		std::string features = target_features(options);
		llvm::TargetOptions opts;
		llvm::Reloc::Model reloc_model = TargetRelocationModel::Static == options.relocation_model
			? llvm::Reloc::Model::Static : llvm::Reloc::Model::PIC_;
		std::optional<llvm::CodeModel::Model> code_model;
		switch (options.code_model) {
		case TargetCodeModel::Default:
			break;
		case TargetCodeModel::Small:
			code_model = llvm::CodeModel::Small;
			break;
		case TargetCodeModel::Kernel:
			code_model = llvm::CodeModel::Kernel;
			break;
		case TargetCodeModel::Medium:
			code_model = llvm::CodeModel::Medium;
			break;
		case TargetCodeModel::Large:
			code_model = llvm::CodeModel::Large;
			break;
		}

		target_machine = target->createTargetMachine(
			*target_triple, cpu, features, opts, reloc_model, code_model
		);

		return true;
	}

	// lld-link's arguments, for PE/COFF: a hosted program starts at the entry the compiler generates, which needs only kernel32.
	static std::vector<std::string> coff_arguments(const Options& options, const std::vector<std::string>& libraries) {
		// /Brepro: no link time in the program or its PDB, so the same program builds to the same bytes every time
		std::vector<std::string> args{ "/Brepro" };
		// Each #foreign function's library, by its import library
		for (const std::string& library : libraries) {
			args.push_back(std::format("{}.lib", library));
		}
		if (options.debug_info) {
			args.push_back("/debug");
		}
		if (options.startup_code) {
			args.insert(args.end(), { std::format("/entry:{}", HOSTED_ENTRY_SYMBOL), "/subsystem:console", "/nodefaultlib", "kernel32.lib" });
		}
		else {
			args.insert(args.end(), { std::format("/entry:{}", options.entry), "/nodefaultlib" });
		}
		args.push_back(std::format("/out:{}.exe", options.output_name));
		switch (options.architecture) {
		case ArchType::arm:
			args.push_back("/machine:arm");
			break;
		case ArchType::aarch64:
		case ArchType::aarch64_32:
			args.push_back("/machine:arm64");
			break;
		case ArchType::x86:
			args.push_back("/machine:x86");
			break;
		case ArchType::x86_64:
			args.push_back("/machine:x64");
			break;
		}
		return args;
	}

	/*
	 * ld.lld's arguments, for ELF: static, without the C runtime, and a position-independent executable for
	 * position-independent code, like a relocatable kernel.
	 */
	static std::vector<std::string> elf_arguments(const Options& options, const std::vector<std::string>& libraries) {
		/*
		 * A hosted Linux program with #foreign libraries links C dynamically, against the sysroot's
		 * libraries, and starts through libc; any other is static, with no C library
		 */
		const bool links_c = options.startup_code && OSType::Linux == options.os && !libraries.empty();
		std::vector<std::string> args{ "-nostdlib" };
		if (links_c) {
			args.insert(args.end(), { "-dynamic-linker", "/lib64/ld-linux-x86-64.so.2" });
			if (!options.sysroot.empty()) {
				args.insert(args.end(), { "-L", options.sysroot.string() });
			}
			args.push_back("-lc");
		}
		else {
			args.push_back("-static");
		}
		// Each #foreign function's library
		for (const std::string& library : libraries) {
			if (!links_c || library != "c") {
				args.push_back(std::format("-l{}", library));
			}
		}
		/*
		 * A position-independent executable relocates itself, which freestanding programs like a
		 * relocatable kernel do; a hosted one has no C library to do it, so it's linked at a fixed address
		 */
		if (TargetRelocationModel::PositionIndependent == options.relocation_model
			&& (!options.startup_code || OSType::SlopOS == options.os)) {
			// A SlopOS program's loader relocates it, as Limine does a kernel
			args.insert(args.end(), { "-pie", "--no-dynamic-linker" });
		}
		const bool linux_start = options.startup_code && OSType::Linux == options.os && ArchType::x86_64 == options.architecture;
		args.insert(args.end(), { "-e", linux_start ? LINUX_START_SYMBOL : options.startup_code ? HOSTED_ENTRY_SYMBOL : options.entry });
		if (!options.linker_script.empty()) {
			args.insert(args.end(), { "-T", options.linker_script.string() });
		}
		if (!options.debug_info) {
			args.push_back("--strip-debug");
		}
		args.insert(args.end(), { "-o", options.output_name });
		return args;
	}

	/*
	 * The linker run directly, rather than through a shell, which on Windows starts cmd.exe first: about 60 ms
	 * of every build. The linker is found on the PATH.
	 */
	void BackendLLVM::link(const Options& options,
		std::string_view object_file) {

		// What generate_object_file wrote, in order, or the object asked for
		const std::vector<std::string> files = objects.empty() ? std::vector<std::string>{ std::string(object_file) } : objects;
		std::string linker;
		std::vector<std::string> args;
		if (ObjectFormatType::ELF == options.object_format) {
			linker = "ld.lld";
			args = elf_arguments(options, libraries);
		}
		else if (ObjectFormatType::COFF == options.object_format) {
			linker = "lld-link";
			args = coff_arguments(options, libraries);
		}
		else {
			report_error(ErrorCode::E7000, object_file, 0, 0, "only ELF and PE/COFF outputs can be linked yet");
			return;
		}
		args.insert(args.end(), files.begin(), files.end());
		llvm::ErrorOr<std::string> program = llvm::sys::findProgramByName(linker);
		if (!program) {
			report_error(ErrorCode::E7000, object_file, 0, 0, std::format("{} isn't on the PATH", linker));
		}
		else {
			std::vector<llvm::StringRef> argv{ *program };
			for (const std::string& arg : args) {
				argv.push_back(arg);
			}
			std::string message;
			const int result = llvm::sys::ExecuteAndWait(*program, argv, std::nullopt, {}, 0, 0, &message);
			if (result != 0) {
				if (message.empty()) {
					report_error(ErrorCode::E7000, object_file, 0, 0);
				}
				else {
					report_error(ErrorCode::E7000, object_file, 0, 0, message);
				}
			}
		}

		for (const std::string& file : files) {
			if (!std::filesystem::remove(file)) {
				report_error(ErrorCode::E7001, file, 0, 0);
			}
		}

	}

}
