#pragma once

#include <cstdint>
#include <vector>

namespace hemera {

	struct TypeInfo;

	/// <summary>
	/// A type's schema (docs/types.md, Schemas), written by the compiler itself: the same bytes base's
	/// runtime.schema_try_write gives for the type's descriptor, for debug info, where no compile-time code runs
	/// (docs/compilation.md, Debug Info). Plain aliases are the type they name.
	/// </summary>
	/// <param name="type">The type described; null gives an empty result.</param>
	/// <returns>"HSCH", the version, the type count, then each type reached, breadth first.</returns>
	std::vector<uint8_t> write_schema(TypeInfo const* type);
}
