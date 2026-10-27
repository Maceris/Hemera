#pragma once

#include <string>
#include <vector>

#include "front_end/checking.h"
#include "front_end/info.h"

namespace hemera {

	/*
	 * The checks on pointers to the stack (docs/memory.md, Pointers to the Stack): nothing that
	 * points into a stack frame, or a block's part of one, can outlive it. Each function is checked
	 * from what checking its body recorded, the signatures of what it calls, and which of their
	 * parameters each gives back pointers from, worked out from their bodies: so every body is checked
	 * at once, once all of them are.
	 */

	/// <summary>
	/// Checks every function's checked body: which parameters each gives back pointers from, until that
	/// settles across them all, then each place a pointer into the stack could outlive what it points to,
	/// reported. Returns whether there were none.
	/// </summary>
	bool check_all_stack_pointers(std::vector<StackCheck>& functions);

}
