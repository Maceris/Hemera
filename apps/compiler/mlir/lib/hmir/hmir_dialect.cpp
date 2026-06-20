#include "hmir/hmir_dialect.h"
#include "hmir/hmir_ops.h"

using namespace mlir;
using namespace hmir;

#include "hmir/hmir_opsDialect.cpp.inc"

void hmirdialect::initialize() {
	addOperations<
#define GET_OP_LIST
#include "hmir/hmir_ops.cpp.inc"
	>();
}
