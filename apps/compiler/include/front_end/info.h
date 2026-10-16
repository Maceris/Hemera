#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>

#include "front_end/names.h"
#include "front_end/type.h"
#include "front_end/type_id.h"
#include "lexer/token.h"
#include "memory/allocator.h"
#include "parser/ast_types.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Region.h"

namespace hemera {

	struct FileInfo;
	struct PackageInfo;

	enum class IdentifierKind : uint8_t {
		UNKNOWN,
		CONSTANT,
		FUNCTION,
		TYPE,
		VARIABLE,
	};

	struct IdentifierInfo {
		TypeID type;
		/// <summary>
		/// The file the identifier is declared in.
		/// </summary>
		FileInfo* file = nullptr;
		/// <summary>
		/// The declaration, which also gives its location.
		/// </summary>
		ast::Node* node = nullptr;
		IdentifierKind kind = IdentifierKind::UNKNOWN;
		bool has_value;
		/// <summary>
		/// Marked #export, so part of the public interface.
		/// </summary>
		bool is_exported = false;
		char _padding[5] = { 0 };
	};

	struct ImportInfo {
		InternedString name;
		InternedString alias;
		InternedString location;
		/// <summary>
		/// The canonical path of the imported package's folder, once resolved.
		/// </summary>
		InternedString resolved_path = nullptr;
		/// <summary>
		/// The import statement, which also gives its location.
		/// </summary>
		ast::Node* node = nullptr;
		/// <summary>
		/// The imported package, once it has been resolved.
		/// </summary>
		PackageInfo* package = nullptr;
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
		FileInfo* file;
		PackageInfo* package;
		ast::Node* node;
		std::unique_ptr<FunctionInfoMLIR> mlir_info;
		TypeInfoFunction type_info;
		/// <summary>
		/// Marked #export, so part of the public interface.
		/// </summary>
		bool is_exported;
		char _padding[7] = { 0 };

		FunctionInfo();
		~FunctionInfo();
		FunctionInfo(const FunctionInfo&) = delete;
		FunctionInfo(FunctionInfo&&) = delete;
		FunctionInfo& operator=(const FunctionInfo&) = delete;
		FunctionInfo& operator=(FunctionInfo&&) = delete;
	};

	/// <summary>
	/// The parts of a function's definition, like name : type : fn(...) {...}.
	/// </summary>
	struct FunctionParts {
		ast::Node* name = nullptr;
		/// <summary>
		/// The type written before the second colon, if any.
		/// </summary>
		ast::Node* explicit_type = nullptr;
		/// <summary>
		/// The function's signature: the fn literal, or the explicit type for a declaration
		/// without a body (name : fn() : ---).
		/// </summary>
		ast::Node* signature = nullptr;
		/// <summary>
		/// The body, or null for a declaration without one.
		/// </summary>
		ast::Node* body = nullptr;
	};

	/// <summary>
	/// Splits a DEFINITION node whose value is a function into its parts.
	/// The node's children are the name, an optional explicit type, any annotations,
	/// the separator (: or =), then either the signature and body, or --- for a declaration.
	/// </summary>
	/// <returns>False if the definition isn't a function.</returns>
	bool function_parts(ast::Node* definition, FunctionParts& parts);

	struct ExpressionInfo {
		ast::Node* node;
	};

	struct FileInfo {
		MyMap<InternedString, IdentifierInfo*> identifiers;
		MyVector<ImportInfo*> imports;
		MyVector<Token> tokens;
		ast::Node* ast_root;
		InternedString full_path;

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
		InternedString self_reported_name;
		MyMap<InternedString, FileInfo*> files;
		/// <summary>
		/// Filled out later, after files are processed, by combining
		/// all their info.
		/// </summary>
		MyMap<InternedString, IdentifierInfo> identifiers;

		/// <summary>
		/// Used while modifying or checking the list of files.
		/// </summary>
		std::mutex files_mutex;
		/// <summary>
		/// Used for identifiers within the package, as well as the 
		/// self-reported name.
		/// </summary>
		std::mutex identifiers_mutex;

		PackageInfo();
		~PackageInfo();
		PackageInfo(const PackageInfo&) = delete;
		PackageInfo(PackageInfo&&) = delete;
		PackageInfo& operator=(const PackageInfo&) = delete;
		PackageInfo& operator=(PackageInfo&&) = delete;
	};

	struct ProgramInfo {
		/// <summary>
		/// Map from (canonical) package path to package info.
		/// </summary>
		MyMap<InternedString, PackageInfo*> packages;
		MyMap<ExpressionID, ExpressionInfo*> expressions;
		MyMap<FunctionID, FunctionInfo*> functions;
		Allocator<> node_alloc;

		std::atomic_size_t next_location_id;

		/// <summary>
		/// Every top-level declaration, and the work waiting on names and declarations.
		/// </summary>
		NameRegistry names;

		std::mutex types_mutex;
		std::mutex packages_mutex;
		std::mutex expressions_mutex;
		std::mutex functions_mutex;

		mlir::MLIRContext* context;
		mlir::OpBuilder* op_builder;
		mlir::ModuleOp* module;

		bool debug_build;

		/// <summary>
		/// What the compiler makes for compile-time code (middle_end/reflection.h), made the first time it's
		/// needed, and its mutex.
		/// </summary>
		std::shared_ptr<void> compile_time_data;
		std::mutex compile_time_data_mutex;

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
