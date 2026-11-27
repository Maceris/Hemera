#include "middle_end/build_cache.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <format>
#include <fstream>
#include <iterator>
#include <mutex>
#include <random>
#include <set>
#include <sstream>
#include <string>
#include <system_error>
#include <thread>
#include <utility>
#include <vector>

#include "cmd_line/options.h"
#include "front_end/info.h"
#include "front_end/names.h"
#include "middle_end/build.h"
#include "memory/allocator.h"

#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Process.h"
#include "llvm/Support/Program.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Support/xxhash.h"
#include "mlir/IR/OperationSupport.h"

namespace hemera {

	namespace {

		// What changes when an entry's layout or what its key covers does, so an older compiler's entries aren't used
		constexpr std::string_view CACHE_VERSION = "hemera build cache 1";
		// The most the cache holds once trimmed: 4 GiB, trimmed to three quarters of it so it isn't trimmed every build
		constexpr uintmax_t CACHE_LIMIT = uintmax_t{ 4 } << 30;

		// Whether this process kept anything, so trimming looks at the cache only then
		std::atomic<bool> kept_something{ false };

		std::string hex_of(llvm::XXH128_hash_t hash) {
			return std::format("{:016x}{:016x}", hash.high64, hash.low64);
		}

		std::string read_bytes(const std::filesystem::path& path, bool& read) {
			std::ifstream file(path, std::ios::binary);
			read = static_cast<bool>(file);
			return std::string(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
		}

		/*
		 * The compiler itself, by its executable's bytes: worked out once, as base is embedded in it and its code makes
		 * the outputs. Empty if it can't be read, which keeps the cache from being used.
		 */
		const std::string& compiler_identity() {
			static std::once_flag once;
			// Kept for the process's life, never destroyed, as a cache key may be made until it ends
			static std::string* identity = new std::string();
			std::call_once(once, [] {
				static int anchor = 0;
				const std::string executable = llvm::sys::fs::getMainExecutable(nullptr, &anchor);
				bool read = false;
				const std::string bytes = read_bytes(executable, read);
				if (read && !bytes.empty()) {
					*identity = hex_of(llvm::xxh3_128bits(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size()));
				}
			});
			return *identity;
		}

		// The entry's folder for key: the cache's folder, then the key's first two digits, then the key
		std::filesystem::path entry_folder(const Options& options, const std::string& key) {
			return cache_folder_of(options) / key.substr(0, 2) / key;
		}

		// Copies from to to, over what's there; false if it couldn't be
		bool copy_over(const std::filesystem::path& from, const std::filesystem::path& to) {
			std::error_code error;
			std::filesystem::copy_file(from, to, std::filesystem::copy_options::overwrite_existing, error);
			return !error;
		}
	}

	bool caches(const Options& options) {
		return options.use_cache && options.build_extent >= BuildExtent::LINK && options.fuzz.empty();
	}

	std::filesystem::path cache_folder_of(const Options& options) {
		if (!options.cache_folder.empty()) {
			return options.cache_folder;
		}
		auto variable = [](const char* name) { return llvm::sys::Process::GetEnv(name).value_or(""); };
#ifdef _WIN32
		if (const std::string local = variable("LOCALAPPDATA"); !local.empty()) {
			return std::filesystem::path(local) / "Hemera" / "cache";
		}
#else
		if (const std::string xdg = variable("XDG_CACHE_HOME"); !xdg.empty()) {
			return std::filesystem::path(xdg) / "hemera";
		}
		if (const std::string home = variable("HOME"); !home.empty()) {
			return std::filesystem::path(home) / ".cache" / "hemera";
		}
#endif
		return std::filesystem::temp_directory_path() / "hemera-cache";
	}

	/*
	 * Which linker links a program, as the back end finds it (BackendLLVM::link): the target's own, or ld.lld or
	 * lld-link on the PATH. Its path, size and modification time, as two linkers on the PATH can give different
	 * outputs, like an older lld that drops a property note another keeps; empty where none is found.
	 */
	static std::string linker_identity(const Options& options) {
		std::string linker = options.linker;
		if (linker.empty()) {
			linker = ObjectFormatType::COFF == options.object_format ? "lld-link" : "ld.lld";
		}
		llvm::ErrorOr<std::string> program = std::filesystem::path(linker).is_absolute() ? llvm::ErrorOr<std::string>(linker)
			: llvm::sys::findProgramByName(linker);
		if (!program) {
			return {};
		}
		std::error_code error;
		const std::filesystem::path found(*program);
		const auto size = std::filesystem::file_size(found, error);
		const auto written = std::filesystem::last_write_time(found, error);
		if (error) {
			return found.generic_string();
		}
		return std::format("{} {} {}", found.generic_string(), size, written.time_since_epoch().count());
	}

	std::string build_cache_key(const Options& options, mlir::ModuleOp module) {
		const std::string& identity = compiler_identity();
		if (identity.empty()) {
			return {};
		}
		/*
		 * What lowering, optimizing and linking read besides the MLIR. The output's name is in it since a PE/COFF
		 * program names its PDB, and a split debug file is named after it; where it's written isn't, but for a PE/COFF
		 * program with debug info, whose PDB records the command that linked it (Deterministic Output)
		 */
		std::string text;
		text.reserve(4096);
		auto line = [&](std::string_view name, const auto& value) { text += std::format("{}={}\n", name, value); };
		text += CACHE_VERSION;
		text += '\n';
		line("compiler", identity);
		const std::filesystem::path output(options.output_name);
		const bool coff_debug = ObjectFormatType::COFF == options.object_format && options.debug_info;
		line("output", coff_debug ? std::filesystem::absolute(output).generic_string() : output.filename().generic_string());
		line("extent", static_cast<int>(options.build_extent));
		line("optimization", static_cast<int>(options.optimization_level));
		line("architecture", static_cast<int>(options.architecture));
		line("subarchitecture", static_cast<int>(options.subarchitecture));
		line("vendor", static_cast<int>(options.vendor));
		line("os", static_cast<int>(options.os));
		line("environment", static_cast<int>(options.environment));
		line("object_format", static_cast<int>(options.object_format));
		line("code_model", static_cast<int>(options.code_model));
		line("relocation_model", static_cast<int>(options.relocation_model));
		line("stack_check", static_cast<int>(options.stack_check));
		line("cpu", options.cpu);
		line("cpu_features", options.cpu_features);
		line("entry", options.entry);
		line("debug_info", options.debug_info);
		line("typed_library", options.typed_library);
		line("startup_code", options.startup_code);
		line("red_zone", options.red_zone);
		line("address_zero_is_memory", options.address_zero_is_memory);
		line("control_flow_integrity", options.control_flow_integrity);
		line("coverage", options.coverage);
		line("model_checked", options.model_checked);
		line("valgrind_secrets", options.valgrind_secrets);
		line("max_frame_size", options.max_frame_size);
		line("linker", options.linker);
		line("linker_found", linker_identity(options));
		line("sysroot", options.sysroot.generic_string());
		for (const std::filesystem::path& folder : options.library_paths) {
			line("library_path", folder.generic_string());
		}
		if (!options.linker_script.empty()) {
			bool read = false;
			const std::string script = read_bytes(options.linker_script, read);
			if (!read) {
				return {};
			}
			line("linker_script", hex_of(llvm::xxh3_128bits(reinterpret_cast<const uint8_t*>(script.data()), script.size())));
		}
		/*
		 * The program as generated, with its locations, which its debug info and #caller_location are made from. The
		 * module is named after the output's whole path, which the program doesn't take in, so it's hashed under the
		 * file's name alone, and a build into another folder, like a test's own, finds the same outputs
		 */
		std::string generated;
		{
			const std::optional<llvm::StringRef> name = module.getSymName();
			const std::string whole = name.has_value() ? name->str() : std::string();
			module.setSymName(output.filename().generic_string());
			llvm::raw_string_ostream stream(generated);
			module.print(stream, mlir::OpPrintingFlags().enableDebugInfo(true, false));
			if (name.has_value()) {
				module.setSymName(whole);
			}
			else {
				module.removeSymNameAttr();
			}
		}
		line("module", hex_of(llvm::xxh3_128bits(reinterpret_cast<const uint8_t*>(generated.data()), generated.size())));
		return hex_of(llvm::xxh3_128bits(reinterpret_cast<const uint8_t*>(text.data()), text.size()));
	}

	std::vector<CacheOutput> cache_outputs(const Options& options) {
		const std::filesystem::path stem(options.output_name);
		std::vector<std::filesystem::path> paths;
		if (ObjectFormatType::COFF == options.object_format) {
			// A UEFI application keeps the name it's given; another gets .exe or .dll, its PDB, and a DLL's import library
			const std::filesystem::path program = OSType::UEFI == options.os ? stem
				: std::filesystem::path(options.output_name + (options.typed_library ? ".dll" : ".exe"));
			paths = { program, std::filesystem::path(program).replace_extension(".pdb"),
				std::filesystem::path(program).replace_extension(".lib"), std::filesystem::path(program).replace_extension(".exp") };
		}
		else {
			// An ELF program, and the debug file a SlopOS program's debug info is split into
			paths = { stem, std::filesystem::path(stem).replace_extension(".debug") };
		}
		std::vector<CacheOutput> outputs;
		for (const std::filesystem::path& path : paths) {
			CacheOutput output{ path, false, {} };
			std::error_code error;
			output.existed = std::filesystem::is_regular_file(path, error);
			if (output.existed) {
				output.written = std::filesystem::last_write_time(path, error);
			}
			outputs.push_back(std::move(output));
		}
		return outputs;
	}

	bool reuse_from_cache(const Options& options, const std::string& key) {
		const std::filesystem::path folder = entry_folder(options, key);
		std::error_code error;
		if (!std::filesystem::is_directory(folder, error)) {
			return false;
		}
		// Each output kept is a file named by its place in cache_outputs' list
		const std::vector<CacheOutput> outputs = cache_outputs(options);
		bool any = false;
		for (size_t i = 0; i < outputs.size(); ++i) {
			const std::filesystem::path kept = folder / std::to_string(i);
			if (!std::filesystem::is_regular_file(kept, error)) {
				continue;
			}
			if (!copy_over(kept, outputs[i].path)) {
				return false;
			}
			any = true;
		}
		// Used now, so it's among the last trimmed
		std::filesystem::last_write_time(folder, std::filesystem::file_time_type::clock::now(), error);
		return any;
	}

	void keep_in_cache(const Options& options, const std::string& key, const std::vector<CacheOutput>& outputs) {
		const std::filesystem::path folder = entry_folder(options, key);
		std::error_code error;
		if (std::filesystem::exists(folder, error)) {
			return;
		}
		// Written beside it under a name of its own, then renamed, so a reader never sees half an entry
		static std::atomic<uint64_t> made{ 0 };
		const uint64_t unique = (static_cast<uint64_t>(std::random_device{}()) << 32) ^ made.fetch_add(1);
		const std::filesystem::path partial = folder.parent_path() / std::format("{}.{:016x}.partial", key, unique);
		std::filesystem::create_directories(partial, error);
		if (error) {
			return;
		}
		bool any = false;
		for (size_t i = 0; i < outputs.size(); ++i) {
			const CacheOutput& output = outputs[i];
			std::error_code missing;
			if (!std::filesystem::is_regular_file(output.path, missing)) {
				continue;
			}
			// Only what this build wrote: one left from before, like a PDB from a build with debug info, isn't an output
			if (output.existed && std::filesystem::last_write_time(output.path, missing) == output.written) {
				continue;
			}
			if (!copy_over(output.path, partial / std::to_string(i))) {
				std::filesystem::remove_all(partial, error);
				return;
			}
			any = true;
		}
		if (!any) {
			std::filesystem::remove_all(partial, error);
			return;
		}
		std::filesystem::rename(partial, folder, error);
		if (error) {
			// Another build kept the same outputs first
			std::filesystem::remove_all(partial, error);
			return;
		}
		kept_something = true;
	}

	void trim_build_cache(const Options& options) {
		if (!kept_something.exchange(false)) {
			return;
		}
		struct Entry {
			std::filesystem::path folder;
			std::filesystem::file_time_type used;
			uintmax_t size = 0;
		};
		std::vector<Entry> entries;
		uintmax_t total = 0;
		std::error_code error;
		for (const auto& group : std::filesystem::directory_iterator(cache_folder_of(options), error)) {
			if (!group.is_directory(error)) {
				continue;
			}
			for (const auto& found : std::filesystem::directory_iterator(group.path(), error)) {
				if (!found.is_directory(error) || found.path().extension() == ".partial") {
					continue;
				}
				Entry entry{ found.path(), found.last_write_time(error), 0 };
				for (const auto& file : std::filesystem::directory_iterator(found.path(), error)) {
					entry.size += file.file_size(error);
				}
				total += entry.size;
				entries.push_back(std::move(entry));
			}
		}
		if (total <= CACHE_LIMIT) {
			return;
		}
		std::sort(entries.begin(), entries.end(), [](const Entry& a, const Entry& b) { return a.used < b.used; });
		for (const Entry& entry : entries) {
			if (total <= CACHE_LIMIT / 4 * 3) {
				break;
			}
			std::filesystem::remove_all(entry.folder, error);
			if (!error) {
				total -= entry.size;
			}
		}
	}

	// What a target's build used of files (docs/compilation.md, The Build Cache: Targets)

	namespace {

		thread_local FileRecord* current_record = nullptr;

		// What changes when a target's entry's layout does
		constexpr std::string_view TARGET_VERSION = "hemera target 1";

		// The bytes compile-time code reads for path: an overlay's, or the file's; read is false if neither can be read
		std::string reading_bytes(const Options& options, const std::string& path, bool& read) {
			const std::string* overlay = find_overlay(options, path);
			return read_bytes(overlay != nullptr ? std::filesystem::path(*overlay) : std::filesystem::path(path), read);
		}

		std::string hash_text(std::string_view text) {
			return hex_of(llvm::xxh3_128bits(reinterpret_cast<const uint8_t*>(text.data()), text.size()));
		}

		// A folder's entries' names, sorted, one a line, a folder's ending in /: what listing it found
		std::string listing_of(const std::string& path) {
			std::vector<std::string> names;
			std::error_code error;
			for (const auto& entry : std::filesystem::directory_iterator(path, error)) {
				names.push_back(entry.path().filename().string() + (entry.is_directory(error) ? "/" : ""));
			}
			if (error) {
				return "missing";
			}
			std::sort(names.begin(), names.end());
			std::string text;
			for (const std::string& name : names) {
				text += name;
				text += '\n';
			}
			return hash_text(text);
		}

		// What's at path, as probing it finds: missing, file or folder
		std::string kind_of(const std::string& path) {
			std::error_code error;
			const std::filesystem::file_status status = std::filesystem::status(path, error);
			return status.type() == std::filesystem::file_type::directory ? "folder"
				: status.type() == std::filesystem::file_type::not_found || error ? "missing" : "file";
		}

		// The options a target's build reads besides its sources, as text, one a line
		std::string options_text(const Options& options) {
			std::string text;
			auto line = [&](std::string_view name, const auto& value) { text += std::format("{}={}\n", name, value); };
			line("input", options.input.generic_string());
			line("output", std::filesystem::absolute(options.output_name).generic_string());
			line("entry", options.entry);
			line("extent", static_cast<int>(options.build_extent));
			line("optimization", static_cast<int>(options.optimization_level));
			line("architecture", static_cast<int>(options.architecture));
			line("os", static_cast<int>(options.os));
			line("object_format", static_cast<int>(options.object_format));
			line("code_model", static_cast<int>(options.code_model));
			line("relocation_model", static_cast<int>(options.relocation_model));
			line("stack_check", static_cast<int>(options.stack_check));
			line("cpu", options.cpu);
			line("cpu_features", options.cpu_features);
			line("debug_info", options.debug_info);
			line("configuration", options.configuration);
			line("typed_library", options.typed_library);
			line("startup_code", options.startup_code);
			line("red_zone", options.red_zone);
			line("address_zero_is_memory", options.address_zero_is_memory);
			line("control_flow_integrity", options.control_flow_integrity);
			line("coverage", options.coverage);
			line("model_checked", options.model_checked);
			line("valgrind_secrets", options.valgrind_secrets);
			line("generate_all", options.generate_all);
			line("check_documentation", options.check_documentation);
			line("test", options.test);
			line("test_filter", options.test_filter);
			line("test_tags", options.test_tags);
			line("test_seed", options.test_seeded ? std::to_string(options.test_seed) : std::string());
			line("test_runs", options.test_runs);
			line("max_frame_size", options.max_frame_size);
			line("linker", options.linker);
			line("linker_script", options.linker_script.generic_string());
			line("sysroot", options.sysroot.generic_string());
			line("install_path", options.install_path.generic_string());
			for (const auto& [package, folder] : options.builtin_paths) {
				line("builtin", std::format("{} {}", static_cast<int>(package), folder.generic_string()));
			}
			for (const std::filesystem::path& folder : options.library_paths) {
				line("library_path", folder.generic_string());
			}
			for (const LinkedLibrary& library : options.libraries) {
				line("library", std::format("{} {}", library.root.generic_string(), library.file));
			}
			for (const auto& [name, value] : options.settings) {
				line("setting", std::format("{}={}", name, value));
			}
			for (const auto& [path, overlay] : options.overlays) {
				line("overlay", std::format("{} {}", path, overlay));
			}
			for (const std::string& pattern : options.allowed_warnings) {
				line("allow", pattern);
			}
			for (const std::string& pattern : options.denied_warnings) {
				line("deny", pattern);
			}
			return text;
		}

		// The files of program's packages but base's, with the .hsc files now in each package's folder, by path
		std::vector<std::string> program_files(ProgramInfo* program) {
			std::vector<std::string> paths;
			for (const auto& [path, package] : program->packages) {
				if (is_base_package(path)) {
					continue;
				}
				for (const auto& [file_name, file] : package->files) {
					paths.push_back(file_path_of(path, file_name));
				}
				std::error_code error;
				for (const auto& entry : std::filesystem::directory_iterator(std::string_view(*path), error)) {
					if (entry.path().extension() == ".hsc") {
						paths.push_back(file_path_of(path, intern(entry.path().filename().string())));
					}
				}
			}
			std::sort(paths.begin(), paths.end());
			paths.erase(std::unique(paths.begin(), paths.end()), paths.end());
			return paths;
		}

		// A path as the record keeps it: absolute, from the compiler's current folder, with its own separators
		std::string recorded_path(const std::string& path) {
			std::error_code error;
			return std::filesystem::absolute(std::filesystem::path(path), error).lexically_normal().string();
		}
	}

	FileRecord* file_record() {
		return current_record;
	}

	void set_file_record(FileRecord* record) {
		current_record = record;
	}

	void note_file_use(const std::string& path, FileUse use) {
		FileRecord* record = current_record;
		if (record == nullptr) {
			return;
		}
		std::scoped_lock<std::mutex> lock(record->mutex);
		record->uses.emplace_back(recorded_path(path), use);
	}

	std::string FileHashes::of(const std::string& path, const Options& reading) {
		{
			std::scoped_lock<std::mutex> lock(mutex);
			if (auto found = hashes.find(path); found != hashes.end()) {
				return found->second;
			}
		}
		std::string hash = kind_of(path);
		if (hash == "file") {
			bool read = false;
			const std::string bytes = reading_bytes(reading, path, read);
			hash = read ? hash_text(bytes) : "missing";
		}
		std::scoped_lock<std::mutex> lock(mutex);
		hashes[path] = hash;
		return hash;
	}

	std::string build_identity(ProgramInfo* build, const Options& build_options) {
		const std::string& identity = compiler_identity();
		if (identity.empty()) {
			return {};
		}
		std::string text(TARGET_VERSION);
		text += '\n';
		text += std::format("compiler={}\n", identity);
		text += options_text(build_options);
		FileHashes hashes;
		for (const std::string& path : program_files(build)) {
			text += std::format("build_file={} {}\n", hashes.of(path, build_options), path);
		}
		for (const auto& [folder, program] : loaded_package_programs()) {
			for (const std::string& path : program_files(program)) {
				text += std::format("loaded_file={} {}\n", hashes.of(path, build_options), path);
			}
		}
		for (const auto& [folder, listed] : folder_listings()) {
			text += std::format("listed={}\n", folder);
			for (const std::string& subfolder : listed) {
				text += std::format("  {}\n", subfolder);
			}
		}
		// What compiler.declares answered, not the files' bytes: an edit that keeps the answers keeps the identity
		for (const DeclarationAsked& asked : declarations_answered()) {
			text += std::format("declares={} {} {}\n", asked.folder, asked.name, asked.declared ? 1 : 0);
		}
		return hash_text(text);
	}

	std::string target_key(const std::string& identity, const std::string& registered, const Options& options) {
		if (identity.empty()) {
			return {};
		}
		return hash_text(std::format("{}\n{}\n{}", identity, registered, options_text(options)));
	}

	bool replay_target(const Options& options, const std::string& key, FileHashes& hashes, TargetResult& result) {
		const std::filesystem::path folder = entry_folder(options, key);
		bool read = false;
		const std::string record = read_bytes(folder / "record", read);
		if (!read) {
			return false;
		}
		std::istringstream lines(record);
		std::string line;
		if (!std::getline(lines, line) || line != TARGET_VERSION) {
			return false;
		}
		TargetResult found;
		struct Write {
			std::string kind;
			std::string path;
			std::string stored;
		};
		std::vector<Write> writes;
		// Each line: what it is, a space, and the rest; a path is always last, so it may hold spaces
		while (std::getline(lines, line)) {
			const size_t space = line.find(' ');
			const std::string kind = line.substr(0, space);
			const std::string rest = space == std::string::npos ? std::string() : line.substr(space + 1);
			if (kind == "output") {
				found.output = rest;
			}
			else if (kind == "outputs") {
				found.outputs_key = rest;
			}
			else if (kind == "read" || kind == "listed" || kind == "probed") {
				const size_t gap = rest.find(' ');
				if (gap == std::string::npos) {
					return false;
				}
				const std::string expected = rest.substr(0, gap);
				const std::string path = rest.substr(gap + 1);
				const std::string now = kind == "read" ? hashes.of(path, options) : kind == "listed" ? listing_of(path) : kind_of(path);
				if (now != expected) {
					return false;
				}
			}
			else if (kind == "wrote") {
				const size_t gap = rest.find(' ');
				if (gap == std::string::npos) {
					return false;
				}
				writes.push_back({ rest.substr(0, gap), rest.substr(gap + 1), std::format("w{}", writes.size()) });
			}
			else {
				return false;
			}
		}
		// Every file it wrote kept, before anything's written, so a missing one leaves everything as it was
		for (const Write& write : writes) {
			std::error_code error;
			if (write.kind == "file" && !std::filesystem::is_regular_file(folder / write.stored, error)) {
				return false;
			}
		}
		if (!found.outputs_key.empty() && !reuse_from_cache(options, found.outputs_key)) {
			return false;
		}
		for (const Write& write : writes) {
			std::error_code error;
			if (write.kind == "file") {
				copy_over(folder / write.stored, write.path);
			}
			else if (write.kind == "folder") {
				std::filesystem::create_directories(write.path, error);
			}
			else {
				std::filesystem::remove(write.path, error);
			}
		}
		// Used now, so it's among the last trimmed
		std::error_code error;
		std::filesystem::last_write_time(folder, std::filesystem::file_time_type::clock::now(), error);
		result = found;
		return true;
	}

	void keep_target(const Options& options, const std::string& key, ProgramInfo* program, FileRecord& record,
		FileHashes& hashes, const TargetResult& result) {
		std::vector<std::pair<std::string, FileUse>> uses;
		{
			std::scoped_lock<std::mutex> lock(record.mutex);
			uses = record.uses;
		}
		std::string text(TARGET_VERSION);
		text += '\n';
		text += std::format("output {}\n", result.output);
		if (!result.outputs_key.empty()) {
			text += std::format("outputs {}\n", result.outputs_key);
		}
		// What it read: its program's files, then what compile-time code read that it hadn't written itself first
		std::set<std::string> seen;
		for (const std::string& path : program_files(program)) {
			if (seen.insert(path).second) {
				text += std::format("read {} {}\n", hashes.of(path, options), path);
			}
		}
		std::set<std::string> written;
		std::vector<std::string> written_order;
		for (const auto& [path, use] : uses) {
			if (FileUse::UNTRACKED == use) {
				return;
			}
			if (FileUse::WRITTEN == use) {
				if (written.insert(path).second) {
					written_order.push_back(path);
				}
				continue;
			}
			// One of its program's files, read again by a check, is there already
			if (written.contains(path) || (FileUse::READ == use && seen.contains(path))
				|| !seen.insert(std::format("{} {}", static_cast<int>(use), path)).second) {
				continue;
			}
			const std::string now = FileUse::READ == use ? hashes.of(path, options) : FileUse::LISTED == use ? listing_of(path) : kind_of(path);
			text += std::format("{} {} {}\n", FileUse::READ == use ? "read" : FileUse::LISTED == use ? "listed" : "probed", now, path);
		}
		// Written beside where it goes, then renamed over the one before, so a reader never sees half an entry
		const std::filesystem::path folder = entry_folder(options, key);
		static std::atomic<uint64_t> made{ 0 };
		const uint64_t unique = (static_cast<uint64_t>(std::random_device{}()) << 32) ^ made.fetch_add(1);
		const std::filesystem::path partial = folder.parent_path() / std::format("{}.{:016x}.partial", key, unique);
		std::error_code error;
		std::filesystem::create_directories(partial, error);
		if (error) {
			return;
		}
		// What it wrote, as it is now: a file's bytes kept, by its place among the writes, a folder made, or nothing there
		for (size_t i = 0; i < written_order.size(); ++i) {
			const std::string& path = written_order[i];
			const std::string kind = kind_of(path);
			if (kind == "file" && !copy_over(path, partial / std::format("w{}", i))) {
				std::filesystem::remove_all(partial, error);
				return;
			}
			text += std::format("wrote {} {}\n", kind, path);
		}
		{
			std::ofstream out(partial / "record", std::ios::binary | std::ios::trunc);
			out << text;
			if (!out) {
				std::filesystem::remove_all(partial, error);
				return;
			}
		}
		std::filesystem::remove_all(folder, error);
		std::filesystem::rename(partial, folder, error);
		if (error) {
			std::filesystem::remove_all(partial, error);
			return;
		}
		kept_something = true;
	}
}
