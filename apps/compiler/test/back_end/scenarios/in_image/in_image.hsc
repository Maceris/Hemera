package in_image

import runtime from "base"

/*
 * runtime.in_image: whether an address is in the program's image, from the image's own headers. A string literal and a
 * function are; what's on the heap or the stack isn't. It reads the headers through a generic #no_context function,
 * whose instances are #no_context too. main returns 42 if each is where it should be.
 */

LITERAL :: "a literal, in the image's read-only data"

main :: fn() -> int {
    if !runtime.in_image(cast[rawptr](LITERAL.data)) {
        return 1
    }
    if !runtime.in_image(cast[rawptr](main)) {
        return 2
    }
    on_heap := runtime.new(int)
    defer runtime.free(on_heap)
    if runtime.in_image(cast[rawptr](on_heap)) {
        return 3
    }
    on_stack := 5
    if runtime.in_image(cast[rawptr](&on_stack)) {
        return 4
    }
    return 42
}
