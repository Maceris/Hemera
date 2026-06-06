#pragma once

#include "llvm/IR/Module.h"

namespace hemera {
	struct Backend {
		void destroy();
		void generate_object_file();
		void initialize();
		void link();
	};

}
