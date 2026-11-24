package main

import intrinsics from "base:intrinsics"
import math from "std:math"

/**
 * Integer arithmetic that says when it overflows (docs/operators.md, Integer overflow): how many of the cases hold,
 * each worth one, signed and unsigned, at the edges and inside them. As many at compile time as at run time.
 *
 * @param one 1, given so nothing's folded away before it runs.
 * @return How many hold, 14 of 14.
 */
cases :: fn(one : i64) -> int {
    largest := cast[i64](9223372036854775807)
    smallest := -largest - one
    held := 0
    held += if intrinsics.add_overflows(largest, one) { 1 } else { 0 }
    held += if !intrinsics.add_overflows(largest - one, one) { 1 } else { 0 }
    held += if intrinsics.subtract_overflows(smallest, one) { 1 } else { 0 }
    held += if intrinsics.multiply_overflows(smallest, -one) { 1 } else { 0 }
    held += if !intrinsics.multiply_overflows(cast[i64](3037000499), cast[i64](3037000499) * one) { 1 } else { 0 }
    held += if intrinsics.multiply_overflows(cast[i64](3037000500), cast[i64](3037000500) * one) { 1 } else { 0 }
    // Unsigned: past the top, and below 0
    top := cast[u8](255)
    small := cast[u8](one)
    held += if intrinsics.add_overflows(top, small) { 1 } else { 0 }
    held += if intrinsics.subtract_overflows(cast[u8](0), small) { 1 } else { 0 }
    held += if !intrinsics.multiply_overflows(cast[u8](15), cast[u8](17) * small) { 1 } else { 0 }
    held += if intrinsics.multiply_overflows(cast[u8](16), cast[u8](16) * small) { 1 } else { 0 }
    // std:math's, as optionals
    held += if (math.checked_add(largest, one) or_else 7) == 7 { 1 } else { 0 }
    held += if (math.checked_add(cast[i32](40), cast[i32](2) * cast[i32](one)) or_else 0) == 42 { 1 } else { 0 }
    held += if (math.checked_subtract(cast[u64](5), cast[u64](one) * 6) or_else 9) == 9 { 1 } else { 0 }
    held += if (math.checked_multiply(cast[u64](1) << 32, cast[u64](1) << 31) or_else 0) == cast[u64](1) << 63 { 1 } else { 0 }
    return held
}

AT_COMPILE_TIME :: #run cases(1)

/** 42: 14 cases at compile time and at run time, 28, and 14 more. */
main :: fn() -> int {
    return AT_COMPILE_TIME + cases(1) + 14
}
