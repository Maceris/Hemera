#pragma once

#include "front_end/type_id.h"

namespace hemera {

	enum class CompilerEventType {
		DISCOVERED,
		EVALUATED,
		TYPE_CHECK_PASSED,
		TYPE_DEDUCED,
	};

	struct CompilerEvent {
		CompilerEventType type;
		void* target;//TODO(ches) not this way
	};
}