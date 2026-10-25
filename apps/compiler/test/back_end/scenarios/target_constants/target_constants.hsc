/*
 * OS and TARGET_ARCH as values, not only in #if: compared where the program runs, and as constants' values. main
 * returns 42 if they say what #if does, or the number of the first check that didn't.
 */
package target_constants

ON_WINDOWS :: OS == .Windows

main :: fn() -> int {
    #if OS == .Windows {
        expected_windows :: true
    }
    #else {
        expected_windows :: false
    }
    if ON_WINDOWS != expected_windows || (OS == .Windows) != expected_windows {
        return 1
    }
    #if TARGET_ARCH == .x86_64 {
        expected_x86 :: true
    }
    #else {
        expected_x86 :: false
    }
    if (TARGET_ARCH == .x86_64) != expected_x86 {
        return 2
    }
    return 42
}
