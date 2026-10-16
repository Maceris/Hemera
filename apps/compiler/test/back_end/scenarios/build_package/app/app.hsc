// A target of the build package: main returns the answer the build's settings give it.
package app

import compiler from "base"

ANSWER :: #run compiler.target_setting("answer", default = "0")

main :: fn() -> int {
    if ANSWER == "42" {
        return 42
    }
    return 1
}
