#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>

#include "front_end/hlir.h"
#include "front_end/type.h"
#include "lexer/token.h"
#include "memory/allocator.h"
#include "parser/ast_types.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Region.h"

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

	struct FunctionInfoMLIR {
		mlir::func::FuncOp func_op;
		
		FunctionInfoMLIR(mlir::func::FuncOp func_op);
		~FunctionInfoMLIR();
		FunctionInfoMLIR(const FunctionInfoMLIR&) = delete;
		FunctionInfoMLIR(FunctionInfoMLIR&&) = delete;
		FunctionInfoMLIR& operator=(const FunctionInfoMLIR&) = delete;
		FunctionInfoMLIR& operator=(FunctionInfoMLIR&&) = delete;
	};

	struct FunctionInfo {
		InternedString name;
		InternedString package;
		ast::Node* node;
		FunctionInfoMLIR* mlir_info;
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

	struct ProgramInfo {
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

		mlir::MLIRContext* context;
		mlir::OpBuilder* op_builder;
		mlir::ModuleOp* module;

		ProgramInfo(mlir::MLIRContext* mlir_context, 
			mlir::OpBuilder* mlir_op_builder,
			mlir::ModuleOp* mlir_module);
		~ProgramInfo();
		ProgramInfo(const ProgramInfo&) = delete;
		ProgramInfo(ProgramInfo&&) = delete;
		ProgramInfo& operator=(const ProgramInfo&) = delete;
		ProgramInfo& operator=(ProgramInfo&&) = delete;
	};
}
