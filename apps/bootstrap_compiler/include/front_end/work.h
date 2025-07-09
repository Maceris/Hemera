#pragma once

#include <cstdint>

#include "memory/allocator.h"

namespace hemera {

	using WorkID = size_t;

	enum class WorkType {
		EXECUTION,
		EXPRESSION_TO_FUNCTION,
		IL1_GENERATION,
		IMPORT,
		LEX,
		PARSE,
		TYPE_DEDUCTION,
		TYPE_CHECK,
	};

	struct Work {
		WorkID id;
		MyVector<WorkID> dependencies;//TODO(ches) not this way
		WorkType type;
		void* work_data;
	};

	struct WorkTracking {
		MyVector<Work*> queued;
		MyVector<Work*> blocked;
	};
}