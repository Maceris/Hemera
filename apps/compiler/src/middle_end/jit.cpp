#include "middle_end/jit.h"

#include <mutex>

#include "llvm/ExecutionEngine/Orc/ExecutionUtils.h"
#include "llvm/ExecutionEngine/Orc/JITTargetMachineBuilder.h"
#include "llvm/ExecutionEngine/Orc/LLJIT.h"
#include "llvm/ExecutionEngine/Orc/ThreadSafeModule.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/TargetSelect.h"

namespace hemera {

	/*
	 * Compiled code keeps its carrier block in r14 and never gives the caller's value back
	 * (docs/calling_convention.md, Carrier Register), but r14 is this function's caller's to keep: saying the
	 * call clobbers it makes this function save and restore it.
	 */
	[[clang::noinline]] static void call_compiled(void (*function)(void*), void* argument) {
		function(argument);
		asm volatile("" ::: "r14", "memory");
	}

	bool run_on_host(std::unique_ptr<llvm::Module> module, std::unique_ptr<llvm::LLVMContext> context,
		const std::string& entry, void* result, const std::function<void()>& while_loaded, std::string& error) {

		// The host's target, with its assembly parser for module-level assembly like entry trampolines
		static std::once_flag initialized;
		std::call_once(initialized, [] {
			llvm::InitializeNativeTarget();
			llvm::InitializeNativeTargetAsmPrinter();
			llvm::InitializeNativeTargetAsmParser();
		});

		auto machine = llvm::orc::JITTargetMachineBuilder::detectHost();
		if (!machine) {
			error = llvm::toString(machine.takeError());
			return false;
		}
		// The carrier register, which nothing else may use (docs/calling_convention.md, Carrier Register)
		machine->addFeatures({ "+reserve-r14" });
		auto jit = llvm::orc::LLJITBuilder().setJITTargetMachineBuilder(std::move(*machine)).create();
		if (!jit) {
			error = llvm::toString(jit.takeError());
			return false;
		}
		module->setDataLayout((*jit)->getDataLayout());
		module->setTargetTriple((*jit)->getTargetTriple());
		// The operating system's functions, through the compiler's own process
		auto process = llvm::orc::DynamicLibrarySearchGenerator::GetForCurrentProcess(
			(*jit)->getDataLayout().getGlobalPrefix());
		if (!process) {
			error = llvm::toString(process.takeError());
			return false;
		}
		(*jit)->getMainJITDylib().addGenerator(std::move(*process));
		if (llvm::Error added = (*jit)->addIRModule(llvm::orc::ThreadSafeModule(std::move(module), std::move(context)))) {
			error = llvm::toString(std::move(added));
			return false;
		}
		auto symbol = (*jit)->lookup(entry);
		if (!symbol) {
			error = llvm::toString(symbol.takeError());
			return false;
		}
		call_compiled(symbol->toPtr<void (*)(void*)>(), result);
		while_loaded();
		return true;
	}

}
