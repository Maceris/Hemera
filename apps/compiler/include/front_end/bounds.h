#pragma once

#include <string>
#include <unordered_set>
#include <vector>

#include "front_end/checking.h"
#include "front_end/info.h"

namespace hemera {

	/*
	 * Bounds proofs (docs/types.md, Bounds Checking): every index into an array or string, and every
	 * slice's bounds, must be proven in bounds at compile time, from constants, conditions that lead
	 * to it, and loops over a range or the elements.
	 */

	/// <summary>
	/// Checks a function's checked body, reporting each index or slice it can't prove in bounds, unless reporting is
	/// false, when they're only counted. A call forgets what's known through pointers, unless writes_nothing names what
	/// it calls: functions that write no memory but their own locals. Returns whether every index was proven.
	/// </summary>
	bool check_bounds(const CheckedBody& checked, ast::Node* body, TypeInfoFunction const* type, const std::string& file_path,
		const std::unordered_set<const Declaration*>* writes_nothing = nullptr, bool reporting = true);

	/// <summary>
	/// Once every body is checked: works out which functions write no memory but their own locals, calling only those
	/// that don't either, then proves again, reporting, each function whose indexes weren't all proven without it
	/// (StackCheck::bounds_pending). Returns whether every one was.
	/// </summary>
	bool check_pending_bounds(const std::vector<StackCheck>& functions);

}
