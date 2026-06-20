#ifndef HMIR_DIALECT
#define HMIR_DIALECT

include "mlir/IR/OpBase.td"

def hmir_dialect : Dialect {
	let name = "hmir";
	let summary = "A MLIR dialect for Hemera";
	let description = [{
		This is a MLIR dialect used for Hemera.
	}];
	let cppNamespace = "hmir";
}

class hmir_op<string mnemonic, list<Trait> props = []> :
	Op<hmir_dialect, mnemonic, props>;

#endif
