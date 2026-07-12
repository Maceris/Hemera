#include "front_end/info.h"

namespace hemera {

	FunctionInfoMLIR::FunctionInfoMLIR(mlir::func::FuncOp func_op)
		: func_op{ func_op }
	{}
	FunctionInfoMLIR::~FunctionInfoMLIR() = default;

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

	ProgramInfo::ProgramInfo(mlir::MLIRContext* mlir_context,
		mlir::OpBuilder* mlir_op_builder,
		mlir::ModuleOp* mlir_module)
		: packages{}
		, expressions{}
		, functions{}
		, node_alloc{}
		, next_location_id{}
		, types_mutex{}
		, packages_mutex{}
		, expressions_mutex{}
		, functions_mutex{}
		, context{ mlir_context }
		, op_builder{ mlir_op_builder }
		, module{ mlir_module }
	{}
	ProgramInfo::~ProgramInfo() = default;
}
