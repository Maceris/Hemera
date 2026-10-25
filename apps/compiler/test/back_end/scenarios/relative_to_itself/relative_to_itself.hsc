/*
 * A relative pointer set to point at itself (docs/types.md, Relative Pointers): its offset would be 0, which an
 * optional one reads as None, so the store's check fails through the hosted context's handler.
 */
package relative_to_itself

import runtime from "base"

// next is the first field, so a pointer to the Loop is a pointer to next itself
Loop :: struct {
    next : relptr32[Loop],
    value : int,
}

main :: fn() -> int {
    first := runtime.new(Loop)
    second := runtime.new(Loop)
    first.next = second
    first.next = first
    return 42
}
