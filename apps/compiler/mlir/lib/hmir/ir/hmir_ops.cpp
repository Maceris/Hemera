#include "hmir/hmir_ops.h"
#include "hmir/hmir_dialect.h"

#include "mlir/Interfaces/FunctionInterfaces.h"

#define GET_OP_CLASSES
#include "hmir/hmir_ops.cpp.inc"

namespace hmir {

    /// <summary>
    /// Walks outward from op until it either reaches a function or hmir.defer
    /// body, and count all the hmir.loop ops. Sets boundary to either the
    /// boundary it found, or null if none were found.
    /// </summary>
    /// <param name="op">The starting op.</param>
    /// <param name="boundary">Out parameter for the boundary.</param>
    /// <returns>How many loops we found on the way to the boundary.</returns>
    static int64_t countLoopsBeforeBoundary(mlir::Operation* op,
        mlir::Operation*& boundary)
    {
        int64_t loops = 0;
        boundary = nullptr;
        mlir::Operation* parent = nullptr;
        for (parent = op->getParentOp(); parent; parent = parent->getParentOp()) {
            if (mlir::isa<HemeraDeferOp, mlir::FunctionOpInterface>(parent)) {
                boundary = parent;
                break;
            }
            if (mlir::isa<HemeraLoopOp>(parent)) {
                ++loops;
            }
        }
        return loops;
    }

    mlir::LogicalResult HemeraBreakOp::verify() {
        mlir::Operation* boundary = nullptr;
        int64_t loops = countLoopsBeforeBoundary(getOperation(), boundary);
        int64_t depth = static_cast<int64_t>(getDepth());
        if (loops < depth) {
            return emitOpError() << "breaks out of " << depth
                << " loop(s), but only " << loops << " enclosing loop(s) "
                << (mlir::isa_and_nonnull<HemeraDeferOp>(boundary)
                    ? "are inside the enclosing defer"
                    : "exist");
        }
        return mlir::success();
    }

    mlir::LogicalResult HemeraContinueOp::verify() {
        mlir::Operation* boundary = nullptr;
        if (countLoopsBeforeBoundary(getOperation(), boundary) < 1) {
            return emitOpError() << "must be inside a loop"
                << (mlir::isa_and_nonnull<HemeraDeferOp>(boundary)
                    ? " which is inside the enclosing defer"
                    : "");
        }
        return mlir::success();
    }

    mlir::LogicalResult HemeraReturnOp::verify() {
        mlir::Operation* boundary = nullptr;
        countLoopsBeforeBoundary(getOperation(), boundary);
        if (mlir::isa_and_nonnull<HemeraDeferOp>(boundary)) {
            return emitOpError() << "cannot return from inside a defer";
        }
        if (!boundary) {
            return emitOpError() << "must be inside a function";
        }
        return mlir::success();
    }

    mlir::LogicalResult HemeraDeferOp::verifyRegions() {
        mlir::Block* body = getBody();
        if (body->empty() || !mlir::isa<HemeraEndOp>(body->back())) {
            return emitOpError() << "body must end with 'hmir.end'";
        }
        return mlir::success();
    }
}
