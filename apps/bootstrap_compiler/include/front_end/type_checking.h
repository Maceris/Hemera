#pragma once

#include "front_end/hlir.h"
#include "front_end/front_end.h"
#include "parser/ast_types.h"

namespace hemera {
	void type_check_block(WorkThreadData& executor,
		FileLocation file_location, FunctionInfo* function,
		ast::Node* parent_block, ast::Node* node);
	void type_check_definition(WorkThreadData& executor, 
		FileLocation file_location, ast::Node* node);
	void type_check_expression(WorkThreadData& executor, 
		FileLocation file_location, ast::Node* node);
	void type_check_function(WorkThreadData& executor, 
		FileLocation file_location, FunctionInfo* function);
}
