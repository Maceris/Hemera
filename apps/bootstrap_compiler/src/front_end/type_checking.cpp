#include "front_end/type_checking.h"

namespace hemera {
	void type_check_definition(WorkThreadData& executor, ast::Node* node) {
		if (executor.doing_work && node) {
			//TODO(ches) remove this
		}
		//TODO(ches) complete this
	}

	void type_check_expression(WorkThreadData& executor, ast::Node* node) {
		if (executor.doing_work && node) {
			//TODO(ches) remove this
		}
		//TODO(ches) complete this
	}

	void type_check_function(WorkThreadData& executor, FunctionInfo* function) {
		if (executor.doing_work && function) {
			//TODO(ches) remove this
		}
		//TODO(ches) complete this
	}
}