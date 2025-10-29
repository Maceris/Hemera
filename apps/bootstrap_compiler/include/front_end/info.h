#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>

#include "front_end/hlir.h"
#include "front_end/type.h"
#include "lexer/token.h"
#include "memory/allocator.h"
#include "parser/ast_types.h"

namespace hemera {

	struct IdentifierInfo {
		TypeID type;
		builtin::_any default_value;
		bool has_value;
		char _padding[7] = { 0 };
	};

	struct ImportInfo {
		InternedString name;
		InternedString alias;
		InternedString location;
	};

	struct FunctionInfo {
		InternedString name;
		InternedString package;
		ast::Node* node;
		hlir::Function* ir;
		TypeInfoFunction type_info;
	};

	struct ExpressionInfo {
		ast::Node* node;
	};

	struct FileInfo {
		MyMap<InternedString, IdentifierInfo*> identifiers;
		MyVector<ImportInfo*> imports;
		MyVector<Token> tokens;
		ast::Node* ast_root;

		std::mutex imports_mutex;
		std::mutex identifiers_mutex;

		FileInfo();
		~FileInfo();
		FileInfo(const FileInfo&) = delete;
		FileInfo(FileInfo&&) = delete;
		FileInfo& operator=(const FileInfo&) = delete;
		FileInfo& operator=(FileInfo&&) = delete;
	};

	struct PackageInfo {
		InternedString full_path;
		MyMap<InternedString, FileInfo*> files;
		/// <summary>
		/// Filled out later, after files are processed, by combining
		/// all their info.
		/// </summary>
		MyMap<InternedString, IdentifierInfo> identifiers;

		std::mutex files_mutex;
		std::mutex identifiers_mutex;

		PackageInfo();
		~PackageInfo();
		PackageInfo(const PackageInfo&) = delete;
		PackageInfo(PackageInfo&&) = delete;
		PackageInfo& operator=(const PackageInfo&) = delete;
		PackageInfo& operator=(PackageInfo&&) = delete;
	};

	struct Info {
		MyMap<InternedString, PackageInfo*> packages;
		MyMap<ExpressionID, ExpressionInfo*> expressions;
		MyMap<FunctionID, FunctionInfo*> functions;
		Allocator<> node_alloc;
		Allocator<> info_alloc;

		std::atomic_size_t next_location_id;

		std::mutex types_mutex;
		std::mutex packages_mutex;
		std::mutex expressions_mutex;
		std::mutex functions_mutex;

		Info();
		~Info();
		Info(const Info&) = delete;
		Info(Info&&) = delete;
		Info& operator=(const Info&) = delete;
		Info& operator=(Info&&) = delete;
	};
}