#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include "hmir/hmir_passes.h"

namespace mlir::hmir {
#define GEN_PASS_DEF_HEMERADEFER
#include "hmir/hmir_passes.h.inc"

namespace {
    class HemeraDeferRewriter : public OpRewritePattern<::hmir::HemeraDeferOp> {
    public:
        using OpRewritePattern<::hmir::HemeraDeferOp>::OpRewritePattern;
        
        LogicalResult matchAndRewrite(::hmir::HemeraDeferOp op,
            PatternRewriter& rewriter) const final
        {
            //TODO(ches) find where we need to defer to, and do so

            // Some dummy code that should in theory unwrap the op in place
            mlir::Value deferInput = op.getOperand(0);
            rewriter.replaceOp(op, { deferInput });
            return success();
        }
    };

    class HemeraDefer
        : public impl::HemeraDeferBase<HemeraDefer> {
    public:
        using impl::HemeraDeferBase<HemeraDefer>::HemeraDeferBase;
        
        void runOnOperation() final {
            RewritePatternSet patterns(&getContext());
            patterns.add<HemeraDeferRewriter>(&getContext());
            FrozenRewritePatternSet patternSet(std::move(patterns));
            if (failed(applyPatternsGreedily(getOperation(), patternSet))) {
                signalPassFailure();
            }
        }
    };
} // namespace
} // namespace mlir::hmir
