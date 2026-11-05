/*
 * b16, b32 and b64 (docs/types.md): true is 1 and false 0, in a wider integer, and ! gives the other,
 * through a widening and as a condition.
 */
package wide_booleans

import testing from "std"

/**
 * Tell whether a wide boolean is true, taking it widened to b64 and testing it as a condition.
 *
 * @param ok Any wide boolean, widened to b64 where it's passed.
 * @return True if ok is.
 */
holds :: fn(ok: b64) -> bool {
    if ok {
        return true
    }
    return false
}

/**
 * Negate a b32, through a call.
 *
 * @param value Any b32.
 * @return !value.
 */
flip :: fn(value: b32) -> b32 {
    return !value
}

negates_wide_booleans #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a : b16 = true
    b : b32 = true
    c : b64 = true
    off : b16 = false
    testing.expect(t, holds(!(!a)), "a b16's double negation is itself, widened to b64")
    testing.expect(t, holds(!(!b)), "a b32's double negation is itself, widened to b64")
    testing.expect(t, holds(!(!c)), "a b64's double negation is itself")
    testing.expect(t, holds(!off), "false negated is true, widened to b64")
    testing.expect_eq(t, bit_cast[u16](!a), 0, "true negated is 0 in all 16 bits")
    testing.expect_eq(t, bit_cast[u16](!off), 1, "false negated is 1, not all ones")
    wide : b64 = a
    testing.expect(t, holds(!(!wide)), "a b16 widened to b64 keeps its truth")
    testing.expect_eq(t, bit_cast[u32](flip(true)), 0, "true negated through a call is 0")
    testing.expect_eq(t, bit_cast[u32](flip(false)), 1, "false negated through a call is 1")
    if !c {
        testing.fail(t, "a true b64's negation, as a condition, isn't taken")
    }
    return .Ok
}
