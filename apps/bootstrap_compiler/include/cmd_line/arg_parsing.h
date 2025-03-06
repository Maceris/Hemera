#pragma once

#include <string>
#include <vector>

#include "memory/allocator.h"

namespace hemera {

	namespace arg_parse {

		struct ArgumentInfo {
			MyString option;
			MyVector<MyString> values;
		};

		MyVector<ArgumentInfo>* parse_arguments(int argc, char* argv[],
			Allocator<> alloc);
	}
	
}