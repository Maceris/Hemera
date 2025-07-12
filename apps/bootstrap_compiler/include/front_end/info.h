#pragma once

#include <cstdint>

#include "front_end/type.h"
#include "memory/allocator.h"
#include "parser/ast_types.h"

namespace hemera {

	struct IdentifierInfo {
		TypeID type;
		builtin::_any value;
		bool has_value;
	};

	struct ImportInfo {
		InternedString name;
		InternedString alias;
	};

	struct FunctionInfo {
		InternedString name;
		InternedString package;
		ast::FlatNode* node;
	};

	struct ExpressionInfo {
		ast::FlatNode* node;
	};

	struct FileInfo {
		MyMap<InternedString, IdentifierInfo> identifiers;
		MyVector<ImportInfo> imports;
	};

	struct PackageInfo {
		InternedString full_path;
		MyMap<InternedString, FileInfo> files;
		/// <summary>
		/// Filled out later, after files are processed, by combining
		/// all their info.
		/// </summary>
		MyMap<InternedString, IdentifierInfo> identifiers;
	};

	struct Info {
		MyMap<TypeID, TypeInfo> all_types;
		MyMap<InternedString, PackageInfo> packages;
		MyMap<ExpressionID, ExpressionInfo> expressions;
		MyMap<FunctionID, FunctionInfo> functions;
	};
}