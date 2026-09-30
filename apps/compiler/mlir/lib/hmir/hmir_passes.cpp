#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Interfaces/FunctionInterfaces.h"

#include "hmir/hmir_passes.h"

namespace mlir::hmir {
#define GEN_PASS_DEF_HEMERADEFER
#include "hmir/hmir_passes.h.inc"

namespace {

    /// <summary>
    /// A single lexical scope.
    /// </summary>
    struct ExitedScope {
        /// <summary>
        /// The block for the scope.
        /// </summary>
        Block* block;
        /// <summary>
        /// The op in block that is, or contains, the exit op.
        /// </summary>
        Operation* position;
    };

    /// <summary>
    /// Determines which scopes that a terminator leaves, ordered from
    /// innermost first to outermost last. Intended for hmir.end, 
    /// hmir.continue, hmir.break, hmir.return, or func.return.
    /// </summary>
    /// <param name="exitOp">The operation which leaves scopes.</param>
    /// <returns>A list of scopes the op exits, sorted from innermost to outermost.</returns>
    SmallVector<ExitedScope, 4> computeExitedScopes(Operation* exitOp) {
        int64_t loops = 0;
        bool returns = false;
        if (auto breakOp = dyn_cast<::hmir::HemeraBreakOp>(exitOp)) {
            loops = static_cast<int64_t>(breakOp.getDepth());
        }
        else if (isa<::hmir::HemeraContinueOp>(exitOp)) {
            loops = 1;
        }
        else if (isa<::hmir::HemeraReturnOp, func::ReturnOp>(exitOp)) {
            returns = true;
        }

        SmallVector<ExitedScope, 4> scopes;
        Operation* position = exitOp;
        while (true) {
            Block* block = position->getBlock();
            scopes.push_back({ block, position });

            Operation* owner = block->getParentOp();
            if (!owner || isa<FunctionOpInterface>(owner)) {
                break;
            }
            if (isa<::hmir::HemeraLoopOp>(owner)) {
                loops -= 1;
            }
            if (!returns && loops <= 0) {
                break;
            }
            position = owner;
        }
        return scopes;
    }

    /// <summary>
    /// Copies the body of each defer which is applicable to the exit op, in
    /// front of the exit op, in reverse declaration order.
    /// </summary>
    /// <param name="exitOp">The operation which leaves scopes.</param>
    /// <param name="builder">The op builder to use.</param>
    /// <returns>Status of the expansion.</returns>
    LogicalResult expandDefersAtExit(Operation* exitOp, OpBuilder& builder) {
        builder.setInsertionPoint(exitOp);

        for (const ExitedScope& scope : computeExitedScopes(exitOp)) {
            SmallVector<::hmir::HemeraDeferOp, 4> active;
            for (Operation& op : *scope.block) {
                if (&op == scope.position) {
                    break;
                }
                if (auto deferOp = dyn_cast<::hmir::HemeraDeferOp>(op)) {
                    active.push_back(deferOp);
                }
            }
            if (active.empty()) {
                continue;
            }

            if (!scope.block->getParent()->hasOneBlock()) {
                return exitOp->emitOpError()
                    << "leaves a scope with a 'hmir.defer' but has multiple "
                    "blocks. hemera-defer must run before lowering to "
                    "unstructured control flow";
            }

            for (::hmir::HemeraDeferOp deferOp : llvm::reverse(active)) {
                /*
                 * Use a fresh mapping for each op, that ops inside the body
                 * only refer to their own copy's results. Values from outside
                 * the op body are left alone.
                 */
                IRMapping mapping;
                for (Operation& bodyOp : deferOp.getBody()->without_terminator()) {
                    builder.clone(bodyOp, mapping);
                }
            }
        }
        return success();
    }

    class HemeraDefer
        : public impl::HemeraDeferBase<HemeraDefer> {
    public:
        using impl::HemeraDeferBase<HemeraDefer>::HemeraDeferBase;
        
        void runOnOperation() final {
            ModuleOp module = getOperation();

            /*
             * Go find all the terminators before we go changing things.
             * A post-order walk will automatically handle any nonsense like
             * defers nested inside other defer bodies.
             */
            SmallVector<Operation*> exits;
            module.walk([&](Operation* op) {
                if (op->hasTrait<OpTrait::IsTerminator>()) {
                    exits.push_back(op);
                }
            });

            OpBuilder builder(&getContext());
            for (Operation* exitOp : exits) {
                if (failed(expandDefersAtExit(exitOp, builder))) {
                    signalPassFailure();
                    return;
                }
            }
            
            // Go erase defer ops. Post-order walk will deal with nested ops.
            SmallVector<::hmir::HemeraDeferOp> defers;
            module.walk([&](::hmir::HemeraDeferOp deferOp) {
                defers.push_back(deferOp);
            });
            for (::hmir::HemeraDeferOp deferOp : defers) {
                deferOp.erase();
            }
        }
    };
} // namespace
} // namespace mlir::hmir
