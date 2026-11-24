package math

import intrinsics from "base:intrinsics"

/*
 * Integer arithmetic that says when it overflows (docs/operators.md, Integer overflow): the result as an optional,
 * null when the true result is past the type's range, where the plain operator would wrap. Each is LLVM's
 * *.with.overflow, one instruction and a flag, through base's intrinsics.
 */

/**
 * Add two integers, unless the sum overflows their type.
 *
 * @tparam T An integer type, signed or not, of both.
 * @param a The first.
 * @param b The second.
 * @return a + b; null when the true sum is past T's range.
 */
checked_add :: fn[T](a : T, b : T) -> T? {
    if intrinsics.add_overflows(a, b) {
        return null
    }
    return a + b
}

/**
 * Subtract one integer from another, unless the difference overflows their type, as 0 - 1 does for an unsigned one.
 *
 * @tparam T An integer type, signed or not, of both.
 * @param a What's subtracted from.
 * @param b What's subtracted.
 * @return a - b; null when the true difference is past T's range.
 */
checked_subtract :: fn[T](a : T, b : T) -> T? {
    if intrinsics.subtract_overflows(a, b) {
        return null
    }
    return a - b
}

/**
 * Multiply two integers, unless the product overflows their type.
 *
 * @tparam T An integer type, signed or not, of both.
 * @param a The first.
 * @param b The second.
 * @return a * b; null when the true product is past T's range.
 */
checked_multiply :: fn[T](a : T, b : T) -> T? {
    if intrinsics.multiply_overflows(a, b) {
        return null
    }
    return a * b
}
