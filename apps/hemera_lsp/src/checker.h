#pragma once

#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <map>
#include <set>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

/*
 * Running hemera --check --diagnostics=json for the language server, and reading what it reports: one check at a
 * time, on a thread of its own, a newer check of the same root stopping the one running.
 */
namespace hemera::lsp {

	// One diagnostic as hemera --diagnostics=json prints it (docs/compilation.md, Diagnostics as JSON)
	struct CompilerDiagnostic {
		// error, warning or information
		std::string severity;
		// prefix:code, like hemera:E4015; empty for information
		std::string code;
		// The path on disk, with / throughout, or <base>/... for base's files
		std::string file;
		// Counting from 1; 0 for none in particular
		uint32_t line = 0;
		// Bytes from the line's start, counting from 0; 0 too for none in particular
		uint32_t column = 0;
		std::string message;
		// The build package's target whose check found it; empty for the build's own code, or a program
		std::string target;
		// A place in a file, as file, line and column are above, with what's there
		struct Place {
			std::string file;
			uint32_t line = 0;
			uint32_t column = 0;
			std::string message;
		};
		// For one in inserted code, each #insert that put the code there, the first first; empty otherwise
		std::vector<Place> inserted;
		// What else it shows, as related information: the server's own, never the compiler's
		std::vector<Place> related;
		// Ways to fix it, each a title and its edits in the diagnostic's file: an offset and a length, in the text the
		// check read, and what goes there
		struct Edit {
			uint32_t offset = 0;
			uint32_t length = 0;
			std::string text;
		};
		struct Fix {
			std::string title;
			std::vector<Edit> edits;
		};
		std::vector<Fix> fixes;
	};

	/*
	 * The diagnostics in the compiler's standard output, a JSON object a line. A line that isn't one, or lacks a
	 * severity or a file, is skipped.
	 */
	std::vector<CompilerDiagnostic> parse_diagnostics(std::string_view output);

	// How a run of the compiler went
	struct RunResult {
		// Whether it started at all: false when the program couldn't be found or run, with error saying why
		bool started = false;
		// Whether it was stopped, by a newer check, before it finished; what it printed is then left out
		bool stopped = false;
		int exit_code = 0;
		// What it wrote to standard output, then standard error, or why it didn't start
		std::string output;
		std::string error;
		/*
		 * Whether hemera --serve found the build package changed, and checked it afresh: what other targets find may
		 * have changed too. Always false for a process of its own.
		 */
		bool rebuilt = false;
	};

	// A run of a program that can be stopped from another thread.
	class Run {
	public:
		virtual ~Run() = default;
		// Waits for it to finish, or to be stopped, and says how it went; called once
		virtual RunResult wait() = 0;
		// Stops it, if it hasn't finished; wait then says it was stopped
		virtual void stop() = 0;
	};

	/*
	 * Starts arguments[0] with the rest of arguments, its standard input empty. Never null: one that couldn't start
	 * says so from wait.
	 */
	using Launch = std::function<std::unique_ptr<Run>(const std::vector<std::string>& arguments)>;

	// The real Launch: a process, through LLVM's, standard output and error kept in temporary files.
	std::unique_ptr<Run> launch_process(const std::vector<std::string>& arguments);

	// A check to run: the root package it checks, the command, and temporary files to delete once it's done.
	struct CheckJob {
		std::string root;
		std::vector<std::string> arguments;
		std::vector<std::string> temporaries;
		// Which of the server's settings it was made under, so a result from before they changed is left out
		uint64_t generation = 0;
		// Where the check writes its name index (--index), which is among temporaries; empty for none
		std::string index_file;
		// The text of each document that was open when it was made, by path_key, which the index's offsets count in
		std::map<std::string, std::string> texts;
		// For a check of some of a build package's targets (--targets), their names; empty for a check of everything
		std::vector<std::string> targets;
	};

	/*
	 * Runs checks one at a time, on a thread of its own. A newer request for a root replaces a waiting one it does all
	 * of, and stops a running one it does all of: a check of everything does a check of everything's, and a check of
	 * some targets one's of no others. Any other is left to run, the newer one queued behind it, so no check's result
	 * is lost that a newer one wouldn't give. A stopped check's result is left out. Requests wait their turn, in order.
	 */
	class Checker {
	public:
		// Called on the checker's thread with a check's result, unless it was stopped
		using Finished = std::function<void(const CheckJob& job, const RunResult& result)>;

		Checker(Launch launch, Finished finished);
		// Stops what's running and drops what's waiting, deleting their temporary files
		~Checker();

		Checker(const Checker&) = delete;
		Checker& operator=(const Checker&) = delete;

		void request(CheckJob job);

		// Waits until nothing is running or waiting, for tests
		void wait_idle();

	private:
		Launch launch;
		Finished finished;
		std::mutex mutex;
		std::condition_variable changed;
		std::deque<CheckJob> waiting;
		// The root being checked, and its run, while one is
		std::string running_root;
		std::vector<std::string> running_targets;
		std::unique_ptr<Run> running;
		bool busy = false;
		bool stopping = false;
		std::thread worker;

		void work();
	};

	// Deletes temporary files, ignoring any already gone
	void delete_temporaries(const std::vector<std::string>& files);
}
