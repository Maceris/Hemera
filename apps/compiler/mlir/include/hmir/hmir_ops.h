#pragma once

#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/Interfaces/SideEffects.h"

namespace mlir::hmir {

#define GET_OP_CLASSES
#include "hmir/hmir_ops.h.inc"

}
