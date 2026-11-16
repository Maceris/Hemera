// For hemera --check: a #run statement runs as its function is generated, which a check has to do for it to run.
package main

import compiler from "base:compiler"

main :: fn() -> int {
    #run compiler.report_warning(#source_location, "ran as main was generated")
    return 0
}
