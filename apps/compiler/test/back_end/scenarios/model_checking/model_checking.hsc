/*
 * Model checking (docs/testing.md, Model Checking), built with --model-checked: a lost update between two threads that
 * each load and store is found, with its schedule; atomic increments and a SpinLock count both under every schedule
 * within the preemption bound; a relaxed flag seen before its data is found, as weak memory allows, and a released and
 * acquired one never is. main returns 42 if every test passed.
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

/** A message: data, then a flag that says it's there. */
Message :: struct #scoped {
    data : u32,
    flag : u32,
    t : ptr[mut testing.T]?,
}

message_of :: fn(data: any) -> ptr[mut Message] {
    return cast[ptr[ptr[mut Message]]](data.data)^
}

write_relaxed : runtime.ThreadFunction : fn(data #escaping : any) {
    message :: message_of(data)
    intrinsics.atomic_store_u32_no_fence(&message.data, 1)
    intrinsics.atomic_store_u32_no_fence(&message.flag, 1)
}

read_relaxed : runtime.ThreadFunction : fn(data #escaping : any) {
    message :: message_of(data)
    if intrinsics.atomic_load_u32_no_fence(&message.flag) == 1 {
        t :: message.t or_return void
        testing.expect_eq(t, intrinsics.atomic_load_u32_no_fence(&message.data), 1, "the data is there once the flag is")
    }
}

write_released : runtime.ThreadFunction : fn(data #escaping : any) {
    message :: message_of(data)
    intrinsics.atomic_store_u32_no_fence(&message.data, 1)
    intrinsics.atomic_store_u32_release(&message.flag, 1)
}

read_acquired : runtime.ThreadFunction : fn(data #escaping : any) {
    message :: message_of(data)
    if intrinsics.atomic_load_u32_acquire(&message.flag) == 1 {
        t :: message.t or_return void
        testing.expect_eq(t, intrinsics.atomic_load_u32_no_fence(&message.data), 1, "the data is there once the flag is")
    }
}

pass_message :: fn(data #escaping : any, writer: runtime.ThreadFunction, reader: runtime.ThreadFunction) {
    message :: message_of(data)
    message.data = 0
    message.flag = 0
    first :: testing.spawn(writer, data) or_return void
    second :: testing.spawn(reader, data) or_return void
    testing.join(first)
    testing.join(second)
}

relaxed_body : runtime.ThreadFunction : fn(data #escaping : any) {
    pass_message(data, write_relaxed, read_relaxed)
}

released_body : runtime.ThreadFunction : fn(data #escaping : any) {
    pass_message(data, write_released, read_acquired)
}

// Weak memory: a relaxed flag can be seen before the data it follows, as a weakly ordered CPU can show it
finds_a_message_seen_before_its_data #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    message :: runtime.new(Message)
    defer runtime.free(message)
    attempt :: runtime.new(testing.T)
    defer runtime.free(attempt)
    message.t = attempt
    outcome :: testing.check_model(attempt, relaxed_body, message)
    testing.expect(t, outcome is_error, "a reader that sees the flag but not the data is found")
    return .Ok
}

// Release and acquire: the data is always there once the flag is
released_messages_arrive_whole #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    message :: runtime.new(Message)
    defer runtime.free(message)
    attempt :: runtime.new(testing.T)
    defer runtime.free(attempt)
    message.t = attempt
    outcome :: testing.check_model(attempt, released_body, message)
    testing.expect(t, outcome is_ok, "every schedule's reader sees the data with the flag")
    return .Ok
}

main :: fn() -> int {
    failed :: testing.run(#insert testing.tests_of(compiler.load_package(".")), testing.STANDARD_OUTPUT)
    return if failed == 0 { 42 } else { 1 }
}
