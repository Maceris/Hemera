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
		, cpu{ "generic" }
		, cpu_features{ "" }
		, output_name{ "application" }
	{}
	Options::~Options() = default;
}
