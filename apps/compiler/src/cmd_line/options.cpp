#include "cmd_line/options.h"

#include <algorithm>
#include <system_error>

namespace hemera {
	Options::Options()
		: build_extent{ BuildExtent::LINK }
		, optimization_level{ OptimizationLevel::O2 }
		, architecture{ ArchType::x86_64 }
		, subarchitecture{ SubArchType::NoSubArch }
		, vendor{ VendorType::Intel }
		, os{ OSType::Win32 }
		, environment{ EnvironmentType::MSVC }
		, object_format{ ObjectFormatType::COFF }
		, code_model{ TargetCodeModel::Default }
		, relocation_model{ TargetRelocationModel::PositionIndependent }
		, stack_check{ TargetStackCheck::Off }
		, cpu{ "generic" }
		, cpu_features{ "" }
		, input{ std::filesystem::current_path() }
		, install_path{ std::filesystem::current_path() }
		, builtin_paths{}
		, output_name{ "" }
		, entry{ "main" }
		, linker_script{}
		, sysroot{}
		, debug_info{ false }
		, generate_all{ false }
		, startup_code{ true }
		, red_zone{ true }
		, address_zero_is_memory{ false }
		, control_flow_integrity{ false }
		, coverage{ false }
		, model_checked{ false }
	{}
	Options::~Options() = default;

	std::string output_stem(const std::string& name, OSType os, bool typed_library) {
		if (OSType::Win32 != os) {
			return name;
		}
		const std::string_view extension = typed_library ? ".dll" : ".exe";
		if (name.size() <= extension.size()) {
			return name;
		}
		for (size_t i = 0; i < extension.size(); ++i) {
			const char given = name[name.size() - extension.size() + i];
			if ((given >= 'A' && given <= 'Z' ? given - 'A' + 'a' : given) != extension[i]) {
				return name;
			}
		}
		return name.substr(0, name.size() - extension.size());
	}

	std::string overlay_key(const std::filesystem::path& path) {
		std::error_code error;
		std::filesystem::path full = std::filesystem::weakly_canonical(std::filesystem::absolute(path, error), error);
		if (error) {
			full = std::filesystem::absolute(path, error).lexically_normal();
		}
		std::string key = full.generic_string();
#ifdef _WIN32
		std::transform(key.begin(), key.end(), key.begin(), [](char c) { return c >= 'A' && c <= 'Z' ? static_cast<char>(c - 'A' + 'a') : c; });
#endif
		return key;
	}

	const std::string* find_overlay(const Options& options, const std::filesystem::path& path) {
		if (options.overlays.empty()) {
			return nullptr;
		}
		const std::string key = overlay_key(path);
		for (const auto& [replaced, file] : options.overlays) {
			if (replaced == key) {
				return &file;
			}
		}
		return nullptr;
	}
}
