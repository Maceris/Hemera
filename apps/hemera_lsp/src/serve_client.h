#pragma once

#include <cstddef>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "checker.h"

// hemera --serve, kept running for the server's quick checks (docs/editor.md).
namespace hemera::lsp {

	/*
	 * A hemera --serve process, started the first time a check is asked of it, and again whenever it asks to be,
	 * ends, or can't be written to. One check at a time: launch's runs wait for each other.
	 */
	class ServeClient {
	public:
		/*
		 * compiler is the compiler, a path or a name found on the PATH; memory_limit_mb what it may use before it
		 * restarts, 0 for no limit.
		 */
		ServeClient(std::string compiler, size_t memory_limit_mb);
		~ServeClient();

		ServeClient(const ServeClient&) = delete;
		ServeClient& operator=(const ServeClient&) = delete;

		// Asks it the check arguments (without the compiler) ask for, starting it as needed, and says how it went.
		RunResult check(const std::vector<std::string>& arguments);

	private:
		struct Process;
		std::string compiler;
		size_t memory_limit_mb;
		std::mutex mutex;
		std::unique_ptr<Process> process;

		bool start();
		void stop_process();
	};

	/*
	 * A run of a check through client: arguments as a Launch gives them, the compiler first, which is left out of the
	 * request. Stopping it only leaves its result out, as the check runs to its end to keep the process in step.
	 */
	std::unique_ptr<Run> launch_through(std::shared_ptr<ServeClient> client, const std::vector<std::string>& arguments);
}
