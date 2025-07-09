#pragma once

#include <cstdint>

#include "memory/allocator.h"

namespace hemera {

	using UniqueID = size_t;

	enum class FunctionType {
		/// <summary>
		/// A normal function at the global level.
		/// </summary>
		GLOBAL,
		/// <summary>
		/// Functions that exist at compile time in order to evaluate any
		/// expressions stored in global (constant) values.
		/// </summary>
		IMPLIED,
		/// <summary>
		/// A function contained within a function.
		/// </summary>
		NESTED,
	};

	struct FunctionInfo {
		InternedString name;
		FunctionType type;
		MyVector<UniqueID> calls;
		MyVector<UniqueID> references;
	};

	enum class IdentifierType {
		ARRAY,
		ENUM,
		FUNCTION,
		NOT_YET_DETERMINED,
		POINTER,
		PRIMITIVE,
		STRUCT,
		TYPE,
		UNION,
	};

	union IdentifierAdditionalInfo {
		FunctionInfo function_info;
	};

	struct IdentifierInfo {
		IdentifierType identifier_type;
		IdentifierAdditionalInfo additional_info;
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
	};
}