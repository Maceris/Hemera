#pragma once

#include "front_end/hlir.h"
#include "front_end/front_end.h"
#include "parser/ast_types.h"

namespace hemera {
	hlir::BasicBlock* hlir_process_block(ast::Node* node, hlir::Function* fn);
	void hlir_process_expression(ast::Node* node, hlir::BasicBlock* containing_block);
	void hlir_process_function(WorkThreadData& executor, FunctionInfo* function);
}
