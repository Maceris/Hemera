/*
 * Model checking (docs/testing.md, Model Checking), built with --model-checked: a lost update between two threads that
 * each load and store is found, with its schedule; atomic increments and a SpinLock count both under every schedule
 * within the preemption bound. main returns 42 if every test passed.
 */
package model_checking

import runtime from "base"
import intrinsics from "base"
import compiler from "base"
import concurrency from "std"
import testing from "std"

Shared :: struct #scoped {
    count : u32,
    lock : concurrency.SpinLock,
    t : ptr[mut testing.T]?,
}

shared_of :: fn(data: any) -> ptr[mut Shared] {
    return cast[ptr[ptr[mut Shared]]](data.data)^
}

add_racily : runtime.ThreadFunction : fn(data #escaping : any) {
    shared :: shared_of(data)
    seen :: intrinsics.atomic_load_u32(&shared.count)
    intrinsics.atomic_store_u32(&shared.count, seen + 1)
}

add_atomically : runtime.ThreadFunction : fn(data #escaping : any) {
    shared :: shared_of(data)
    _ = intrinsics.interlocked_increment_u32(&shared.count)
}

add_locked : runtime.ThreadFunction : fn(data #escaping : any) {
    shared :: shared_of(data)
    concurrency.lock(&shared.lock)
    seen :: intrinsics.atomic_load_u32(&shared.count)
    intrinsics.atomic_store_u32(&shared.count, seen + 1)
    concurrency.unlock(&shared.lock)
}

run_two :: fn(data #escaping : any, add: runtime.ThreadFunction) {
    shared :: shared_of(data)
    shared.count = 0
    shared.lock = concurrency.SpinLock.{}
    first :: testing.spawn(add, data) or_return void
    second :: testing.spawn(add, data) or_return void
    testing.join(first)
    testing.join(second)
    t :: shared.t or_return void
    testing.expect_eq(t, intrinsics.atomic_load_u32(&shared.count), 2, "both increments are counted")
}

racy_body : runtime.ThreadFunction : fn(data #escaping : any) {
    run_two(data, add_racily)
}

atomic_body : runtime.ThreadFunction : fn(data #escaping : any) {
    run_two(data, add_atomically)
}

locked_body : runtime.ThreadFunction : fn(data #escaping : any) {
    run_two(data, add_locked)
}

finds_a_lost_update #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    shared :: runtime.new(Shared)
    defer runtime.free(shared)
    attempt :: runtime.new(testing.T)
    defer runtime.free(attempt)
    attempt.name = "racy"
    shared.t = attempt
    outcome :: testing.check_model(attempt, racy_body, shared)
    testing.expect(t, outcome is_error, "a lost update is found")
    for i in 0..<attempt.note_count {
        if i < attempt.notes.count {
            runtime.write_output(testing.text_of(&attempt.notes[i]))
            runtime.write_output("\n")
        }
    }
    return .Ok
}

atomic_increments_pass #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    shared :: runtime.new(Shared)
    defer runtime.free(shared)
    attempt :: runtime.new(testing.T)
    defer runtime.free(attempt)
    shared.t = attempt
    outcome :: testing.check_model(attempt, atomic_body, shared)
    testing.expect(t, outcome is_ok, "every schedule counts both increments")
    for i in 0..<attempt.note_count {
        if i < attempt.notes.count {
            runtime.write_output(testing.text_of(&attempt.notes[i]))
            runtime.write_output("\n")
        }
    }
    return .Ok
}

locked_increments_pass #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    shared :: runtime.new(Shared)
    defer runtime.free(shared)
    attempt :: runtime.new(testing.T)
    defer runtime.free(attempt)
    shared.t = attempt
    outcome :: testing.check_model(attempt, locked_body, shared)
    testing.expect(t, outcome is_ok, "every schedule counts both increments")
    for i in 0..<attempt.note_count {
        if i < attempt.notes.count {
            runtime.write_output(testing.text_of(&attempt.notes[i]))
            runtime.write_output("\n")
        }
    }
    return .Ok
}

main :: fn() -> int {
    failed :: testing.run(#insert testing.tests_of(compiler.load_package(".")), testing.STANDARD_OUTPUT)
    return if failed == 0 { 42 } else { 1 }
}
