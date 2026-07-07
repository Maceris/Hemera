#ifndef HMIR_OPS
#define HMIR_OPS

include "hmir_dialect.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def HemeraDeferOp : HemeraOp<"defer", [AlwaysSpeculatableImplTrait]> {
	
	let summary = "Used to defer an expression until the end of the scope";
	let description = [{
	 Example:

        ```mlir
        ^bb2:
          %2 = call @someFn()
          hmir.defer ^bb3(%2 : tensor<*xf32>)
        ^bb3(%3: tensor<*xf32>):
        ```
	}];

	let arguments = (ins Variadic<AnyType>:$destOperands);
    let successors = (successor AnySuccessor:$dest);

    let builders = [
    OpBuilder<(ins "mlir::Block *":$dest,
                   CArg<"mlir::ValueRange", "{}">:$destOperands), [{
      $_state.addSuccessors(dest);
      $_state.addOperands(destOperands);
    }]>];

    let extraClassDeclaration = [{
        void setDest(mlir::Block *block);

        /// Erase the operand at 'index' from the operand list.
        void eraseOperand(unsigned index);
    }];

    let hasCanonicalizeMethod = 1;
    let assemblyFormat = [{
        $dest (`(` $destOperands^ `:` type($destOperands) `)`)? attr-dict
    }];
}

#endif
