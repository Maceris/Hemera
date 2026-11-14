package base_all

// Every package of base, which the compiler supplies
import compiler from "base:compiler"
import intrinsics from "base:intrinsics"
import x86_64 from "base:intrinsics/x86_64"
import runtime from "base:runtime"

USES :: runtime.Context
