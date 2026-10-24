// A target that doesn't check, built at the same time as others, which still build.
package broken

main :: fn() -> int {
    return not_declared_anywhere
}
