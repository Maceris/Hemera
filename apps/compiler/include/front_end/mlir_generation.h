#pragma once

#include "front_end/front_end.h"
#include "parser/ast_types.h"

namespace hemera {
	mlir::Block* mlir_process_block_in_function(ProgramInfo* program_info,
		ast::Node* node, mlir::OpBuilder* builder,
		FunctionInfo* function);
	mlir::Value* mlir_process_expression(ProgramInfo* program_info,
		ast::Node* node, mlir::Block* containing_block,
		InternedString file_path);
	void mlir_process_function(WorkThreadData& executor,
		FunctionInfo* function);
}
