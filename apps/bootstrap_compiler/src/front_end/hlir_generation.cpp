#include "front_end/hlir_generation.h"
#include "util/logger.h"

//TODO(ches) remove this, shuts up unused warnings while we work
#define IGNORE_UNUSED(X) do{(void)sizeof(X);}while(false)

namespace hemera {

	struct DeferredExpression {
		ast::Node* expression = nullptr;
		DeferredExpression* next = nullptr;
	};

	static void free_deferred_expressions(DeferredExpression* expr) {
		if (nullptr == expr) {
			return;
		}
		DeferredExpression* next = expr->next;
		delete expr;
		free_deferred_expressions(next);
	}

	/// <summary>
	/// Process a block into HLIR.
	/// </summary>
	/// <param name="node">The AST node representing/starting the block.</param>
	/// <param name="fn">The function we are processing.</param>
	/// <returns>The first basic block in the block.</returns>
	hlir::BasicBlock* hlir_process_block(ast::Node* node, hlir::Function* fn) {
		hlir::BasicBlock* block = fn->create_basic_block();

		DeferredExpression* deferred = nullptr;

		for (size_t i = 0; i < node->children.size(); ++i) {
			ast::Node* child = node->children[i];
			if (ast::NodeType::RETURN == child->node_type) {
				//TODO(ches) deferred expression(s)

				hlir::Return* instr = block->create_instruction<hlir::Return>();

				LOG_ASSERT(child->children.size() > 0);

				//TODO(ches) handle the actual return part
				if (ast::NodeType::VOID != child->children[0]->node_type) {
					for (size_t j = 0; j < child->children.size(); ++j) {
						ast::Node* value = child->children[i];
						hlir_process_expression(value, block);
					}
				}
				block->instructions.push_back(instr);
			}
			else if (ast::NodeType::DEFER == child->node_type) {
				//NTOE(ches) slap it onto the stack of deferred expressions
				DeferredExpression* next = new DeferredExpression();
				next->expression = child->children[0];
				next->next = deferred;
				deferred = next;
			}
			else if (ast::NodeType::BREAK == child->node_type) {
				//TODO(ches) deferred expression(s)
				//TODO(ches) handle this
			}
			else if (ast::NodeType::CONTINUE == child->node_type) {
				//TODO(ches) deferred expression(s)
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
				//TODO(ches) store current context
				InternedString context_name = child->children[0]->value.value;
				IGNORE_UNUSED(context_name);
				hlir_process_block(child->children[1], fn);
				//TODO(ches) restore old context
			}
			else if (ast::NodeType::SWITCH == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::DEFINITION == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::BLOCK == child->node_type) {
				hlir_process_block(child, fn);
			}
			// Expressions with results
			else if (ast::NodeType::MATCH == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::BINARY_OPERATOR == child->node_type) {
				//TODO(ches) handle this
			}

		}

		//TODO(ches) deferred expression(s)

		free_deferred_expressions(deferred);

		return block;
	}

	void hlir_process_expression(ast::Node* node, hlir::BasicBlock* containing_block) {
		//TODO(ches) finish this
		IGNORE_UNUSED(node);
		IGNORE_UNUSED(containing_block);
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
