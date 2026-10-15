package compiler

import runtime from "base"

/*
 * A location in the source code, what #caller_location gives: runtime's, so a location from either
 * package is the same type.
 */
SourceCodeLocation :: runtime.SourceCodeLocation
