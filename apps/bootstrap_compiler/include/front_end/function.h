#pragma once

#include "memory/allocator.h"

namespace hemera {
	enum class FunctionType {
		/// <summary>
		/// A normal function at the global level.
		/// </summary>
		GLOBAL,
		/// <summary>
		/// Functions that exist at compile time in order to evaluate any
		/// expressions stored in global (constant) values.
		/// </summary>
		IMPLIED,
		/// <summary>
		/// A function contained within a function.
		/// </summary>
		NESTED,
	};

	struct Function {
		MyString* name;
		FunctionType type;
		MyVector<Function*> calls;
		MyVector<Function*> references;
	};
}