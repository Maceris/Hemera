package main

import intrinsics from "base:intrinsics"
import math from "std:math"

/**
 * Float-to-integer casts, which saturate (docs/operators.md, Casting operators): how many of the cases hold, each
 * worth one. As many at compile time as at run time.
 */
cases :: fn() -> int {
    nan := cast[f32](math.nan[f64]())
    infinite := math.infinity[f64]()
    held := 0
    held += if cast[i32](nan) == 0 { 1 } else { 0 }
    held += if cast[u64](cast[f64](nan)) == 0 { 1 } else { 0 }
    held += if cast[i32](cast[f32](1e30)) == 2147483647 { 1 } else { 0 }
    held += if cast[i32](cast[f32](-1e30)) == -2147483648 { 1 } else { 0 }
    held += if cast[u8](cast[f32](300)) == 255 { 1 } else { 0 }
    held += if cast[u8](cast[f32](-5)) == 0 { 1 } else { 0 }
    held += if cast[u64](infinite) == 18446744073709551615 { 1 } else { 0 }
    held += if cast[i64](-infinite) == -9223372036854775807 - 1 { 1 } else { 0 }
    held += if cast[i32](cast[f32](-2.7)) == -2 { 1 } else { 0 }
    held += if cast[i16](cast[f64](12345.9)) == 12345 { 1 } else { 0 }
    // Each lane of a vector as a number is
    lanes := vector[f32, 4].{nan, 1e30, -1e30, 7.5}
    whole := cast[vector[i32, 4]](lanes)
    held += if whole[0] == 0 && whole[1] == 2147483647 && whole[2] == -2147483648 && whole[3] == 7 { 1 } else { 0 }
    // The unchecked conversion, within range, as a cast
    held += if intrinsics.to_integer_unchecked[i32](cast[f32](-41.9)) == -41 { 1 } else { 0 }
    within := intrinsics.to_integer_unchecked[vector[i32, 4]](vector[f32, 4].{1.5, 2.5, -3.5, 40.9})
    held += if within[0] == 1 && within[3] == 40 && within[2] == -3 { 1 } else { 0 }
    return held
}

AT_COMPILE_TIME :: #run cases()

/** 42: 13 cases at compile time and at run time, 26, and 16 more. */
main :: fn() -> int {
    return AT_COMPILE_TIME + cases() + 16
}
