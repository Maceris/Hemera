/*
 * A hosted Linux program that links the C library, which declaring #foreign functions of its own
 * makes it do: main returns 42 if everything worked, or the number of the first check that failed.
 *
 * It calls C from main, from threads (which the runtime then starts through pthreads, so C's own
 * state is set up on them) and from a fiber, and C calls back into Hemera from qsort, with the
 * caller's context, on each.
 */
package libc_test

import intrinsics from "base"
import runtime from "base"
import x86_64 from "base/intrinsics"
import fiber from "std"

LIBC :: #library("c")

strlen #foreign(LIBC) : fn(text: rawptr) -> usize : ---
getpid #foreign(LIBC) : fn() -> i32 : ---
qsort #foreign(LIBC) : fn(items: rawptr, count: usize, size: usize, compare: rawptr) : ---

SYS_GETPID : u64 : 39

// What the checks found, through context.user_data.
Results :: struct {
    // Comparisons qsort called back for
    comparisons : u64,
    // 0 once a thread's or the fiber's checks worked, or the first that didn't
    thread_failures : int[2],
    fiber_failure : int,
}

// qsort's comparison, a callback with the context of whoever called qsort.
compare_ints #calling_convention(.c) :: fn(a: rawptr, b: rawptr) -> i32 {
    results :: cast[ptr[mut Results]](context.user_data)
    intrinsics.interlocked_increment_u64(&results.comparisons)
    left :: cast[ptr[i32]](a)^
    right :: cast[ptr[i32]](b)^
    return if left < right { -1 } else if left > right { 1 } else { 0 }
}

// C's calls, wherever this runs: 0 if they all worked, or the first that didn't.
call_c :: fn(results: ptr[mut Results]) -> int {
    text : u8[8]
    text[0] = cast[u8]('h')
    text[1] = cast[u8]('e')
    text[2] = cast[u8]('m')
    text[3] = cast[u8]('e')
    text[4] = cast[u8]('r')
    text[5] = cast[u8]('a')
    text[6] = 0
    if strlen(cast[rawptr](&text[0])) != 6 {
        return 1
    }
    if cast[u64](getpid()) != x86_64.syscall(SYS_GETPID) {
        return 2
    }
    before :: intrinsics.atomic_load_u64_acquire(&results.comparisons)
    numbers : i32[8]
    numbers[0] = 5
    numbers[1] = 3
    numbers[2] = 8
    numbers[3] = 1
    numbers[4] = 9
    numbers[5] = 2
    numbers[6] = 7
    numbers[7] = 4
    qsort(cast[rawptr](&numbers[0]), 8, 4, cast[rawptr](compare_ints))
    for i in 0..<7 {
        if numbers[i] > numbers[i + 1] {
            return 3
        }
    }
    if intrinsics.atomic_load_u64_acquire(&results.comparisons) == before {
        return 4
    }
    return 0
}

worker : runtime.ThreadFunction : fn(data #escaping : any) {
    results :: cast[ptr[mut Results]](context.user_data)
    index :: runtime.current_thread_index()
    if index < 2 {
        results.thread_failures[index] = call_c(results)
    }
}

fiber_worker : runtime.ThreadFunction : fn(data #escaping : any) {
    results :: cast[ptr[mut Results]](context.user_data)
    results.fiber_failure = call_c(results)
}

main :: fn() -> int {
    if !intrinsics.uses_c_library() {
        return 1
    }
    results :: runtime.new(Results)
    results.thread_failures[0] = -1
    results.thread_failures[1] = -1
    results.fiber_failure = -1
    threads : rawptr[2]
    push_context with_results (user_data = cast[rawptr](results)) {
        // From main
        failure :: call_c(results)
        if failure != 0 {
            return 10 + failure
        }
        // From threads
        for i in 0..<cast[usize](2) {
            thread :: runtime.thread_create(worker)
            thread.index = i
            if !runtime.thread_start(thread) {
                return 20
            }
            threads[i] = cast[rawptr](thread)
        }
        // From a fiber, on this thread
        pool :: fiber.create_fiber_pool()
        _, error :: fiber.spawn(pool, fiber_worker)
        if error != null {
            return 21
        }
        fiber.close_pool(pool)
        fiber.run_carrier(pool)
        fiber.destroy_fiber_pool(pool)
    }
    for i in 0..<cast[usize](2) {
        runtime.thread_join(cast[ptr[mut runtime.Thread]](threads[i]))
    }
    for i in 0..<cast[usize](2) {
        if results.thread_failures[i] != 0 {
            return 30 + results.thread_failures[i]
        }
    }
    if results.fiber_failure != 0 {
        return 40 + results.fiber_failure
    }
    return 42
}
