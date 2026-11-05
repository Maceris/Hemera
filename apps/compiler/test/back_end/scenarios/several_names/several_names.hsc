/*
 * Several names in one declaration (docs/functions.md, Several Names in One Declaration): each with its own value, in
 * order, typed once or not, at the top level and in a function, or one value for them all.
 */
package several_names

import testing from "std"

MIN, MAX :: -10, 10
WIDTH, HEIGHT : u32 : 640, 480

divide :: fn(a: int, b: int) -> (int, int) {
    return a / b, a % b
}

declares_several_constants #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, MIN == -10 && MAX == 10, "each name takes its own value, in order")
    testing.expect_eq(t, WIDTH * HEIGHT, 307200, "names typed once each have the type and their own value")
    return .Ok
}

declares_several_variables #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    x, y, z := 1, 2, 3
    testing.expect_eq(t, x + y * 10 + z * 100, 321, "each variable takes its own value, in order")
    small, large : u8 = 1, 200
    testing.expect_eq(t, cast[int](small) + cast[int](large), 201, "variables typed once each take their own value")
    quotient, remainder := divide(7, 2)
    testing.expect(t, quotient == 3 && remainder == 1, "a call's two results go to the two names")
    low, high, extra := divide(9, 4), 5
    testing.expect(t, low == 2 && high == 1 && extra == 5, "a call's results and a value after them go to the names in order")
    // Each is its own variable
    x, y = y, x
    testing.expect(t, x == 2 && y == 1, "assigning both at once swaps them")
    both, too := 7
    testing.expect(t, both == 7 && too == 7, "one value is given to every name")
    return .Ok
}
