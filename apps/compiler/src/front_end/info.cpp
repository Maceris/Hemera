#include "front_end/info.h"

namespace hemera {

	static bool is_separator(const ast::Node* node) {
		// A constant's separator is a COLON node; a variable's is the = token, kept as an IDENTIFIER
		return ast::NodeType::COLON == node->node_type
			|| (ast::NodeType::IDENTIFIER == node->node_type
				&& node->value.value != nullptr
				&& node->value.value->compare("=") == 0);
	}

	bool function_parts(ast::Node* definition, FunctionParts& parts) {
		parts = FunctionParts{};
		if (definition == nullptr
			|| ast::NodeType::DEFINITION != definition->node_type
			|| definition->children.empty()) {
			return false;
		}
		parts.name = definition->children[0];

		size_t i = 1;
		const size_t count = definition->children.size();
		while (i < count && !is_separator(definition->children[i])) {
			ast::Node* child = definition->children[i];
			if (ast::NodeType::ANNOTATION != child->node_type) {
				parts.explicit_type = child;
			}
			++i;
		}
		if (i >= count) {
			return false;
		}
		++i; // the separator

		while (i < count && ast::NodeType::ANNOTATION == definition->children[i]->node_type) {
			++i;
		}
		if (i >= count) {
			return false;
		}

		ast::Node* value = definition->children[i];
		if (ast::NodeType::FUNCTION == value->node_type) {
			parts.signature = value;
			if (i + 1 < count && ast::NodeType::BLOCK == definition->children[i + 1]->node_type) {
				parts.body = definition->children[i + 1];
			}
			return true;
		}
		if (ast::NodeType::UNINITIALIZED == value->node_type
			&& parts.explicit_type != nullptr
			&& ast::NodeType::FUNCTION == parts.explicit_type->node_type) {
			parts.signature = parts.explicit_type;
			return true;
		}
		return false;
	}

	FunctionInfoMLIR::FunctionInfoMLIR(mlir::func::FuncOp func_op)
		: func_op{ func_op }
	{}
	FunctionInfoMLIR::~FunctionInfoMLIR() = default;

	FunctionInfo::FunctionInfo()
		: name{}
		, file{}
		, package{}
		, node{}
		, mlir_info{}
		, type_info{}
		, is_exported{ false }
	{}

	FunctionInfo::~FunctionInfo() = default;

	FileInfo::FileInfo()
		: identifiers{}
		, imports{}
		, tokens{}
		, ast_root{ nullptr }
		, full_path{}
		, imports_mutex{}
		, identifiers_mutex{}
	{}
	FileInfo::~FileInfo() = default;

	PackageInfo::PackageInfo()
		: full_path{ nullptr }
		, self_reported_name{ nullptr }
		, files{}
		, identifiers{}
		, files_mutex{}
		, identifiers_mutex{}
	{}
	PackageInfo::~PackageInfo() = default;

	ProgramInfo::ProgramInfo(mlir::MLIRContext* mlir_context,
		mlir::OpBuilder* mlir_op_builder,
		mlir::ModuleOp* mlir_module)
		: packages{}
		, expressions{}
		, functions{}
		, node_alloc{}
		, next_location_id{}
		, types_mutex{}
		, packages_mutex{}
		, expressions_mutex{}
		, functions_mutex{}
		, context{ mlir_context }
		, op_builder{ mlir_op_builder }
		, module{ mlir_module }
		, debug_build{ false }
	{}
	ProgramInfo::~ProgramInfo() = default;
}
