#pragma once

#include <string>

#include "front_end/checking.h"

namespace hemera {

	/*
	 * The checks on pointers to the stack (docs/memory.md, Pointers to the Stack): nothing that
	 * points into a stack frame, or a block's part of one, can outlive it. Each function is checked on
	 * its own, from what checking its body recorded and the signatures of what it calls.
	 */

	/// <summary>
	/// Checks a function's checked body, reporting each place a pointer into the stack could
	/// outlive what it points to. Returns whether there were none.
	/// </summary>
	bool check_stack_pointers(const CheckedBody& checked, ast::Node* body, TypeInfoFunction const* type,
		const std::string& file_path);

}
