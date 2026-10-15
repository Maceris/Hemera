#ifndef HMIR_HMIR_PASSES_H
#define HMIR_HMIR_PASSES_H

#include "hmir/hmir_dialect.h"
#include "hmir/hmir_ops.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Pass/Pass.h"
#include <memory>

namespace mlir::hmir {

#define GEN_PASS_DECL
#include "hmir/hmir_passes.h.inc"

#define GEN_PASS_REGISTRATION
#include "hmir/hmir_passes.h.inc"

} // namespace mlir::hmir

#endif
