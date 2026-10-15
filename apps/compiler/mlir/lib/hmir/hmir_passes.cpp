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
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "llvm/ADT/DenseMap.h"

namespace mlir::hmir {
#define GEN_PASS_DEF_HEMERADEFER
#define GEN_PASS_DEF_HEMERALOWERCONTROLFLOW
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
        else if (auto continueOp = dyn_cast<::hmir::HemeraContinueOp>(exitOp)) {
            loops = static_cast<int64_t>(continueOp.getDepth());
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

    bool isStructured(Operation* op) {
        return isa<::hmir::HemeraScopeOp, ::hmir::HemeraLoopOp, ::hmir::HemeraIfOp>(op);
    }

    bool isExit(Operation* op) {
        return isa<::hmir::HemeraEndOp, ::hmir::HemeraBreakOp, ::hmir::HemeraContinueOp,
            ::hmir::HemeraReturnOp>(op);
    }

    /// <summary>
    /// The structured op an exit goes to, worked out before anything is inlined: hmir.end's own
    /// op, the loop hmir.break leaves, or the loop hmir.continue continues. Null for hmir.return.
    /// </summary>
    Operation* exitTarget(Operation* exitOp) {
        if (isa<::hmir::HemeraEndOp>(exitOp)) {
            return exitOp->getParentOp();
        }
        int64_t loops = 0;
        if (auto breakOp = dyn_cast<::hmir::HemeraBreakOp>(exitOp)) {
            loops = static_cast<int64_t>(breakOp.getDepth());
        }
        else if (auto continueOp = dyn_cast<::hmir::HemeraContinueOp>(exitOp)) {
            loops = static_cast<int64_t>(continueOp.getDepth());
        }
        else {
            return nullptr;
        }
        for (Operation* parent = exitOp->getParentOp(); parent; parent = parent->getParentOp()) {
            if (isa<::hmir::HemeraLoopOp>(parent) && --loops == 0) {
                return parent;
            }
        }
        return nullptr;
    }

    /// <summary>
    /// Where branches to a lowered op go: the block after it, and for a loop, its body's start.
    /// </summary>
    struct Targets {
        Block* header = nullptr;
        Block* exit = nullptr;
    };

    /// <summary>
    /// Lowers one structured op that's directly in its function's region: its regions are moved
    /// into the function, and its block branches into them. Their exits are rewritten later.
    /// </summary>
    void lowerOne(Operation* op, llvm::DenseMap<Operation*, Targets>& targets, OpBuilder& builder) {
        Block* before = op->getBlock();
        Block* after = before->splitBlock(std::next(op->getIterator()));
        Region* region = before->getParent();
        Location loc = op->getLoc();
        auto moveIn = [&](Region& body) -> Block* {
            if (body.empty()) {
                return after;
            }
            Block* entry = &body.front();
            region->getBlocks().splice(Region::iterator(after), body.getBlocks());
            return entry;
        };
        builder.setInsertionPointToEnd(before);
        if (auto scope = dyn_cast<::hmir::HemeraScopeOp>(op)) {
            Block* entry = moveIn(scope.getBodyRegion());
            targets[op] = { nullptr, after };
            LLVM::BrOp::create(builder, loc, ValueRange{}, entry);
        }
        else if (auto loop = dyn_cast<::hmir::HemeraLoopOp>(op)) {
            Block* entry = moveIn(loop.getBodyRegion());
            targets[op] = { entry, after };
            LLVM::BrOp::create(builder, loc, ValueRange{}, entry);
        }
        else if (auto ifOp = dyn_cast<::hmir::HemeraIfOp>(op)) {
            Value condition = ifOp.getCondition();
            Block* thenEntry = moveIn(ifOp.getThenRegion());
            Block* elseEntry = moveIn(ifOp.getElseRegion());
            targets[op] = { nullptr, after };
            LLVM::CondBrOp::create(builder, loc, condition, thenEntry, elseEntry);
        }
        op->erase();
    }

    class HemeraLowerControlFlow
        : public impl::HemeraLowerControlFlowBase<HemeraLowerControlFlow> {
    public:
        using impl::HemeraLowerControlFlowBase<HemeraLowerControlFlow>::HemeraLowerControlFlowBase;

        void runOnOperation() final {
            ModuleOp module = getOperation();
            OpBuilder builder(&getContext());
            module.walk([&](FunctionOpInterface function) {
                // Each exit's target, from the nesting as written
                SmallVector<std::pair<Operation*, Operation*>> exits;
                SmallVector<Operation*> structured;
                function->walk<WalkOrder::PreOrder>([&](Operation* op) {
                    if (isStructured(op)) {
                        structured.push_back(op);
                    }
                    else if (isExit(op)) {
                        exits.emplace_back(op, exitTarget(op));
                    }
                });
                // Outermost first, so each op is in the function's region when its turn comes
                llvm::DenseMap<Operation*, Targets> targets;
                for (Operation* op : structured) {
                    lowerOne(op, targets, builder);
                }
                for (auto [exitOp, target] : exits) {
                    builder.setInsertionPoint(exitOp);
                    Location loc = exitOp->getLoc();
                    if (auto returnOp = dyn_cast<::hmir::HemeraReturnOp>(exitOp)) {
                        LLVM::ReturnOp::create(builder, loc, returnOp.getOperands());
                    }
                    else {
                        const Targets& to = targets[target];
                        // A loop's end and continue start its next iteration; anything else leaves
                        const bool next_iteration = isa<::hmir::HemeraContinueOp>(exitOp)
                            || (isa<::hmir::HemeraEndOp>(exitOp) && to.header != nullptr);
                        LLVM::BrOp::create(builder, loc, ValueRange{}, next_iteration ? to.header : to.exit);
                    }
                    exitOp->erase();
                }
            });
        }
    };
} // namespace
} // namespace mlir::hmir
