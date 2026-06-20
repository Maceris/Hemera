#include "hmir/hmir_ops.h"
#include "hmir/hmir_dialect.h"
#include "mlir/IR/OpImplementation.h"

namespace mlir::hmir {

#define GET_OP_CLASSES
#include "hmir/hmir_ops.cpp.inc"

}
