#include "middle_end/serve.h"

#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <format>
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "cmd_line/cmd_line_utils.h"
#include "cmd_line/options.h"
#include "error/reporting.h"
#include "front_end/documentation.h"
#include "front_end/front_end.h"
#include "front_end/info.h"
#include "front_end/name_index.h"
#include "front_end/names.h"
#include "hmir/hmir_dialect.h"
#include "middle_end/build.h"
#include "util/console.h"
#include "util/logger.h"
#include "util/phase_timer.h"

#include "llvm/Support/JSON.h"
#include "llvm/Support/xxhash.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"

namespace hemera {

	namespace {

		// What hemera exits with when a check had errors, as its main does
		constexpr int FAILED = -1;

		// The arguments that don't decide what a build is, so may differ between checks that reuse it
		bool varies(std::string_view argument) {
			return argument.starts_with("--targets") || argument.starts_with("--overlay") || argument.starts_with("--index")
				|| argument.starts_with("--diagnostics");
		}

		std::vector<std::string> deciding(const std::vector<std::string>& arguments) {
			std::vector<std::string> kept;
			for (const std::string& argument : arguments) {
				if (!varies(argument)) {
					kept.push_back(argument);
				}
			}
			return kept;
		}

		// The bytes a check reads for path: an overlay's, or the file's; empty if neither can be read
		std::string bytes_of(const Options& options, const std::string& path) {
			const std::string* overlay = find_overlay(options, path);
			std::ifstream file(overlay != nullptr ? *overlay : path, std::ios::binary);
			return std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
		}

		// How a later check finds the build: as it was, changed, or as it was but for a loaded package with errors
		enum class Freshness {
			SAME,
			CHANGED,
			BROKEN,
		};

		// A build package's state, kept from the check that made it for the checks after it
		struct Kept {
			Allocator<> alloc;
			Options* options = nullptr;
			std::unique_ptr<mlir::MLIRContext> context;
			std::unique_ptr<mlir::OpBuilder> builder;
			mlir::ModuleOp module;
			ProgramInfo* build = nullptr;
			// What it reported while it was checked, reported again by each check that reuses it
			std::vector<Diagnostic> diagnostics;
			/*
			 * What it depends on: the arguments that decide it, the build's own files' bytes' hashes, each package
			 * load_package loaded's, by its folder, each folder's listing, and what compiler.declares answered
			 */
			std::vector<std::string> arguments;
			std::map<std::string, uint64_t> files;
			std::map<std::string, std::map<std::string, uint64_t>> loaded;
			std::vector<std::pair<std::string, std::vector<std::string>>> listings;
			// What compiler.declares answered, asked again when a check would reuse it
			std::vector<DeclarationAsked> declared;
			// Whether a check can reuse it: only a build package's, and only one checked without errors
			bool reusable = false;
			/*
			 * Each loaded package's constants, as the build read them, by its folder: taken before it's first checked
			 * again, which a reloaded one is compared with
			 */
			std::map<std::string, std::string> constants;
			// The loaded packages whose files have errors now, checked again by each check until they don't
			std::set<std::string> broken;

			// The files a program read, by their bytes' hashes, as options read them; not base's, the compiler's own
			static std::map<std::string, uint64_t> read_files(ProgramInfo* program, const Options& reading) {
				std::map<std::string, uint64_t> found;
				for (const auto& [path, package] : program->packages) {
					if (is_base_package(path)) {
						continue;
					}
					for (const auto& [file_name, file] : package->files) {
						const std::string file_path = file_path_of(path, file_name);
						const std::string bytes = bytes_of(reading, file_path);
						found[file_path] = llvm::xxh3_64bits(llvm::StringRef(bytes));
					}
					// And a file added to the package since, as packages are found by listing their folders
					std::error_code error;
					for (const std::filesystem::directory_entry& entry : std::filesystem::directory_iterator(std::string_view(*path), error)) {
						const std::string file_path = file_path_of(path, intern(entry.path().filename().string()));
						if (entry.path().extension() == ".hsc" && !found.contains(file_path)) {
							const std::string bytes = bytes_of(reading, file_path);
							found[file_path] = llvm::xxh3_64bits(llvm::StringRef(bytes));
						}
					}
				}
				return found;
			}

			/*
			 * Whether a check with arguments, read as options, finds the build as it was. A package load_package loaded
			 * whose files changed is checked again, and the build is as it was if its constants are, which is what the
			 * build could have read of it. One that has errors now leaves the build as it was, but for this check, which
			 * reports them, as a fresh check's build would, and checks no targets: what it reports is in reported.
			 */
			Freshness refresh(const std::vector<std::string>& given, const Options& reading, std::vector<Diagnostic>& reported) {
				if (!reusable || deciding(given) != arguments || read_files(build, reading) != files) {
					return Freshness::CHANGED;
				}
				for (const auto& [folder, listed] : listings) {
					std::error_code error;
					std::vector<std::string> now;
					for (const std::filesystem::directory_entry& entry : std::filesystem::directory_iterator(folder, error)) {
						if (entry.is_directory()) {
							now.push_back(std::filesystem::canonical(entry.path(), error).string());
						}
					}
					std::sort(now.begin(), now.end());
					if (error || now != listed) {
						return Freshness::CHANGED;
					}
				}
				// What compiler.declares answered, asked again of the files as they are: parsing, not checking
				for (const DeclarationAsked& asked : declared) {
					if (!asked.folder.empty() && package_declares(asked.folder, asked.name, reading) != asked.declared) {
						return Freshness::CHANGED;
					}
				}
				for (const auto& [folder, program] : loaded_package_programs()) {
					if (!broken.contains(folder) && read_files(program, reading) == loaded[folder]) {
						continue;
					}
					/*
					 * What the reloaded package reports is kept apart, as a fresh check would report it in the build's
					 * own: warnings, or anything it reported before, make it a build that isn't as it was, and a fresh
					 * compiler shows what it does
					 */
					for (const Diagnostic& diagnostic : diagnostics) {
						if (std::filesystem::path(diagnostic.file).lexically_normal().string().starts_with(folder)) {
							return Freshness::CHANGED;
						}
					}
					// The constants the build read, from the package as it was when the build was checked
					if (!constants.contains(folder)) {
						constants[folder] = loaded_constants(folder);
					}
					ReportScope reloading;
					ReportScope* outer = report_scope();
					set_report_scope(&reloading);
					reload_package(folder, reading.overlays);
					set_report_scope(outer);
					if (reloading.errors > 0) {
						broken.insert(folder);
						reported.insert(reported.end(), reloading.diagnostics.begin(), reloading.diagnostics.end());
						continue;
					}
					if (!reloading.diagnostics.empty() || loaded_constants(folder) != constants[folder]) {
						return Freshness::CHANGED;
					}
					broken.erase(folder);
					for (const auto& [again, reloaded] : loaded_package_programs()) {
						if (again == folder) {
							loaded[folder] = read_files(reloaded, reading);
						}
					}
				}
				return broken.empty() ? Freshness::SAME : Freshness::BROKEN;
			}

			// What it depends on, recorded after a check, which may have loaded more
			void remember(const std::vector<std::string>& given, const Options& reading) {
				arguments = deciding(given);
				files = read_files(build, reading);
				loaded.clear();
				for (const auto& [folder, program] : loaded_package_programs()) {
					loaded[folder] = read_files(program, reading);
				}
				listings = folder_listings();
				declared = declarations_answered();
			}
		};

		// The index, if asked for: the build's names and its targets', written where it was asked to be
		bool write_asked_index(NameIndex* index, ProgramInfo& build, const Options& options) {
			if (index == nullptr) {
				return true;
			}
			add_to_index(*index, build, options);
			return write_index(*index, options.index_path);
		}

		// The first check, which checks the package from the start, and keeps it if it's a build package
		int first_check(Kept& kept, const std::vector<std::string>& given) {
			std::vector<std::string> arguments{ "hemera" };
			arguments.insert(arguments.end(), given.begin(), given.end());
			std::vector<char*> argv;
			for (std::string& argument : arguments) {
				argv.push_back(argument.data());
			}
			bool fine = true;
			kept.options = handle_command_line(static_cast<int>(argv.size()), argv.data(), kept.alloc, &fine);
			if (!fine || kept.options == nullptr) {
				return 1;
			}
			Options& options = *kept.options;
			options.free_targets = true;
			kept.context = std::make_unique<mlir::MLIRContext>();
			kept.context->loadDialect<mlir::BuiltinDialect>();
			kept.context->loadDialect<mlir::func::FuncDialect>();
			kept.context->loadDialect<hmir::HemeraDialect>();
			kept.builder = std::make_unique<mlir::OpBuilder>(kept.context.get());
			kept.module = mlir::ModuleOp::create(*kept.builder, kept.builder->getUnknownLoc(), options.output_name);
			kept.build = kept.alloc.new_object<ProgramInfo>(kept.context.get(), kept.builder.get(), &kept.module);
			std::unique_ptr<NameIndex> index = options.index_path.empty() ? nullptr : std::make_unique<NameIndex>();
			// Its names are recorded whether this check wants an index or not, so later ones can have one
			kept.build->name_uses = std::make_shared<NameUses>();
			{
				PhaseTimer timer(options.time_phases, "check");
				kick_off_processing(kept.build, &options);
			}
			kept.diagnostics = diagnostics();
			int exit = 0;
			if (error_count() > 0) {
				exit = FAILED;
			}
			else if (!build_registry().targets.empty() || !build_registry().steps.empty()) {
				kept.reusable = true;
				kept.remember(given, options);
				exit = build_targets(kept.build, options, kept.alloc, index.get()) ? 0 : FAILED;
			}
			else {
				exit = finish_program(&options, kept.build, kept.module) ? 0 : FAILED;
			}
			if (!write_asked_index(index.get(), *kept.build, options)) {
				exit = FAILED;
			}
			return exit;
		}

		// A later check, reusing the build: its diagnostics reported again, then its targets checked
		int reusing_check(Kept& kept, const std::vector<std::string>& given, Allocator<>& alloc, const Options& options) {
			for (const Diagnostic& diagnostic : kept.diagnostics) {
				report_again(diagnostic);
			}
			std::unique_ptr<NameIndex> index = options.index_path.empty() ? nullptr : std::make_unique<NameIndex>();
			int exit = build_targets(kept.build, options, alloc, index.get()) ? 0 : FAILED;
			if (!write_asked_index(index.get(), *kept.build, options)) {
				exit = FAILED;
			}
			// What it loaded since is part of it now
			PhaseTimer remembering(options.time_phases, "remember what the build read");
			kept.remember(given, options);
			return exit;
		}

		/*
		 * A later check while a package the build loaded has errors: the build's diagnostics and those, and none of its
		 * targets checked, as a fresh check's build stops at errors
		 */
		int broken_check(Kept& kept, const std::vector<Diagnostic>& reported, const Options& options) {
			for (const Diagnostic& diagnostic : kept.diagnostics) {
				report_again(diagnostic);
			}
			for (const Diagnostic& diagnostic : reported) {
				report_again(diagnostic);
			}
			std::unique_ptr<NameIndex> index = options.index_path.empty() ? nullptr : std::make_unique<NameIndex>();
			write_asked_index(index.get(), *kept.build, options);
			return FAILED;
		}

		// The arguments a request line asks for, or empty if it isn't one
		std::optional<std::vector<std::string>> request_of(const std::string& line) {
			llvm::Expected<llvm::json::Value> parsed = llvm::json::parse(line);
			if (!parsed) {
				llvm::consumeError(parsed.takeError());
				return std::nullopt;
			}
			const llvm::json::Object* object = parsed->getAsObject();
			const llvm::json::Array* arguments = object != nullptr ? object->getArray("arguments") : nullptr;
			if (arguments == nullptr) {
				return std::nullopt;
			}
			std::vector<std::string> found;
			for (const llvm::json::Value& argument : *arguments) {
				found.push_back(argument.getAsString().value_or("").str());
			}
			return found;
		}
	}

	int serve(int argc, char* argv[]) {
		size_t memory_limit = 0;
		for (int i = 2; i < argc; ++i) {
			const std::string_view argument(argv[i]);
			if (argument.starts_with("--memory-limit=")) {
				memory_limit = static_cast<size_t>(std::stoull(std::string(argument.substr(std::string_view("--memory-limit=").size())))) * 1024 * 1024;
			}
		}
		// Standard output carries the answers alone, before any compile-time code can print to it
		std::FILE* answers = take_standard_output();
		if (answers == nullptr) {
			std::cerr << "Standard output couldn't be kept for answers" << std::endl;
			return 1;
		}
		Logger::init();
		initialize_interned_string_cache();
		initialize_reporting_storage();
		enable_reporting();
		enable_reporting_printing();
		print_diagnostics_as_json(answers);

		Kept kept;
		std::string line;
		while (std::getline(std::cin, line)) {
			if (!line.empty() && line.back() == '\r') {
				line.pop_back();
			}
			const std::optional<std::vector<std::string>> given = request_of(line);
			if (!given.has_value()) {
				write_protocol_line("{\"done\":false,\"restart\":false,\"error\":\"a request is {\\\"arguments\\\": [...]}\"}");
				continue;
			}
			reset_reporting_storage();
			forget_documentation_checks();
			int exit = 0;
			if (kept.build == nullptr) {
				exit = first_check(kept, *given);
			}
			else {
				// Read as the request reads, overlays and all, to see whether the build is as it was
				Allocator<> alloc;
				std::vector<std::string> arguments{ "hemera" };
				arguments.insert(arguments.end(), given->begin(), given->end());
				std::vector<char*> request_argv;
				for (std::string& argument : arguments) {
					request_argv.push_back(argument.data());
				}
				bool fine = true;
				Options* options = handle_command_line(static_cast<int>(request_argv.size()), request_argv.data(), alloc, &fine);
				if (!fine || options == nullptr) {
					write_protocol_line("{\"done\":true,\"exit\":1,\"restart\":false}");
					continue;
				}
				std::vector<Diagnostic> reported;
				auto refreshing = std::make_unique<PhaseTimer>(options->time_phases, "see whether the build is as it was");
				const Freshness freshness = kept.refresh(*given, *options, reported);
				refreshing.reset();
				if (Freshness::CHANGED == freshness) {
					write_protocol_line("{\"done\":false,\"restart\":true}");
					return 3;
				}
				options->free_targets = true;
				exit = Freshness::BROKEN == freshness ? broken_check(kept, reported, *options) : reusing_check(kept, *given, alloc, *options);
			}
			const bool restart = memory_limit != 0 && memory_in_use() > memory_limit;
			write_protocol_line(std::format("{{\"done\":true,\"exit\":{},\"restart\":{}}}", exit, restart ? "true" : "false"));
			if (restart) {
				return 3;
			}
		}
		return 0;
	}
}
