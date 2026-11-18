// A target of the build_constants packages, whose checks read its constants.
package app

/** How many there are, which the checks read. */
LIMIT :: 7

GREETING :: "hello"

main :: fn() -> int {
    return LIMIT - 7
}
