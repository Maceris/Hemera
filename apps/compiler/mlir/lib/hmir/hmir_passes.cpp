#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include "hmir/hmir_passes.h"

namespace mlir::hmir {
#define GEN_PASS_DEF_HEMERADEFER
#include "hmir/hmir_passes.h.inc"

	//TODO(ches) add pass for defer
}