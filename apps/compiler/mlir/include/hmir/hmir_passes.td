#ifndef HMIR_PASS
#define HMIR_PASS

include "mlir/Pass/PassBase.td"

def HemeraDefer: Pass<"hemera-defer", "::mlir::ModuleOp"> {
  let summary = "Moves the contents of defer statements to the end(s) of their scope.";
  let description = [{
    Moves the contents of defer statements to the end(s) of their scope.
  }];
}

def HemeraLowerControlFlow: Pass<"hemera-lower-control-flow", "::mlir::ModuleOp"> {
  let summary = "Lowers hmir's structured control flow to the LLVM dialect's branches.";
  let description = [{
    Inlines the regions of hmir.scope, hmir.loop and hmir.if into their function, and turns
    hmir.end, hmir.break, hmir.continue and hmir.return into llvm.br and llvm.return. Runs after
    hemera-defer, since defers are expanded at each exit while the structure is still there.
  }];
  let dependentDialects = ["::mlir::LLVM::LLVMDialect"];
}

#endif
