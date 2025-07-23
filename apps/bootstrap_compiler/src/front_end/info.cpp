#include "front_end/info.h"

namespace hemera {

	FileInfo::FileInfo()
		: identifiers{}
		, imports{}
		, tokens{}
		, ast_root{ nullptr }
		, imports_mutex{}
		, identifiers_mutex{}
	{}
	FileInfo::~FileInfo() = default;

	PackageInfo::PackageInfo()
		: full_path{}
		, files{}
		, identifiers{}
		, files_mutex{}
		, identifiers_mutex{}
	{}
	PackageInfo::~PackageInfo() = default;

	Info::Info()
		: all_types{}
		, packages{}
		, expressions{}
		, functions{}
		, node_alloc{}
		, info_alloc{}
		, types_mutex{}
		, packages_mutex{}
		, expressions_mutex{}
		, functions_mutex{}
	{}
	Info::~Info() = default;
}