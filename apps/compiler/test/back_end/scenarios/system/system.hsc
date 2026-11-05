/*
 * The hosted context's clock and random numbers, from the system, and on Linux x86-64 a system call
 * answering in three registers (x86_64.system_call).
 */
package system_test

import runtime from "base"
import random from "std"
import strings from "std"
import testing from "std"
import time from "std"

#if TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"
}

reads_the_wall_clock #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // After this was written, 2026-10-18, and before 2200
    read :: time.now()
    now :: testing.require_ok(t, read, "the system gives the time")?
    moment :: time.utc(now)
    testing.expect_ge(t, now.seconds, 1792281600, "it's after this test was written, 2026-10-18")
    testing.expect(t, moment.year >= 2026 && moment.year < 2200, "its year is after this was written and well before 2200")
    testing.expect_lt(t, now.nanos, 1000000000, "nanoseconds stay below a second")
    return .Ok
}

reads_monotonic_time_going_forward #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    start :: time.monotonic()
    testing.expect_gt(t, cast[i64](start), 0, "monotonic time counts up from some point before the program")
    total : u64 = 0
    for i in 0..<200000 {
        total += cast[u64](i)
    }
    later :: time.monotonic()
    testing.expect_ge(t, cast[i64](later), cast[i64](start), "monotonic time never goes back")
    testing.expect_ne(t, total, 0, "the work between the readings was done")
    took :: time.since(start)
    testing.expect(t, took.seconds >= 0 && took.seconds <= 60, "a short loop takes no time below zero, nor a minute")
    return .Ok
}

reads_random_bytes_from_the_system #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // 32 bytes from the system: not all zero, and not the same twice
    first : u8[32]
    second : u8[32]
    random.fill(first)
    random.fill(second)
    zero := true
    same := true
    for byte, index in first {
        if byte != 0 {
            zero = false
        }
        if index < second.count && byte != second[index] {
            same = false
        }
    }
    testing.expect(t, !zero, "32 random bytes all zero is next to impossible")
    testing.expect(t, !same, "two fills of 32 random bytes alike is next to impossible")
    return .Ok
}

rolls_numbers_in_range #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Every face of a die turns up in a few hundred rolls
    seen : bool[6]
    for i in 0..<600 {
        roll :: random.between(1, 6)
        testing.require(t, roll >= 1 && roll <= 6, "between gives a number from its first to its last, inclusive")?
        face :: cast[usize](roll - 1)
        if face < seen.count {
            seen[face] = true
        }
    }
    for face in seen {
        testing.expect(t, face, "each of six faces turns up in 600 rolls, all but certainly")
    }
    testing.expect_eq(t, random.below(1), 0, "below 1 there's only 0")
    testing.expect_eq(t, random.below(0), 0, "below 0 there's nothing, and 0 is given")
    testing.expect_eq(t, random.between(5, 5), 5, "between a number and itself is that number")
    return .Ok
}

/*
 * getpid through system_call: rax is the process's ID, and Linux keeps rdx and r8, which were arguments,
 * as they were.
 */
makes_a_system_call #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    #if OS == .Linux && TARGET_ARCH == .x86_64 {
        // getpid's number on x86-64 Linux
        result :: x86_64.system_call(39, 0, 0, 0x1234, 0, 0x5678)
        testing.expect(t, result.rax != 0 && result.rax <= 0x7fffffff, "getpid gives a process ID, positive and in 32 bits")
        testing.expect_eq(t, result.rdx, 0x1234, "Linux keeps rdx, an argument, as it was")
        testing.expect_eq(t, result.r8, 0x5678, "Linux keeps r8, an argument, as it was")
        testing.expect_eq(t, result.rax, x86_64.syscall(39), "syscall gives the same process ID")
    }
    return .Ok
}
