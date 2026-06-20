#ifndef HMIR_OPS
#define HMIR_OPS

include "hmir_dialect.td"
include "mlir/Interfaces/InferTypeOpInterface.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def hmir_example_op : hmir_op<"example", [NoMemoryEffect, 
	SameOperandsAndResultType]> {
	
	let summary = "This is an example";
	let description = [{
	 Example:

        ```mlir
        %0 = constant 2 : i32
        // Apply the example operation to %0
        %1 = hmir.example %0 : i32
        ```
	}];

	let arguments = (ins I32:$input);
    let results = (outs I32:$res);

    let assemblyFormat = [{
        $input attr-dict `:` type($input)
    }];
}

#endif
