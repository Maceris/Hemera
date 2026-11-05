/*
 * OS and TARGET_ARCH as values, not only in #if: compared where the program runs, and as constants' values.
 */
package target_constants

import testing from "std"

/** Whether the program is built for Windows, as a constant's value. */
ON_WINDOWS :: OS == .Windows

says_what_if_does_of_the_os #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    #if OS == .Windows {
        expected_windows :: true
    }
    #else {
        expected_windows :: false
    }
    testing.expect_eq(t, ON_WINDOWS, expected_windows, "OS compared in a constant agrees with #if")
    on_windows :: OS == .Windows
    testing.expect_eq(t, on_windows, expected_windows, "OS compared where the program runs agrees with #if")
    return .Ok
}

says_what_if_does_of_the_architecture #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    #if TARGET_ARCH == .x86_64 {
        expected_x86 :: true
    }
    #else {
        expected_x86 :: false
    }
    on_x86 :: TARGET_ARCH == .x86_64
    testing.expect_eq(t, on_x86, expected_x86, "TARGET_ARCH compared where the program runs agrees with #if")
    return .Ok
}
