#include <format>

#include "error/reporting.h"
#include "front_end/type_checking.h"
#include "util/logger.h"

//TODO(ches) remove this, shuts up unused warnings while we work
#define IGNORE_UNUSED(X) do{(void)sizeof(X);}while(false)

namespace hemera {

	void type_check_block(WorkThreadData& executor,
		FileLocation file_location, FunctionInfo* function,
		ast::Node* parent_block, ast::Node* node) {

		for (size_t i = 0; i < node->children.size(); ++i) {
			ast::Node* child = node->children[i];
			if (ast::NodeType::RETURN == child->node_type) {
				//TODO(ches) handle this
				
				const size_t expected_output_count = function->type_info.output.size();
				const size_t actual_output_count = child->children.size();

				for (size_t j = 0; j < actual_output_count; j++) {
					ast::Node* return_value = child->children[j];

					type_check_expression(executor, file_location,
						parent_block, return_value);
				}

				if (expected_output_count != actual_output_count) {
					std::string expected = "";
					std::string actual = "";

					for (size_t j = 0; j < expected_output_count; j++) {
						const FunctionOutput& output = function->type_info.output[j];
						TypeInfo* type = output.type;

						expected += to_string(type);
						if (j < expected_output_count - 1) {
							expected += ", ";
						}
					}

					for (size_t j = 0; j < actual_output_count; j++) {
						TypeInfo* type = child->children[j]->type;

						actual += to_string(type);
						if (j < actual_output_count - 1) {
							actual += ", ";
						}
					}

					std::string details = std::format("Expected: {}. Found: {}.",
						expected, actual);

					report_error(ErrorCode::E4004, *file_location.file_name,
						child->value.line_number,
						child->value.column_number,
						details);
				}
			}
			else if (ast::NodeType::DEFER == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::BREAK == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::CONTINUE == child->node_type) {
				//TODO(ches) handle this
			}
			// Expressions without results
			else if (ast::NodeType::WITH_CLAUSE == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::LOOP == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::FOR_LOOP == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::PUSH_CONTEXT == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::SWITCH == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::DEFINITION == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::BLOCK == child->node_type) {
				type_check_block(executor, file_location, function, node, child);
			}
			// Expressions with results
			else if (ast::NodeType::MATCH == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::BINARY_OPERATOR == child->node_type) {
				//TODO(ches) handle this
			}
		}
	}

	void type_check_definition(WorkThreadData& executor, 
		FileLocation file_location, ast::Node* parent_block, ast::Node* node) {

		IGNORE_UNUSED(executor);
		IGNORE_UNUSED(file_location);
		IGNORE_UNUSED(parent_block);
		IGNORE_UNUSED(node);

		//TODO(ches) complete this
	}

	void type_check_expression(WorkThreadData& executor, 
		FileLocation file_location, ast::Node* parent_block, ast::Node* node) {

		IGNORE_UNUSED(executor);
		IGNORE_UNUSED(file_location);
		IGNORE_UNUSED(parent_block);
		IGNORE_UNUSED(node);
		//TODO(ches) complete this
	}

	void type_check_function(WorkThreadData& executor, 
		FileLocation file_location, ast::Node* parent_block, 
		FunctionInfo* function) {

		IGNORE_UNUSED(parent_block);
		IGNORE_UNUSED(executor);

		LOG_ASSERT(function != nullptr);
		if (function == nullptr) {
			return;
		}

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
			type_check_block(executor, file_location, function, nullptr, body);
		}

		//TODO(ches) complete this
	}
}