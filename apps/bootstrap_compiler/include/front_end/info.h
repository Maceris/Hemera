#pragma once

#include <cstdint>

#include "front_end/type_id.h"
#include "front_end/type.h"
#include "memory/allocator.h"

namespace hemera {

	struct IdentifierInfo {
		TypeID type;
		builtin::_any value;
		bool has_value;
	};

	struct FileInfo {
		MyMap<InternedString, IdentifierInfo> identifiers;
	};

	struct PackageInfo {
		const InternedString full_path;
		MyMap<InternedString, FileInfo> files;
	};

	struct Info {
		MyMap<InternedString, PackageInfo> packages;
		MyMap<TypeID, TypeInfo> all_types;
	};
}