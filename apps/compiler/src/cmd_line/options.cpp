#include "cmd_line/options.h"

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
	{}
	Options::~Options() = default;
}
