#include "front_end/mlir_generation.h"
#include "util/logger.h"

#include "mlir/IR/MLIRContext.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"

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
				//TODO(ches) deferred op
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

		return block;
	}

	void hlir_process_expression(ast::Node* node, hlir::BasicBlock* containing_block) {
		//TODO(ches) finish this
		IGNORE_UNUSED(node);
		IGNORE_UNUSED(containing_block);
	}

	void hlir_process_function(WorkThreadData& executor, FunctionInfo* function) {
		//TODO(ches) finish this

		Allocator<>& alloc = executor.program_info->info_alloc;
		hlir::Function* fn = alloc.allocate_object<hlir::Function>();
		alloc.construct(fn, alloc);

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

	void mlir_process_function(WorkThreadData& executor, FunctionInfo* function) {
		//TODO(ches) finish this

		ast::Node* fn_root = function->node;
		Allocator<>& alloc = executor.program_info->info_alloc;

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
		//TODO(ches) do something with this, or remove it
		IGNORE_UNUSED(body);

		//TODO(ches) figure out from the signature

		mlir::OpBuilder* builder = executor.program_info->op_builder;
		mlir::ModuleOp* module = executor.program_info->module;

		llvm::SmallVector<mlir::Type, 0> argumentTypes = {};
		llvm::SmallVector<mlir::Type, 0> resultTypes = {};

		mlir::FunctionType function_type = 
			builder->getFunctionType(argumentTypes, resultTypes);

		builder->setInsertionPointToEnd(module->getBody());

		mlir::Location location = builder->getUnknownLoc();
		//TODO(ches) figure out from the signature
		llvm::StringRef function_name = "func_I_guess";

		mlir::func::FuncOp func_op = mlir::func::FuncOp::create(location,
			function_name, function_type);

		mlir::Block* entry_block = func_op.addEntryBlock();

		builder->setInsertionPointToStart(entry_block);
		mlir::func::ReturnOp::create(*builder, location);

		function->mlir_info = alloc.new_object<FunctionInfoMLIR>(func_op);
	}
}
