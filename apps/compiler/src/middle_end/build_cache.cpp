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
#include <string>
#include <system_error>
#include <thread>
#include <utility>
#include <vector>

#include "cmd_line/options.h"

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
}
