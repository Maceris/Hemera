#pragma once

#include "memory/allocator.h"

namespace hemera {
	enum class IdentifierType {
		ARRAY,
		ENUM,
		FUNCTION,
		POINTER,
		PRIMITIVE,
		STRUCT,
		TYPE,
		UNION,
	};

	struct Identifier {
		MyString* name;
		MyString* package;
		IdentifierType identifier_type;
	};
}