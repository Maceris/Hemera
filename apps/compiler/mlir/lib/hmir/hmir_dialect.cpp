#include "hmir/hmir_dialect.h"
#include "hmir/hmir_ops.h"

namespace mlir::hmir {
	hmir_dialect::hmir_dialect(mlir::MLIRContext* context)
		: Dialect(getDialectNamespace(), context) {
		addOperations<
#define GET_OP_LIST
#include "hmir/hmir_ops.cpp.inc"
		>();
	}
}
