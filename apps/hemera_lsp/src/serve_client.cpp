#include "serve_client.h"

#include <algorithm>
#include <atomic>
#include <format>
#include <optional>
#include <utility>

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/JSON.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/Program.h"
#include "llvm/Support/raw_ostream.h"

#ifdef _WIN32
#include <Windows.h>
#else
#include <csignal>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
extern char** environ;
#endif

namespace hemera::lsp {

#ifdef _WIN32
	// UTF-8 text as Windows' UTF-16, for a path or a command line
	static std::wstring wide_text(const std::string& text) {
		if (text.empty()) {
			return {};
		}
		const int length = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
		std::wstring wide(static_cast<size_t>(length), L'\0');
		MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), wide.data(), length);
		return wide;
	}
#endif

	// The process, and the ends of its pipes the client keeps.
	struct ServeClient::Process {
#ifdef _WIN32
		HANDLE process = nullptr;
		HANDLE input = nullptr;
		HANDLE output = nullptr;
#else
		pid_t pid = -1;
		int input = -1;
		int output = -1;
#endif
		// What's been read past the last line given out
		std::string pending;

		~Process() {
#ifdef _WIN32
			if (input != nullptr) {
				CloseHandle(input);
			}
			if (output != nullptr) {
				CloseHandle(output);
			}
			if (process != nullptr) {
				// Standard input closed, it ends; one that doesn't is ended
				if (WaitForSingleObject(process, 2000) == WAIT_TIMEOUT) {
					TerminateProcess(process, 1);
				}
				CloseHandle(process);
			}
#else
			if (input >= 0) {
				close(input);
			}
			if (output >= 0) {
				close(output);
			}
			if (pid > 0) {
				int status = 0;
				for (int tries = 0; tries < 20 && waitpid(pid, &status, WNOHANG) == 0; ++tries) {
					usleep(100000);
				}
				if (waitpid(pid, &status, WNOHANG) == 0) {
					kill(pid, SIGKILL);
					waitpid(pid, &status, 0);
				}
			}
#endif
		}

		// Ends it at once, so what's reading its output sees the end
		void terminate() {
#ifdef _WIN32
			if (process != nullptr) {
				TerminateProcess(process, 1);
			}
#else
			if (pid > 0) {
				kill(pid, SIGKILL);
			}
#endif
		}

		bool write(const std::string& text) {
#ifdef _WIN32
			size_t done = 0;
			while (done < text.size()) {
				DWORD written = 0;
				if (!WriteFile(input, text.data() + done, static_cast<DWORD>(text.size() - done), &written, nullptr) || written == 0) {
					return false;
				}
				done += written;
			}
			return true;
#else
			size_t done = 0;
			while (done < text.size()) {
				const ssize_t written = ::write(input, text.data() + done, text.size() - done);
				if (written <= 0) {
					return false;
				}
				done += static_cast<size_t>(written);
			}
			return true;
#endif
		}

		// The next line it writes, without its end; empty when it ends
		std::optional<std::string> read_line() {
			for (;;) {
				const size_t end = pending.find('\n');
				if (end != std::string::npos) {
					std::string line = pending.substr(0, end);
					pending.erase(0, end + 1);
					if (!line.empty() && line.back() == '\r') {
						line.pop_back();
					}
					return line;
				}
				char buffer[65536];
#ifdef _WIN32
				DWORD read = 0;
				if (!ReadFile(output, buffer, sizeof(buffer), &read, nullptr) || read == 0) {
					return std::nullopt;
				}
#else
				const ssize_t read = ::read(output, buffer, sizeof(buffer));
				if (read <= 0) {
					return std::nullopt;
				}
#endif
				pending.append(buffer, static_cast<size_t>(read));
			}
		}
	};

	ServeClient::ServeClient(std::string compiler, size_t memory_limit_mb)
		: compiler(std::move(compiler)), memory_limit_mb(memory_limit_mb) {}

	ServeClient::~ServeClient() {
		stop_process();
	}

	void ServeClient::stop_process() {
		{
			std::lock_guard<std::mutex> lock(running_mutex);
			running = nullptr;
		}
		process.reset();
	}

	void ServeClient::interrupt() {
		std::lock_guard<std::mutex> lock(running_mutex);
		if (running != nullptr) {
			interrupted = true;
			running->terminate();
		}
	}

	bool ServeClient::start() {
		std::string program = compiler;
		if (!llvm::sys::path::has_parent_path(program)) {
			llvm::ErrorOr<std::string> found = llvm::sys::findProgramByName(program);
			if (!found) {
				return false;
			}
			program = *found;
		}
		std::vector<std::string> arguments{ program, "--serve" };
		if (memory_limit_mb != 0) {
			arguments.push_back(std::format("--memory-limit={}", memory_limit_mb));
		}
		auto made = std::make_unique<Process>();
#ifdef _WIN32
		SECURITY_ATTRIBUTES inherited{ sizeof(SECURITY_ATTRIBUTES), nullptr, TRUE };
		HANDLE child_input = nullptr;
		HANDLE child_output = nullptr;
		if (!CreatePipe(&child_input, &made->input, &inherited, 0) || !CreatePipe(&made->output, &child_output, &inherited, 0)) {
			return false;
		}
		// The client's ends aren't the child's
		SetHandleInformation(made->input, HANDLE_FLAG_INHERIT, 0);
		SetHandleInformation(made->output, HANDLE_FLAG_INHERIT, 0);
		std::wstring command;
		for (const std::string& argument : arguments) {
			command += (command.empty() ? L"\"" : L" \"") + wide_text(argument) + L"\"";
		}
		STARTUPINFOW startup{};
		startup.cb = sizeof(startup);
		startup.dwFlags = STARTF_USESTDHANDLES;
		startup.hStdInput = child_input;
		startup.hStdOutput = child_output;
		// What it prints besides its answers goes where the server's own error output does
		startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
		PROCESS_INFORMATION started{};
		const std::wstring wide_program = wide_text(program);
		const BOOL created = CreateProcessW(wide_program.c_str(), command.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW, nullptr,
			nullptr, &startup, &started);
		CloseHandle(child_input);
		CloseHandle(child_output);
		if (!created) {
			return false;
		}
		CloseHandle(started.hThread);
		made->process = started.hProcess;
#else
		int to_child[2];
		int from_child[2];
		if (pipe(to_child) != 0 || pipe(from_child) != 0) {
			return false;
		}
		posix_spawn_file_actions_t actions;
		posix_spawn_file_actions_init(&actions);
		posix_spawn_file_actions_adddup2(&actions, to_child[0], STDIN_FILENO);
		posix_spawn_file_actions_adddup2(&actions, from_child[1], STDOUT_FILENO);
		posix_spawn_file_actions_addclose(&actions, to_child[1]);
		posix_spawn_file_actions_addclose(&actions, from_child[0]);
		std::vector<char*> argv;
		for (std::string& argument : arguments) {
			argv.push_back(argument.data());
		}
		argv.push_back(nullptr);
		pid_t pid = -1;
		const int spawned = posix_spawn(&pid, program.c_str(), &actions, nullptr, argv.data(), environ);
		posix_spawn_file_actions_destroy(&actions);
		close(to_child[0]);
		close(from_child[1]);
		if (spawned != 0) {
			close(to_child[1]);
			close(from_child[0]);
			return false;
		}
		made->pid = pid;
		made->input = to_child[1];
		made->output = from_child[0];
#endif
		process = std::move(made);
		return true;
	}

	RunResult ServeClient::check(const std::vector<std::string>& arguments) {
		std::lock_guard<std::mutex> lock(mutex);
		llvm::json::Array given;
		for (const std::string& argument : arguments) {
			given.push_back(argument);
		}
		std::string request;
		llvm::raw_string_ostream out(request);
		out << llvm::json::Value(llvm::json::Object{ { "arguments", std::move(given) } });
		out.flush();
		request += "\n";
		RunResult result;
		{
			std::lock_guard<std::mutex> running_lock(running_mutex);
			interrupted = false;
		}
		// Once as it is, and once more on a fresh compiler, if it asks for one or ends on the way
		for (int attempt = 0; attempt < 2; ++attempt) {
			if (process == nullptr && !start()) {
				result.error = "couldn't start " + compiler + " --serve";
				return result;
			}
			{
				std::lock_guard<std::mutex> running_lock(running_mutex);
				running = process.get();
			}
			result.output.clear();
			if (!process->write(request)) {
				stop_process();
				continue;
			}
			for (;;) {
				const std::optional<std::string> line = process->read_line();
				if (!line.has_value()) {
					stop_process();
					std::lock_guard<std::mutex> running_lock(running_mutex);
					if (interrupted) {
						result.stopped = true;
						result.output.clear();
						return result;
					}
					break;
				}
				llvm::Expected<llvm::json::Value> parsed = llvm::json::parse(*line);
				const llvm::json::Object* object = parsed ? parsed->getAsObject() : nullptr;
				if (!parsed) {
					llvm::consumeError(parsed.takeError());
				}
				if (object == nullptr || !object->get("done")) {
					result.output += *line + "\n";
					continue;
				}
				const bool done = object->getBoolean("done").value_or(false);
				const bool restart = object->getBoolean("restart").value_or(false);
				if (!done) {
					// Not checked, as the build changed: asked of a fresh compiler instead
					stop_process();
					result.rebuilt = true;
					break;
				}
				result.started = true;
				result.exit_code = static_cast<int>(object->getInteger("exit").value_or(0));
				if (restart) {
					stop_process();
				}
				else {
					std::lock_guard<std::mutex> running_lock(running_mutex);
					running = nullptr;
				}
				return result;
			}
		}
		result.error = compiler + " --serve ended before it answered";
		return result;
	}

	namespace {

		// A check through the client, run as it's waited for; stopping it leaves its result out
		class ServeRun : public Run {
		public:
			ServeRun(std::shared_ptr<ServeClient> client, std::vector<std::string> arguments)
				: client(std::move(client)), arguments(std::move(arguments)) {
				everything = std::none_of(this->arguments.begin(), this->arguments.end(),
					[](const std::string& argument) { return argument.starts_with("--targets="); });
			}

			RunResult wait() override {
				RunResult result = client->check(arguments);
				result.stopped = result.stopped || stopped.load();
				if (result.stopped) {
					result.output.clear();
				}
				return result;
			}

			void stop() override {
				stopped = true;
				if (everything) {
					client->interrupt();
				}
			}

		private:
			std::shared_ptr<ServeClient> client;
			std::vector<std::string> arguments;
			std::atomic<bool> stopped{ false };
			// A check of everything, which stopping ends rather than waits out
			bool everything = false;
		};
	}

	std::unique_ptr<Run> launch_through(std::shared_ptr<ServeClient> client, const std::vector<std::string>& arguments) {
		// The compiler isn't asked for: it's the client's
		return std::make_unique<ServeRun>(std::move(client),
			std::vector<std::string>(arguments.begin() + (arguments.empty() ? 0 : 1), arguments.end()));
	}
}
