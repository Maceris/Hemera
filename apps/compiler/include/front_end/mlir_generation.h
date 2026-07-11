#pragma once

#include "front_end/front_end.h"
#include "parser/ast_types.h"

namespace hemera {
	mlir::Block* mlir_process_block(ast::Node* node, mlir::OpBuilder* builder,
		mlir::func::FuncOp fn);
	void mlir_process_expression(ast::Node* node, mlir::Block* containing_block);
	void mlir_process_function(WorkThreadData& executor, FunctionInfo* function);
}
