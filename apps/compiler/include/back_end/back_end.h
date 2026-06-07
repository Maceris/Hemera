#pragma once

#include "llvm/IR/Module.h"
#include "llvm/Target/TargetMachine.h"

namespace hemera {
	struct Backend {
		Backend();
		Backend(const Backend&) = delete;
		Backend(Backend&&) = delete;
		Backend& operator=(const Backend&) = delete;
		Backend& operator=(Backend&&) = delete;
		virtual ~Backend();

		virtual void destroy();
		virtual void generate_object_file(llvm::Module& module);
		virtual void initialize();
		virtual void link();
	};

	struct BackendLLVM : public Backend {
		BackendLLVM();
		BackendLLVM(const BackendLLVM&) = delete;
		BackendLLVM(BackendLLVM&&) = delete;
		BackendLLVM& operator=(const BackendLLVM&) = delete;
		BackendLLVM& operator=(BackendLLVM&&) = delete;
		~BackendLLVM() override;

		void destroy() override;
		void generate_object_file(llvm::Module& module) override;
		void initialize() override;
		void link() override;

	private:
		llvm::TargetMachine* target_machine;
	};
}
