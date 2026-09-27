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
            mlir::Block* currentBlock = op->getBlock();
            if (!currentBlock) {
                return mlir::failure();
            }

            SmallVector<mlir::Operation*, 5> deferredOps;
            bool modified = false;

            for (mlir::Block& block : op->getRegions().front()) {
                for (mlir::Operation& nestedOp : block.getOperations()) {
                    if (mlir::isa<::hmir::HemeraDeferOp>(nestedOp)) {
                        deferredOps.push_back(&nestedOp);
                    }
                }
            }

            if (deferredOps.empty()) {
                return mlir::failure();
            }

            mlir::Operation* terminator = currentBlock->getTerminator();

            for (Operation* deferOp : llvm::reverse(deferredOps)) {
                if (deferOp->getNextNode() == terminator) {
                    // Already at the end
                    terminator = deferOp;
                    continue;
                }

                // Move it to the bottom, or before the previous defer
                rewriter.moveOpBefore(deferOp, terminator);

                // Then replace it with the operand
                mlir::Value deferInput = deferOp->getOperand(0);
                Operation* definingOp = deferInput.getDefiningOp();
                if (!definingOp) {
                    return rewriter.notifyMatchFailure(op, "Operand does not have a defining operation.");
                }
                rewriter.replaceOp(deferOp, definingOp->getResults());
                terminator = definingOp;

                modified = true;
            }
            
            return success(modified);
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
