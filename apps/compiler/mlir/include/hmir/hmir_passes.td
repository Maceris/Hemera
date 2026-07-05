#ifndef HMIR_PASS
#define HMIR_PASS

include "mlir/Pass/PassBase.td"

def HemeraDefer: Pass<"hemera-defer", "::mlir::ModuleOp"> {
  let summary = "Moves the contents of defer statements to the end(s) of their scope.";
  let description = [{
    Moves the contents of defer statements to the end(s) of their scope.
  }];
}

#endif
