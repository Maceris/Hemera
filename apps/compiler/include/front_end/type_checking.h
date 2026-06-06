#pragma once

#include "front_end/hlir.h"
#include "front_end/front_end.h"
#include "parser/ast_types.h"

namespace hemera {
	/// <summary>
	/// Check the block.
	/// </summary>
	/// <param name="executor">Worker data.</param>
	/// <param name="file_location">Info about the file containing the node.</param>
	/// <param name="function">Function that contains the node.</param>
	/// <param name="parent_block">Lexical block that contains the node, which may be null.</param>
	/// <param name="node">Node we are type checking.</param>
	void type_check_block(WorkThreadData& executor,
		FileLocation file_location, FunctionInfo* function,
		ast::Node* parent_block, ast::Node* node);
	
	/// <summary>
	/// Check the definition.
	/// </summary>
	/// <param name="executor">Worker data.</param>
	/// <param name="file_location">Info about the file containing the node.</param>
	/// <param name="parent_block">Lexical block that contains the node, which may be null.</param>
	/// <param name="node">Node we are type checking.</param>
	void type_check_definition(WorkThreadData& executor, 
		FileLocation file_location, ast::Node* parent_block,
		ast::Node* node);

	/// <summary>
	/// Check the expression.
	/// </summary>
	/// <param name="executor">Worker data.</param>
	/// <param name="file_location">Info about the file containing the node.</param>
	/// <param name="parent_block">Lexical block that contains the node, which may be null.</param>
	/// <param name="node">Node we are type checking.</param>
	void type_check_expression(WorkThreadData& executor, 
		FileLocation file_location, ast::Node* parent_block,
		ast::Node* node);

	/// <summary>
	/// Check the function.
	/// </summary>
	/// <param name="executor">Worker data.</param>
	/// <param name="file_location">Info about the file containing the node.</param>
	/// <param name="parent_block">Lexical block that contains the node, which may be null.</param>
	/// <param name="function">Function we are checking.</param>
	void type_check_function(WorkThreadData& executor, 
		FileLocation file_location, ast::Node* parent_block,
		FunctionInfo* function);
}
