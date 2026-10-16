/*
 * A constant whose value comes from compile-time code that gives a pointer: what it points to
 * doesn't exist in the program, so code generation reports it.
 */
package compile_time_pointer

TABLE :: int.[1, 2, 3]

second :: fn() -> ptr[int] {
    return &TABLE[1]
}

SECOND : ptr[int] : second()

main :: fn() -> int {
    return SECOND^
}
