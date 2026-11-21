#include "checker.h"

#include <algorithm>
#include <atomic>
#include <fstream>
#include <iterator>
#include <optional>
#include <utility>

#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/JSON.h"
#include "llvm/Support/Program.h"

#ifdef _WIN32
#include <Windows.h>
#else
#include <csignal>
#include <sys/types.h>
#endif

namespace hemera::lsp {

	std::vector<CompilerDiagnostic> parse_diagnostics(std::string_view output) {
		std::vector<CompilerDiagnostic> found;
		while (!output.empty()) {
			const size_t end = output.find('\n');
			std::string_view line = output.substr(0, end);
			output = end == std::string_view::npos ? std::string_view() : output.substr(end + 1);
			if (!line.empty() && line.back() == '\r') {
				line.remove_suffix(1);
			}
			llvm::Expected<llvm::json::Value> parsed = llvm::json::parse(llvm::StringRef(line.data(), line.size()));
			if (!parsed) {
				llvm::consumeError(parsed.takeError());
				continue;
			}
			const llvm::json::Object* object = parsed->getAsObject();
			const std::optional<llvm::StringRef> severity = object != nullptr ? object->getString("severity") : std::nullopt;
			const std::optional<llvm::StringRef> file = object != nullptr ? object->getString("file") : std::nullopt;
			if (!severity.has_value() || !file.has_value()) {
				continue;
			}
			CompilerDiagnostic diagnostic;
			diagnostic.severity = severity->str();
			diagnostic.code = object->getString("code").value_or("").str();
			diagnostic.file = file->str();
			diagnostic.line = static_cast<uint32_t>(object->getInteger("line").value_or(0));
			diagnostic.column = static_cast<uint32_t>(object->getInteger("column").value_or(0));
			diagnostic.message = object->getString("message").value_or("").str();
			diagnostic.target = object->getString("target").value_or("").str();
			if (const llvm::json::Array* inserted = object->getArray("inserted")) {
				for (const llvm::json::Value& site : *inserted) {
					const llvm::json::Object* place = site.getAsObject();
					if (place != nullptr && place->getString("file").has_value()) {
						diagnostic.inserted.push_back(CompilerDiagnostic::Place{ place->getString("file")->str(),
							static_cast<uint32_t>(place->getInteger("line").value_or(0)),
							static_cast<uint32_t>(place->getInteger("column").value_or(0)), std::string() });
					}
				}
			}
			if (const llvm::json::Array* fixes = object->getArray("fixes")) {
				for (const llvm::json::Value& entry : *fixes) {
					const llvm::json::Object* fix = entry.getAsObject();
					const llvm::json::Array* edits = fix != nullptr ? fix->getArray("edits") : nullptr;
					if (edits == nullptr) {
						continue;
					}
					CompilerDiagnostic::Fix made{ fix->getString("title").value_or("").str(), {} };
					for (const llvm::json::Value& edit : *edits) {
						const llvm::json::Array* parts = edit.getAsArray();
						if (parts != nullptr && parts->size() == 3) {
							made.edits.push_back(CompilerDiagnostic::Edit{ static_cast<uint32_t>((*parts)[0].getAsInteger().value_or(0)),
								static_cast<uint32_t>((*parts)[1].getAsInteger().value_or(0)), (*parts)[2].getAsString().value_or("").str() });
						}
					}
					diagnostic.fixes.push_back(std::move(made));
				}
			}
			found.push_back(std::move(diagnostic));
		}
		return found;
	}

	void delete_temporaries(const std::vector<std::string>& files) {
		for (const std::string& file : files) {
			llvm::sys::fs::remove(file);
		}
	}

	static std::string read_all(const std::string& path) {
		std::ifstream file(path, std::ios::binary);
		return std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
	}

	namespace {

		// A process LLVM started, its output going to two temporary files
		class ProcessRun : public Run {
		public:
			ProcessRun(const std::vector<std::string>& arguments) {
				llvm::SmallString<256> output_path;
				llvm::SmallString<256> error_path;
				if (llvm::sys::fs::createTemporaryFile("hemera-lsp-output", "txt", output_path)
					|| llvm::sys::fs::createTemporaryFile("hemera-lsp-error", "txt", error_path)) {
					failure = "couldn't make a temporary file for the compiler's output";
					return;
				}
				output_file = output_path.str().str();
				error_file = error_path.str().str();
				std::string program = arguments.empty() ? std::string() : arguments[0];
				if (!program.empty() && !llvm::sys::path::has_parent_path(program)) {
					// A name alone is looked for on the PATH
					llvm::ErrorOr<std::string> found = llvm::sys::findProgramByName(program);
					if (!found) {
						failure = "couldn't find " + program + " on the PATH";
						return;
					}
					program = *found;
				}
				std::vector<llvm::StringRef> argument_refs(arguments.begin(), arguments.end());
				const std::optional<llvm::StringRef> redirects[] = { llvm::StringRef(""), llvm::StringRef(output_file),
					llvm::StringRef(error_file) };
				bool execution_failed = false;
				std::string message;
				process = llvm::sys::ExecuteNoWait(program, argument_refs, std::nullopt, redirects, 0, &message, &execution_failed);
				if (execution_failed || process.Pid == llvm::sys::ProcessInfo::InvalidPid) {
					failure = "couldn't run " + program + (message.empty() ? std::string() : ": " + message);
				}
			}

			~ProcessRun() override {
				if (!output_file.empty()) {
					llvm::sys::fs::remove(output_file);
				}
				if (!error_file.empty()) {
					llvm::sys::fs::remove(error_file);
				}
			}

			RunResult wait() override {
				RunResult result;
				if (!failure.empty()) {
					result.error = failure;
					return result;
				}
				result.started = true;
				std::string message;
				const llvm::sys::ProcessInfo done = llvm::sys::Wait(process, std::nullopt, &message);
				{
					std::lock_guard<std::mutex> lock(mutex);
					finished = true;
				}
				result.stopped = was_stopped.load();
				result.exit_code = done.ReturnCode;
				if (!result.stopped) {
					result.output = read_all(output_file);
					result.error = read_all(error_file);
				}
				return result;
			}

			void stop() override {
				std::lock_guard<std::mutex> lock(mutex);
				if (finished || !failure.empty()) {
					return;
				}
				was_stopped = true;
#ifdef _WIN32
				TerminateProcess(process.Process, 1);
#else
				::kill(process.Pid, SIGKILL);
#endif
			}

		private:
			llvm::sys::ProcessInfo process;
			std::string output_file;
			std::string error_file;
			std::string failure;
			std::mutex mutex;
			bool finished = false;
			std::atomic<bool> was_stopped{ false };
		};
	}

	std::unique_ptr<Run> launch_process(const std::vector<std::string>& arguments) {
		return std::make_unique<ProcessRun>(arguments);
	}

	Checker::Checker(Launch launch, Finished finished)
		: launch(std::move(launch)), finished(std::move(finished)), worker([this] { work(); }) {}

	Checker::~Checker() {
		{
			std::lock_guard<std::mutex> lock(mutex);
			stopping = true;
			if (running != nullptr) {
				running->stop();
			}
			for (const CheckJob& job : waiting) {
				delete_temporaries(job.temporaries);
			}
			waiting.clear();
		}
		changed.notify_all();
		worker.join();
	}

	void Checker::request(CheckJob job) {
		{
			std::lock_guard<std::mutex> lock(mutex);
			/*
			 * Whether job does all an older check of the same root would: a full check does a full one's, and a quick
			 * check a quick one's of no other targets. One of the other kind, or of other targets too, isn't replaced:
			 * its result would be lost.
			 */
			const auto covers = [&](const std::vector<std::string>& older) {
				if (job.targets.empty() || older.empty()) {
					return job.targets.empty() && older.empty();
				}
				return std::all_of(older.begin(), older.end(), [&](const std::string& target) {
					return std::find(job.targets.begin(), job.targets.end(), target) != job.targets.end();
				});
			};
			for (auto it = waiting.begin(); it != waiting.end(); ++it) {
				if (it->root == job.root && covers(it->targets)) {
					delete_temporaries(it->temporaries);
					waiting.erase(it);
					break;
				}
			}
			if (running != nullptr && running_root == job.root && covers(running_targets)) {
				running->stop();
			}
			// A quick one goes ahead of those that aren't, as what's saved is shown first
			auto at = waiting.end();
			if (job.quick) {
				at = std::find_if(waiting.begin(), waiting.end(), [](const CheckJob& queued) { return !queued.quick; });
			}
			waiting.insert(at, std::move(job));
		}
		changed.notify_all();
	}

	void Checker::wait_idle() {
		std::unique_lock<std::mutex> lock(mutex);
		changed.wait(lock, [this] { return waiting.empty() && !busy; });
	}

	void Checker::work() {
		for (;;) {
			CheckJob job;
			Run* run = nullptr;
			{
				std::unique_lock<std::mutex> lock(mutex);
				changed.wait(lock, [this] { return stopping || !waiting.empty(); });
				if (stopping) {
					return;
				}
				job = std::move(waiting.front());
				waiting.pop_front();
				busy = true;
				running_root = job.root;
				running_targets = job.targets;
				running = launch(job.arguments);
				run = running.get();
			}
			const RunResult result = run->wait();
			if (!result.stopped) {
				finished(job, result);
			}
			delete_temporaries(job.temporaries);
			{
				std::lock_guard<std::mutex> lock(mutex);
				running.reset();
				running_root.clear();
				busy = false;
			}
			changed.notify_all();
		}
	}
}
