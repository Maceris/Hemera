#pragma once

#include "cmd_line/options.h"

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

		virtual void destroy() = 0;
		/// <summary>
		/// Take a module and turn it into an object file.
		/// </summary>
		/// <param name="options">Options provided by the user.</param>
		/// <param name="module">The module to turn into an object file.</param>
		/// <returns>Whether we were successful.</returns>
		virtual bool generate_object_file(const Options& options,
			llvm::Module& module) = 0;
		/// <summary>
		/// Set up the backend.
		/// </summary>
		/// <param name="options">Options provided by the user.</param>
		/// <returns>Whether it was set up successfully.</returns>
		virtual bool initialize(const Options& options) = 0;
		virtual void link() = 0;
	};

	struct BackendLLVM : public Backend {
		BackendLLVM();
		BackendLLVM(const BackendLLVM&) = delete;
		BackendLLVM(BackendLLVM&&) = delete;
		BackendLLVM& operator=(const BackendLLVM&) = delete;
		BackendLLVM& operator=(BackendLLVM&&) = delete;
		~BackendLLVM() override;

		void destroy() override;
		bool generate_object_file(const Options& options, 
			llvm::Module& module) override;
		bool initialize(const Options& options) override;
		void link() override;

	private:
		llvm::TargetMachine* target_machine;
	};
}
