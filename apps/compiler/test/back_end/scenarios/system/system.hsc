/*
 * The hosted context's clock and random numbers, from the system, and on Linux x86-64 a system call
 * answering in three registers (x86_64.system_call): main returns 42 if everything worked, or the number
 * of the first check that failed.
 */
package system_test

import runtime from "base"
import random from "std"
import strings from "std"
import time from "std"

#if TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"
}

check_clock :: fn() -> int {
    // The wall clock: after this was written, 2026-10-18, and before 2200
    match time.now() {
        case Ok(now) => {
            moment :: time.utc(now)
            if now.seconds < 1792281600 || moment.year < 2026 || moment.year >= 2200 || now.nanos >= 1000000000 {
                return 1
            }
        }
        case Error(_) => return 2
    }
    // Monotonic time goes forward
    start :: time.monotonic()
    if cast[i64](start) <= 0 {
        return 3
    }
    total : u64 = 0
    for i in 0..<200000 {
        total += cast[u64](i)
    }
    later :: time.monotonic()
    if cast[i64](later) < cast[i64](start) || total == 0 {
        return 4
    }
    took :: time.since(start)
    if took.seconds < 0 || took.seconds > 60 {
        return 5
    }
    return 0
}

check_random :: fn() -> int {
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
    if zero || same {
        return 1
    }
    // In range, and every face of a die turns up in a few hundred rolls
    seen : bool[6]
    for i in 0..<600 {
        roll :: random.between(1, 6)
        if roll < 1 || roll > 6 {
            return 2
        }
        face :: cast[usize](roll - 1)
        if face < seen.count {
            seen[face] = true
        }
    }
    for face in seen {
        if !face {
            return 3
        }
    }
    if random.below(1) != 0 || random.below(0) != 0 || random.between(5, 5) != 5 {
        return 4
    }
    return 0
}

/*
 * getpid through system_call: rax is the process's ID, and Linux keeps rdx and r8, which were arguments,
 * as they were.
 */
check_system_call :: fn() -> int {
    #if OS == .Linux && TARGET_ARCH == .x86_64 {
        // getpid's number on x86-64 Linux
        result :: x86_64.system_call(39, 0, 0, 0x1234, 0, 0x5678)
        if result.rax == 0 || result.rax > 0x7fffffff {
            return 1
        }
        if result.rdx != 0x1234 || result.r8 != 0x5678 {
            return 2
        }
        if result.rax != x86_64.syscall(39) {
            return 3
        }
    }
    return 0
}

main :: fn() -> int {
    failure := check_system_call()
    if failure != 0 {
        return 30 + failure
    }
    failure = check_clock()
    if failure != 0 {
        return 10 + failure
    }
    failure = check_random()
    if failure != 0 {
        return 20 + failure
    }
    return 42
}
