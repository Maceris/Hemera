#include "front_end/mlir_generation.h"
#include "util/logger.h"

#include "mlir/IR/MLIRContext.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "hmir/hmir_dialect.h"
#include "hmir/hmir_ops.h"

//TODO(ches) remove this, shuts up unused warnings while we work
#define IGNORE_UNUSED(X) do{(void)sizeof(X);}while(false)

namespace hemera {

	static mlir::Location location_of(ProgramInfo* program_info, mlir::OpBuilder* builder,
		InternedString file_path, ast::Node* node) {

		if (!program_info->debug_build || file_path == nullptr) {
			return builder->getUnknownLoc();
		}
		return mlir::FileLineColLoc::get(builder->getStringAttr(file_path->c_str()),
			node->value.line_number, node->value.column_number);
	}

	static bool has_terminator(mlir::Block* block) {
		return !block->empty() && block->back().hasTrait<mlir::OpTrait::IsTerminator>();
	}

	/*
	 * Emits a scope: a region of its own, so defers and declarations inside it end with it.
	 * The scope falls through with an end op unless its contents already ended it.
	 */
	static void mlir_emit_scope(ProgramInfo* program_info, ast::Node* node,
		mlir::OpBuilder* builder, FunctionInfo* function) {

		InternedString file_path = function->file != nullptr ? function->file->full_path : nullptr;
		mlir::Location loc = location_of(program_info, builder, file_path, node);

		hmir::HemeraScopeOp scope = hmir::HemeraScopeOp::create(*builder, loc);
		mlir::OpBuilder::InsertionGuard guard(*builder);
		mlir::Block* block = builder->createBlock(&scope.getBodyRegion());

		mlir_emit_block_contents(program_info, node, builder, function, false);

		builder->setInsertionPointToEnd(block);
		if (!has_terminator(block)) {
			hmir::HemeraEndOp::create(*builder, loc);
		}
	}

	bool mlir_emit_block_contents(ProgramInfo* program_info,
		ast::Node* node, mlir::OpBuilder* builder, FunctionInfo* function,
		bool function_level) {

		InternedString file_path = function->file != nullptr ? function->file->full_path : nullptr;

		for (size_t i = 0; i < node->children.size(); ++i) {
			ast::Node* child = node->children[i];
			if (ast::NodeType::RETURN == child->node_type) {
				LOG_ASSERT(child->children.size() > 0);

				if (!function_level) {
					//TODO(ches) a return from inside a scope needs an HMIR op, since func.return
					// must be directly in the function, and the scopes' defers must run first
				}
				else if (ast::NodeType::VOID == child->children[0]->node_type) {
					mlir::func::ReturnOp::create(*builder,
						location_of(program_info, builder, file_path, child));
					// Anything after a return can't be reached
					return true;
				}
				//TODO(ches) return the values, once expressions are generated
				for (size_t j = 0; j < child->children.size(); ++j) {
					ast::Node* value = child->children[j];
					mlir::Value* expr = mlir_process_expression(
						program_info, value, builder->getBlock(), file_path);
					IGNORE_UNUSED(expr);
				}
			}
			else if (ast::NodeType::DEFER == child->node_type) {
				LOG_ASSERT(child->children.size() == 1);
				mlir::Location loc = location_of(program_info, builder, file_path, child);

				hmir::HemeraDeferOp defer_op = hmir::HemeraDeferOp::create(*builder, loc);
				// Back up where we are at so the block doesn't mess us up
				mlir::OpBuilder::InsertionGuard guard(*builder);

				ast::Node* defer_target = child->children[0];
				builder->createBlock(&defer_op.getBodyRegion());
				mlir_process_expression(program_info,
					defer_target, builder->getBlock(), file_path);
				hmir::HemeraEndOp::create(*builder, loc);
			}
			else if (ast::NodeType::BREAK == child->node_type) {
				//TODO(ches) handle this
				// hmir::HemeraBreakOp::create(*builder, loc, depth);
			}
			else if (ast::NodeType::CONTINUE == child->node_type) {
				hmir::HemeraContinueOp::create(*builder,
					location_of(program_info, builder, file_path, child));
				return true;
			}
			// Expressions without results
			else if (ast::NodeType::WITH_CLAUSE == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::LOOP == child->node_type) {
				//TODO(ches) handle this
				// hmir::HemeraLoopOp loop = hmir::HemeraLoopOp::create(*builder, loc);
				// mlir::OpBuilder::InsertionGuard guard(*builder);
				// builder->createBlock(&loop.getBodyRegion());
			}
			else if (ast::NodeType::FOR_LOOP == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::PUSH_CONTEXT == child->node_type) {
				//TODO(ches) store the current context, and restore it when the scope ends
				// The block is the last child, after the name and the overrides or from value
				ast::Node* body = child->children.back();
				mlir_emit_scope(program_info, body, builder, function);
			}
			else if (ast::NodeType::SWITCH == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::DEFINITION == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::BLOCK == child->node_type) {
				mlir_emit_scope(program_info, child, builder, function);
			}
			// Expressions with results
			else if (ast::NodeType::MATCH == child->node_type) {
				//TODO(ches) handle this
			}
			else if (ast::NodeType::BINARY_OPERATOR == child->node_type) {
				//TODO(ches) handle this
			}
		}
		return false;
	}

	mlir::Value* mlir_process_expression(ProgramInfo* program_info,
		ast::Node* node, mlir::Block* containing_block,
		InternedString file_path) {
		//TODO(ches) finish this
		IGNORE_UNUSED(program_info);
		IGNORE_UNUSED(node);
		IGNORE_UNUSED(containing_block);
		IGNORE_UNUSED(file_path);
		return nullptr;
	}

	bool mlir_process_function(ProgramInfo* program_info, FunctionInfo* function) {
		FunctionParts parts;
		if (!function_parts(function->node, parts)) {
			LOG_ERROR("Generating code for a definition that isn't a function");
			return false;
		}

		mlir::OpBuilder* builder = program_info->op_builder;
		mlir::ModuleOp* module = program_info->module;
		mlir::OpBuilder::InsertionGuard guard(*builder);

		//TODO(ches) figure out from the signature, once types are resolved
		llvm::SmallVector<mlir::Type, 5> argument_types = {};
		llvm::SmallVector<mlir::Type, 1> result_types = {};

		mlir::FunctionType function_type =
			builder->getFunctionType(argument_types, result_types);

		InternedString file_path = function->file != nullptr ? function->file->full_path : nullptr;
		mlir::Location location = location_of(program_info, builder, file_path, parts.name);
		llvm::StringRef function_name = parts.name->value.value->c_str();

		builder->setInsertionPointToEnd(module->getBody());
		mlir::func::FuncOp func_op = mlir::func::FuncOp::create(*builder, location,
			function_name, function_type);
		function->mlir_info = std::make_unique<FunctionInfoMLIR>(func_op);

		if (parts.body == nullptr) {
			// A declaration without a body, like an intrinsic: external to this module
			func_op.setPrivate();
			return true;
		}

		mlir::Block* entry_block = func_op.addEntryBlock();
		builder->setInsertionPointToStart(entry_block);

		mlir_emit_block_contents(program_info, parts.body, builder, function, true);

		builder->setInsertionPointToEnd(entry_block);
		if (!has_terminator(entry_block)) {
			mlir::func::ReturnOp::create(*builder, location);
		}
		return true;
	}
}
