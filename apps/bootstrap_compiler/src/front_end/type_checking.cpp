#include <format>

#include "error/reporting.h"
#include "front_end/type_checking.h"
#include "util/logger.h"

//TODO(ches) remove this, shuts up unused warnings while we work
#define IGNORE_UNUSED(X) do{(void)sizeof(X);}while(false)


namespace hemera {
	void type_check_definition(WorkThreadData& executor, 
		FileLocation file_location, ast::Node* node) {

		IGNORE_UNUSED(executor);
		IGNORE_UNUSED(file_location);
		IGNORE_UNUSED(node);

		//TODO(ches) complete this
	}

	void type_check_expression(WorkThreadData& executor, 
		FileLocation file_location, ast::Node* node) {

		IGNORE_UNUSED(executor);
		IGNORE_UNUSED(file_location);
		IGNORE_UNUSED(node);
		//TODO(ches) complete this
	}

	void type_check_function(WorkThreadData& executor, 
		FileLocation file_location, FunctionInfo* function) {

		IGNORE_UNUSED(executor);

		LOG_ASSERT(function != nullptr);

		ast::Node* fn_root = function->node;

		if (fn_root->children.size() < 3 || fn_root->children.size() > 4) {
			report_error(ErrorCode::E4001, *file_location.file_name,
				fn_root->value.line_number,
				fn_root->value.column_number);
		}

		ast::Node* decl = fn_root->children[0];
		ast::Node* identifier = decl->children[0];
		ast::Node* explicit_type = decl->children.size() > 1
			? decl->children[1]
			: nullptr;
		ast::Node* colon_or_equals = fn_root->children[1];
		ast::Node* signature = fn_root->children[2];
		ast::Node* body = fn_root->children.size() >= 4 
			? fn_root->children[3]
			: nullptr;

		IGNORE_UNUSED(explicit_type);
		IGNORE_UNUSED(colon_or_equals);
		IGNORE_UNUSED(signature);

		function->name = identifier->value.value;

		if (explicit_type == nullptr) {
			//TODO(ches) deduce type
		}
		if (body != nullptr) {
			//TODO(ches) type check body
		}

		//TODO(ches) complete this
	}
}