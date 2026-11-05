/*
 * A hosted Linux program that links the C library, which declaring #foreign functions of its own
 * makes it do.
 *
 * It calls C from the program's own thread, from threads (which the runtime then starts through
 * pthreads, so C's own state is set up on them) and from a fiber, and C calls back into Hemera from
 * qsort, with the caller's context, on each.
 */
package libc_test

import intrinsics from "base"
import runtime from "base"
import fiber from "std"
import testing from "std"

LIBC :: #library("c")

strlen #foreign(LIBC) : fn(text: rawptr) -> usize : ---
getpid #foreign(LIBC) : fn() -> i32 : ---
qsort #foreign(LIBC) : fn(items: rawptr, count: usize, size: usize, compare: rawptr) : ---
// In libc.so.6 since glibc 2.34; null for its handle is RTLD_DEFAULT, every library's symbols
dlsym #foreign(LIBC) : fn(handle: rawptr, name: cstring) -> rawptr : ---

// getpid and qsort as values dlsym finds, which calls through go through a shim, as calls to #foreign functions do
Getpid :: alias fn() -> i32 #calling_convention(.c) #no_context
Qsort :: alias fn(items: rawptr, count: usize, size: usize, compare: rawptr) #calling_convention(.c) #no_context

// getpid as a system call, to compare with C's
#if TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"

    raw_getpid :: fn() -> u64 {
        return x86_64.syscall(39)
    }
}
#else_if TARGET_ARCH == .arm64 {
    import aarch64 from "base/intrinsics"

    raw_getpid :: fn() -> u64 {
        return aarch64.syscall(172)
    }
}

/** What went wrong calling C, or that nothing did. */
CallProblem :: enum {
    /** Every call to C gave what it should, and qsort called back. */
    None,
    /** Not run: a thread or the fiber never got to its calls. */
    NotRun,
    /** strlen didn't count a C string's six bytes. */
    WrongLength,
    /** C's getpid isn't the system call's process ID. */
    WrongProcessId,
    /** qsort left the numbers out of order. */
    NotSorted,
    /** qsort sorted without calling back into Hemera. */
    NoCallback,
    /** getpid, called through the value dlsym found, isn't the system call's process ID. */
    WrongProcessIdThroughValue,
    /** qsort, called through the value dlsym found, left the numbers out of order. */
    NotSortedThroughValue,
    /** qsort, called through the value dlsym found, sorted without calling back. */
    NoCallbackThroughValue,
}

/** What the calls found, through context.user_data. */
Results :: struct {
    /** Comparisons qsort called back for, from anywhere. */
    comparisons : u64,
    /** What each of two threads found, by its index. */
    thread_problems : CallProblem[2],
    /** What the fiber found. */
    fiber_problem : CallProblem,
}

/**
 * qsort's comparison, a callback with the context of whoever called qsort, counting each call in its Results.
 *
 * @param a The first i32.
 * @param b The second i32.
 * @return -1, 0 or 1 as a is less than, equal to or greater than b.
 */
compare_ints #calling_convention(.c) :: fn(a: rawptr, b: rawptr) -> i32 {
    results :: cast[ptr[mut Results]](context.user_data)
    intrinsics.interlocked_increment_u64(&results.comparisons)
    left :: cast[ptr[i32]](a)^
    right :: cast[ptr[i32]](b)^
    return if left < right { -1 } else if left > right { 1 } else { 0 }
}

/**
 * Call C, by name and through values dlsym finds, wherever this runs.
 *
 * @param results Where qsort's callbacks are counted; the same as context.user_data.
 * @return None if every call gave what it should; otherwise the first that didn't.
 */
call_c :: fn(results: ptr[mut Results]) -> CallProblem {
    text : u8[8]
    text[0] = cast[u8]('h')
    text[1] = cast[u8]('e')
    text[2] = cast[u8]('m')
    text[3] = cast[u8]('e')
    text[4] = cast[u8]('r')
    text[5] = cast[u8]('a')
    text[6] = 0
    if strlen(cast[rawptr](&text[0])) != 6 {
        return .WrongLength
    }
    if cast[u64](getpid()) != raw_getpid() {
        return .WrongProcessId
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
            return .NotSorted
        }
    }
    if intrinsics.atomic_load_u64_acquire(&results.comparisons) == before {
        return .NoCallback
    }
    // Through values: C's own convention, on the thread's own stack, calling back with this context
    through_getpid :: bit_cast[Getpid](dlsym(null, "getpid"))
    if cast[u64](through_getpid()) != raw_getpid() {
        return .WrongProcessIdThroughValue
    }
    through_qsort :: bit_cast[Qsort](dlsym(null, "qsort"))
    sorted :: intrinsics.atomic_load_u64_acquire(&results.comparisons)
    numbers[0] = 6
    numbers[7] = 0
    through_qsort(cast[rawptr](&numbers[0]), 8, 4, cast[rawptr](compare_ints))
    for i in 0..<7 {
        if numbers[i] > numbers[i + 1] {
            return .NotSortedThroughValue
        }
    }
    if intrinsics.atomic_load_u64_acquire(&results.comparisons) == sorted {
        return .NoCallbackThroughValue
    }
    return .None
}

/** A thread calling C, reporting into the Results in context.user_data at its own index. */
worker : runtime.ThreadFunction : fn(data #escaping : any) {
    results :: cast[ptr[mut Results]](context.user_data)
    index :: runtime.current_thread_index()
    if index < 2 {
        results.thread_problems[index] = call_c(results)
    }
}

/** A fiber calling C, reporting into the Results in context.user_data. */
fiber_worker : runtime.ThreadFunction : fn(data #escaping : any) {
    results :: cast[ptr[mut Results]](context.user_data)
    results.fiber_problem = call_c(results)
}

/**
 * Make the Results the callers report into, each not yet run.
 *
 * @return The Results, from the context's allocator, which the caller frees.
 */
new_results :: fn() -> ptr[mut Results] {
    results :: runtime.new(Results)
    results.thread_problems[0] = .NotRun
    results.thread_problems[1] = .NotRun
    results.fiber_problem = .NotRun
    return results
}

links_the_c_library #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, intrinsics.uses_c_library(), "declaring #foreign functions from libc links it")
    return .Ok
}

calls_c_from_the_tests_thread #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    results :: new_results()
    defer runtime.free(results)
    push_context with_results (user_data = cast[rawptr](results)) {
        testing.expect_eq(t, call_c(results), CallProblem.None, "C is called, and calls back with this context, as the program's own thread")
    }
    return .Ok
}

calls_c_from_threads #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    results :: new_results()
    defer runtime.free(results)
    threads : rawptr[2]
    started : usize = 0
    push_context with_results (user_data = cast[rawptr](results)) {
        for i in 0..<cast[usize](2) {
            thread :: runtime.thread_create(worker)
            thread.index = i
            if !testing.expect(t, runtime.thread_start(thread), "pthreads starts a thread") {
                break
            }
            threads[i] = cast[rawptr](thread)
            started += 1
        }
    }
    for i in 0..<started {
        if i < 2 {
            runtime.thread_join(cast[ptr[mut runtime.Thread]](threads[i]))
        }
    }
    testing.require_eq(t, started, 2, "both threads started")?
    for problem in results.thread_problems {
        testing.expect_eq(t, problem, CallProblem.None, "threads the runtime starts through pthreads have C's own state set up")
    }
    return .Ok
}

calls_c_from_a_fiber #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    results :: new_results()
    defer runtime.free(results)
    push_context with_results (user_data = cast[rawptr](results)) {
        pool :: fiber.create_fiber_pool()
        _, error :: fiber.spawn(pool, fiber_worker)
        testing.expect(t, error == null, "the pool has room for a fiber")
        fiber.close_pool(pool)
        fiber.run_carrier(pool)
        fiber.destroy_fiber_pool(pool)
    }
    testing.expect_eq(t, results.fiber_problem, CallProblem.None, "C is called from a fiber's stack, and calls back with its context")
    return .Ok
}
