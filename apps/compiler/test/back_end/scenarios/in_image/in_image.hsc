package in_image

import runtime from "base"
import testing from "std"

/*
 * runtime.in_image: whether an address is in the program's image, from the image's own headers. A string literal and a
 * function are; what's on the heap or the stack isn't. It reads the headers through a generic #no_context function,
 * whose instances are #no_context too.
 */

/** A string literal, whose bytes the linker puts in the image's read-only data. */
LITERAL :: "a literal, in the image's read-only data"

finds_literals_and_functions_in_the_image #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, runtime.in_image(cast[rawptr](LITERAL.data)), "a literal's bytes are in the image's read-only data")
    testing.expect(t, runtime.in_image(cast[rawptr](finds_literals_and_functions_in_the_image)),
        "a function's code is in the image's text")
    return .Ok
}

finds_the_heap_and_stack_outside_the_image #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    on_heap := runtime.new(int)
    defer runtime.free(on_heap)
    testing.expect(t, !runtime.in_image(cast[rawptr](on_heap)), "the heap is memory allocated after the image is loaded")
    on_stack := 5
    testing.expect(t, !runtime.in_image(cast[rawptr](&on_stack)), "the stack is the thread's, not the image's")
    return .Ok
}
