/*
 * Two instances of a generic whose parameter's type is an optional of a generic alias, Optional[DestroyValue[T]]:
 * each instance's optional is its own, whichever thread resolves the alias first. The two instances used to share
 * one when an alias was keyed before it knew what it named, about half the time.
 */
package generic_alias_arguments

import memory from "std"
import testing from "std"

/** A value given a destroy function of its own type. */
Buffer :: struct {
    /** Its size; -1 once destroyed. */
    size : int,
}

/**
 * Mark a buffer destroyed.
 *
 * @param buffer The buffer, its size set to -1.
 */
destroy_buffer :: fn(buffer: ptr[mut Buffer]) {
    buffer.size = -1
}

shares_a_value_with_its_own_destroy_function #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    buffer :: memory.make_shared(Buffer.{size = 4}, destroy_buffer)
    size :: buffer.size
    memory.release(buffer)
    testing.expect_eq(t, size, 4, "the shared buffer is the one made")
    return .Ok
}

shares_a_value_of_another_type_without_one #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    local :: memory.make_shared[int, false](7)
    value :: memory.pointer_of(&local)^
    memory.release(local)
    testing.expect_eq(t, value, 7, "the shared int is the one made")
    return .Ok
}
