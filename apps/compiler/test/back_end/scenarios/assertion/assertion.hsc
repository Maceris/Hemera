/*
 * A hosted program whose assertion fails: the hosted context's handler writes the failure, where it
 * was and the stack to standard error, then ends the program with runtime.ASSERTION_EXIT_CODE.
 */
package assertion_test

import runtime from "base"

check :: fn(count: int) {
    runtime.assert(count > 0, "count must be positive")
}

main :: fn() -> int {
    check(1)
    check(0)
    return 42
}
