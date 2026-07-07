#ifndef HMIR_DIALECT
#define HMIR_DIALECT

include "mlir/IR/OpBase.td"

def HemeraDialect : Dialect {
	let name = "hmir";
	let summary = "A MLIR dialect for Hemera";
	let description = [{
		This is a MLIR dialect used for Hemera.
	}];
	let cppNamespace = "hmir";
}

class HemeraOp<string mnemonic, list<Trait> props = []> :
	Op<HemeraDialect, mnemonic, props>;

#endif
