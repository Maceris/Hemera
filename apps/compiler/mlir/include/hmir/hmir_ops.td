#ifndef HMIR_OPS
#define HMIR_OPS

include "hmir_dialect.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def HemeraDeferOp : HemeraOp<"defer", [AlwaysSpeculatableImplTrait, Pure]> {
	
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

	let arguments = (ins AnyType:$input);
    let results = (outs);

    let assemblyFormat = [{
        $input `:` type($input) attr-dict 
    }];
}

#endif
