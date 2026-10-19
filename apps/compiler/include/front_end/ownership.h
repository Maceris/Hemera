#pragma once

#include <string>

#include "front_end/checking.h"
#include "parser/ast_types.h"

namespace hemera {
	/// <summary>
	/// docs/memory.md, Owned Types: each owner of an #owned value in a function body is released or moved
	/// on every path out of its scope, isn't used once it's moved, and isn't dropped. Reports what isn't
	/// (E4035), and gives whether everything was.
	/// </summary>
	bool check_ownership(const CheckedBody& checked, ast::Node* function_node, ast::Node* body, TypeInfoFunction const* type,
		const std::string& file_path);
}
