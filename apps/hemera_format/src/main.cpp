#include <algorithm>
#include <atomic>
#include <cstdio>
#include <filesystem>
#include <format>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#include "error/reporting.h"
#include "memory/allocator.h"
#include "parser/formatting.h"
#include "util/console.h"

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

/*
 * hemera-format [--check | --write] [--threads=N] [path...]: lays Hemera files out to the style rules
 * (docs/formatting.md).
 *
 * With no path it formats standard input to standard output. A path is a file or a folder, whose .hsc files are
 * all formatted, folders inside it too. --check writes nothing and lists the files that would change; --write
 * writes each file that changes. Without either, one file is written to standard output.
 *
 * Exit status: 0 when every file was already formatted or was written; 1 when --check found a file that would
 * change; 2 for an error, like a file that doesn't parse or a comment that couldn't be placed, which leaves that
 * file as it was.
 */
namespace {

	constexpr int EXIT_CHANGES = 1;
	constexpr int EXIT_ERROR = 2;

	enum class Mode {
		PRINT,
		CHECK,
		WRITE,
	};

	struct FileResult {
		std::filesystem::path path;
		bool read = false;
		bool changed = false;
		bool failed = false;
		std::string formatted;
		std::string message;
		std::unique_ptr<hemera::ReportScope> scope;
	};

	void usage(std::ostream& out) {
		out << "Usage: hemera-format [--check | --write] [--threads=N] [path...]\n"
			"  Lays Hemera files out to the style rules. With no path, standard input to standard output.\n"
			"  A folder's .hsc files are all formatted, folders inside it too.\n"
			"  --check  write nothing; list the files that would change, and exit 1 if any would\n"
			"  --write  write each file that changes\n"
			"  --threads=N  format N files at once; one per processor without it\n"
			"  Without either, one file is formatted to standard output.\n";
	}

	std::string read_all(std::istream& in) {
		return std::string((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
	}

	// Formats one file into result, its errors kept in result's scope.
	void format_file(FileResult& result) {
		hemera::set_report_scope(result.scope.get());
		std::ifstream in(result.path, std::ios::binary);
		if (!in.is_open()) {
			result.failed = true;
			result.message = std::format("{}: can't be read", result.path.generic_string());
			hemera::set_report_scope(nullptr);
			return;
		}
		const std::string source = read_all(in);
		result.read = true;
		const hemera::formatting::Result formatted = hemera::formatting::format_source(source, result.path.generic_string());
		if (!formatted.parsed) {
			result.failed = true;
			result.message = std::format("{}: not formatted, as it doesn't parse", result.path.generic_string());
		}
		else if (!formatted.lost_comments.empty()) {
			result.failed = true;
			result.message = std::format("{}: not formatted, as {} comment(s) couldn't be placed, the first at byte {}",
				result.path.generic_string(), formatted.lost_comments.size(), formatted.lost_comments[0]);
		}
		else {
			result.changed = formatted.text != source;
			result.formatted = std::move(formatted.text);
		}
		hemera::set_report_scope(nullptr);
	}

	// The .hsc files path names: itself, or those in it and the folders in it, in order.
	bool collect(const std::filesystem::path& path, std::vector<std::filesystem::path>& files) {
		std::error_code error;
		if (std::filesystem::is_directory(path, error)) {
			std::vector<std::filesystem::path> found;
			for (const auto& entry : std::filesystem::recursive_directory_iterator(path, error)) {
				if (entry.is_regular_file() && entry.path().extension() == ".hsc") {
					found.push_back(entry.path());
				}
			}
			std::sort(found.begin(), found.end());
			files.insert(files.end(), found.begin(), found.end());
			return !error;
		}
		if (!std::filesystem::exists(path, error)) {
			return false;
		}
		files.push_back(path);
		return true;
	}

	int run(int argc, char* argv[]) {
		Mode mode = Mode::PRINT;
		// How many files are formatted at once: one per processor unless --threads says
		size_t threads = std::max(1u, std::thread::hardware_concurrency());
		std::vector<std::filesystem::path> paths;
		for (int i = 1; i < argc; ++i) {
			const std::string_view arg = argv[i];
			if (arg == "--check") {
				mode = Mode::CHECK;
			}
			else if (arg == "--write") {
				mode = Mode::WRITE;
			}
			else if (arg.starts_with("--threads=")) {
				const std::string_view count = arg.substr(std::string_view("--threads=").size());
				threads = 0;
				bool valid = !count.empty() && count.size() <= 4;
				for (const char digit : count) {
					valid = valid && digit >= '0' && digit <= '9';
					threads = valid ? threads * 10 + static_cast<size_t>(digit - '0') : 0;
				}
				if (!valid || threads == 0) {
					std::cerr << std::format("hemera-format: --threads takes a count of 1 or more, not {}\n", count);
					return EXIT_ERROR;
				}
			}
			else if (arg == "--help" || arg == "-h") {
				usage(std::cout);
				return 0;
			}
			else if (arg.starts_with("-")) {
				std::cerr << std::format("hemera-format: unknown option {}\n", arg);
				usage(std::cerr);
				return EXIT_ERROR;
			}
			else {
				// The process's code page is UTF-8 (the manifest), so a narrow path is UTF-8
				paths.emplace_back(arg);
			}
		}

		if (paths.empty()) {
#ifdef _WIN32
			// Bytes in and out as they are, CRLF included
			_setmode(_fileno(stdin), _O_BINARY);
			_setmode(_fileno(stdout), _O_BINARY);
#endif
			const std::string source = read_all(std::cin);
			const hemera::formatting::Result formatted = hemera::formatting::format_source(source, "<standard input>");
			if (!formatted.parsed || !formatted.lost_comments.empty()) {
				if (formatted.parsed) {
					std::cerr << std::format("<standard input>: not formatted, as {} comment(s) couldn't be placed, the first at byte {}\n",
						formatted.lost_comments.size(), formatted.lost_comments[0]);
				}
				std::cout << source;
				return EXIT_ERROR;
			}
			if (mode == Mode::CHECK) {
				return formatted.text != source ? EXIT_CHANGES : 0;
			}
			std::cout << formatted.text;
			return 0;
		}

		std::vector<std::filesystem::path> files;
		bool all_found = true;
		for (const std::filesystem::path& path : paths) {
			if (!collect(path, files)) {
				std::cerr << std::format("hemera-format: {} isn't a file or a folder\n", path.generic_string());
				all_found = false;
			}
		}
		if (mode == Mode::PRINT && (files.size() != 1 || std::filesystem::is_directory(paths[0]))) {
			std::cerr << "hemera-format: more than one file needs --check or --write\n";
			return EXIT_ERROR;
		}

		// Each file on its own, the files shared out among threads
		std::vector<FileResult> results(files.size());
		for (size_t i = 0; i < files.size(); ++i) {
			results[i].path = files[i];
			results[i].scope = std::make_unique<hemera::ReportScope>();
		}
		std::atomic<size_t> next = 0;
		auto work = [&]() {
			for (size_t i = next++; i < results.size(); i = next++) {
				format_file(results[i]);
			}
		};
		const size_t thread_count = std::min(threads, results.size());
		std::vector<std::thread> workers;
		for (size_t i = 1; i < thread_count; ++i) {
			workers.emplace_back(work);
		}
		work();
		for (std::thread& worker : workers) {
			worker.join();
		}

		int status = all_found ? 0 : EXIT_ERROR;
		for (FileResult& result : results) {
			hemera::print_report_scope(*result.scope);
			if (result.failed) {
				std::cerr << result.message << "\n";
				status = EXIT_ERROR;
				continue;
			}
			if (mode == Mode::PRINT) {
#ifdef _WIN32
				_setmode(_fileno(stdout), _O_BINARY);
#endif
				std::cout << result.formatted;
				continue;
			}
			if (!result.changed) {
				continue;
			}
			if (mode == Mode::CHECK) {
				std::cout << result.path.generic_string() << "\n";
				if (status == 0) {
					status = EXIT_CHANGES;
				}
				continue;
			}
			std::ofstream out(result.path, std::ios::binary | std::ios::trunc);
			out << result.formatted;
			out.close();
			if (!out) {
				std::cerr << std::format("{}: couldn't be written\n", result.path.generic_string());
				status = EXIT_ERROR;
			}
		}
		return status;
	}
}

int main(int argc, char* argv[])
{
	// What's printed is UTF-8, so the console shows it as that
	hemera::use_utf8_console();
	hemera::initialize_interned_string_cache();
	hemera::initialize_reporting_storage();
	const int status = run(argc, argv);
	hemera::destroy_reporting_storage();
	hemera::purge_interned_string_cache();
	return status;
}
