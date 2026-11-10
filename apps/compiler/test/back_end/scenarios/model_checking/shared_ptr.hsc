package model_checking

import runtime from "base"
import intrinsics from "base"
import compiler from "base"
import memory from "std"
import testing from "std"

/*
 * SharedPtr's counts under the model checker (docs/testing.md, Model Checking): owners released on two threads destroy
 * the value once, after both owners' writes; a weak reference upgraded while the last owner goes either gets the value,
 * not yet destroyed, or nothing. The threads are handed their owners as the value's address, which each makes its owner
 * of again, as upgrade does.
 */

/** What the threads' owners destroy, and what they wrote to it. */
Counted :: struct {
    /** Each owner's mark, a relaxed store before it releases. */
    marks : u32[2],
    /** Where its destruction is counted. */
    tally : ptr[mut Tally],
}

/** What the test sees of the value's destruction. */
Tally :: struct {
    /** How many times it was destroyed. */
    destroyed : u32,
    /** How many marks were there when it was. */
    marks_seen : u32,
    /** Whether an upgraded owner found it destroyed while it held it. */
    destroyed_while_held : bool,
}

/** The value the threads own, by its address, and where its destruction is counted. */
Holder :: struct {
    /** The value's address in its shared block, as a number, which isn't a pointer into anyone's stack. */
    value : u64,
    tally : ptr[mut Tally],
    /** How many executions went wrong, as each body checks once its threads have ended. */
    wrong : u32,
}

holder_of :: fn(data: any) -> ptr[mut Holder] {
    return cast[ptr[ptr[mut Holder]]](data.data)^
}

/**
 * Give the holder's value as the pointer an owner holds.
 *
 * @param holder The holder.
 * @return The value; null before it's made.
 */
value_of :: fn(holder: ptr[Holder]) -> ptr[mut Counted]? {
    if holder.value == 0 {
        return null
    }
    return cast[ptr[mut Counted]](cast[rawptr](cast[uintptr](holder.value)))
}

/** Count the value's destruction, and the marks it saw. */
destroy_counted :: fn(value: ptr[mut Counted]) {
    tally :: value.tally
    tally.destroyed += 1
    for i in 0..<value.marks.count {
        tally.marks_seen += intrinsics.atomic_load_u32_no_fence(&value.marks[i])
    }
}

/**
 * Mark the value as one owner, then release that owner.
 *
 * @param data The holder.
 * @param which Which mark: 0 or 1.
 */
mark_and_release :: fn(data: any, which: usize) {
    holder :: holder_of(data)
    value :: value_of(holder) or_return void
    owner :: memory.SharedPtr[Counted].{shared_value = value}
    if which < value.marks.count {
        intrinsics.atomic_store_u32_no_fence(&value.marks[which], 1)
    }
    memory.release(owner)
}

mark_first : runtime.ThreadFunction : fn(data #escaping : any) {
    mark_and_release(data, 0)
}

mark_second : runtime.ThreadFunction : fn(data #escaping : any) {
    mark_and_release(data, 1)
}

two_owners_body : runtime.ThreadFunction : fn(data #escaping : any) {
    holder :: holder_of(data)
    holder.tally^ = Tally.{}
    made :: memory.make_shared(Counted.{tally = holder.tally}, destroy_counted)
    // Two owners, each the thread's that makes it again from the value's address
    other :: memory.share(&made)
    holder.value = cast[u64](cast[uintptr](made.shared_value))
    compiler.forget(made)
    compiler.forget(other)
    first :: testing.spawn(mark_first, data) or_return void
    second :: testing.spawn(mark_second, data) or_return void
    testing.join(first)
    testing.join(second)
    if holder.tally.destroyed != 1 || holder.tally.marks_seen != 2 {
        holder.wrong += 1
    }
}

release_owner : runtime.ThreadFunction : fn(data #escaping : any) {
    holder :: holder_of(data)
    value :: value_of(holder) or_return void
    memory.release(memory.SharedPtr[Counted].{shared_value = value})
}

upgrade_and_check : runtime.ThreadFunction : fn(data #escaping : any) {
    holder :: holder_of(data)
    value :: value_of(holder) or_return void
    weak := memory.WeakPtr[Counted].{shared_value = value}
    match memory.upgrade(&weak) {
        case Some(owner) => {
            // Held: not destroyed until it's released
            if holder.tally.destroyed != 0 {
                holder.tally.destroyed_while_held = true
            }
            memory.release(owner)
        }
        case None => {}
    }
    // The weak reference is the body's, which releases it
    compiler.forget(weak)
}

upgrade_body : runtime.ThreadFunction : fn(data #escaping : any) {
    holder :: holder_of(data)
    holder.tally^ = Tally.{}
    made :: memory.make_shared(Counted.{tally = holder.tally}, destroy_counted)
    weak :: memory.weaken(&made)
    holder.value = cast[u64](cast[uintptr](made.shared_value))
    compiler.forget(made)
    first :: testing.spawn(release_owner, data) or_return void
    second :: testing.spawn(upgrade_and_check, data) or_return void
    testing.join(first)
    testing.join(second)
    memory.release_weak(weak)
    if holder.tally.destroyed != 1 || holder.tally.destroyed_while_held {
        holder.wrong += 1
    }
}

shared_values_are_destroyed_once_after_every_owner #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    holder :: runtime.new(Holder)
    defer runtime.free(holder)
    tally :: runtime.new(Tally)
    defer runtime.free(tally)
    holder.tally = tally
    attempt :: runtime.new(testing.T)
    defer runtime.free(attempt)
    outcome :: testing.check_model(attempt, two_owners_body, holder)
    testing.expect(t, outcome is_ok, "every schedule runs")
    testing.expect_eq(t, holder.wrong, 0, "in every schedule, the value is destroyed once, seeing both owners' marks")
    return .Ok
}

upgrades_never_get_a_destroyed_value #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    holder :: runtime.new(Holder)
    defer runtime.free(holder)
    tally :: runtime.new(Tally)
    defer runtime.free(tally)
    holder.tally = tally
    attempt :: runtime.new(testing.T)
    defer runtime.free(attempt)
    outcome :: testing.check_model(attempt, upgrade_body, holder)
    testing.expect(t, outcome is_ok, "every schedule runs")
    testing.expect_eq(t, holder.wrong, 0, "in every schedule, an upgraded owner never holds a destroyed value, and it's destroyed once")
    return .Ok
}
