#include "front_end/hlir_generation.h"
#include "util/logger.h"

//TODO(ches) remove this, shuts up unused warnings while we work
#define IGNORE_UNUSED(X) do{(void)sizeof(X);}while(false)

namespace hemera {

	/// <summary>
	/// Process a block into HLIR.
	/// </summary>
	/// <param name="node">The AST node representing/starting the block.</param>
	/// <param name="fn">The function we are processing.</param>
	/// <returns>The first basic block in the block.</returns>
	hlir::BasicBlock* hlir_process_block(ast::Node* node, hlir::Function* fn) {
		hlir::BasicBlock* block = fn->create_basic_block();

		for (size_t i = 0; i < node->children.size(); ++i) {
			ast::Node* child = node->children[i];
			if (ast::NodeType::RETURN == child->node_type) {

				hlir::Return* instr = block->create_instruction<hlir::Return>();

				LOG_ASSERT(child->children.size() > 0);

				//TODO(ches) expressions
				if (child->children.size() == 1) {
					ast::Node* value = child->children[0];
					if (ast::NodeType::VOID != value->node_type) {
						// expression
						IGNORE_UNUSED(instr);
					}
				}
				else if (child->children.size() > 1) {
					// multiple expressions
				}

				//TODO(ches) operand, destination
				continue;
			}
			if (ast::NodeType::DEFER == child->node_type) {
				//TODO(ches) handle this
			}
			if (ast::NodeType::BREAK == child->node_type) {
				//TODO(ches) handle this
			}
			if (ast::NodeType::CONTINUE == child->node_type) {
				//TODO(ches) handle this
			}
			if (ast::NodeType::DIRECTIVE == child->node_type) {
				//TODO(ches) handle this
			}
			// Expressions without results
			if (ast::NodeType::WITH_CLAUSE == child->node_type) {
				//TODO(ches) handle this
			}
			if (ast::NodeType::LOOP == child->node_type) {
				//TODO(ches) handle this
			}
			if (ast::NodeType::FOR_LOOP == child->node_type) {
				//TODO(ches) handle this
			}
			if (ast::NodeType::PUSH_CONTEXT == child->node_type) {
				//TODO(ches) handle this
			}
			if (ast::NodeType::SWITCH == child->node_type) {
				//TODO(ches) handle this
			}
			if (ast::NodeType::DEFINITION == child->node_type) {
				//TODO(ches) handle this
			}
			if (ast::NodeType::BLOCK == child->node_type) {
				hlir_process_block(child, fn);
			}
			// Expressions with results
			if (ast::NodeType::MATCH == child->node_type) {
				//TODO(ches) handle this
			}
			if (ast::NodeType::BINARY_OPERATOR == child->node_type) {
				//TODO(ches) handle this
			}

		}
		return block;
	}

	void hlir_process_function(WorkThreadData& executor, FunctionInfo* function) {
		//TODO(ches) finish this

		Allocator<>& alloc = executor.info->info_alloc;
		hlir::Function* fn = alloc.allocate_object<hlir::Function>();
		alloc.construct(fn, alloc);
		function->ir = fn;

		ast::Node* fn_root = function->node;

		// Decl (colon), colon/equals, signature, block
		LOG_ASSERT(fn_root->children.size() == 4);

		ast::Node* decl = fn_root->children[0];
		ast::Node* identifier = decl->children[0];
		ast::Node* explicit_type = decl->children.size() > 1
			? decl->children[1]
			: nullptr;
		ast::Node* colon_or_equals = fn_root->children[1];
		ast::Node* signature = fn_root->children[2];
		ast::Node* body = fn_root->children[3];

		//TODO(ches) do something with this, or remove it
		IGNORE_UNUSED(identifier);
		//TODO(ches) do something with this, or remove it
		IGNORE_UNUSED(explicit_type);
		//TODO(ches) do something with this, or remove it
		IGNORE_UNUSED(colon_or_equals);
		//TODO(ches) do something with this, or remove it
		IGNORE_UNUSED(signature);

		hlir_process_block(body, fn);
	}
}
