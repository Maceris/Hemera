#pragma once

#include <string>

#include "front_end/checking.h"

namespace hemera {

	/*
	 * Bounds proofs (docs/types.md, Bounds Checking): every index into an array or string, and every
	 * slice's bounds, must be proven in bounds at compile time, from constants, conditions that lead
	 * to it, and loops over a range or the elements.
	 */

	/// <summary>
	/// Checks a function's checked body, reporting each index or slice it can't prove in bounds.
	/// Returns whether there were none.
	/// </summary>
	bool check_bounds(const CheckedBody& checked, ast::Node* body, TypeInfoFunction const* type, const std::string& file_path);

}
