#pragma once

#include "front_end/front_end.h"
#include "parser/ast_types.h"

namespace hemera {
	/// <summary>
	/// Emits a block's statements at the builder's insertion point, in the current MLIR block.
	/// function_level is true for the function's own body, false inside a nested scope.
	/// </summary>
	/// <returns>True if the statements ended the block (a return or continue), so nothing after
	/// them is reachable.</returns>
	bool mlir_emit_block_contents(ProgramInfo* program_info,
		ast::Node* node, mlir::OpBuilder* builder,
		FunctionInfo* function, bool function_level);
	mlir::Value* mlir_process_expression(ProgramInfo* program_info,
		ast::Node* node, mlir::Block* containing_block,
		InternedString file_path);
	/// <summary>
	/// Adds a function to the program's module, named as declared, with its body in the entry block.
	/// </summary>
	/// <returns>False if function->node isn't a function definition.</returns>
	bool mlir_process_function(ProgramInfo* program_info,
		FunctionInfo* function);
}
