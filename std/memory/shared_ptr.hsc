package memory

import compiler from "base"
import intrinsics from "base"
import runtime from "base"

/**
 * Shared ownership (docs/memory.md, Owned Types): a value on the heap with several owners, released when the last one
 * is done with it.
 *
 *     buffer #release :: memory.make_shared(Buffer.{size = 4096}, destroy_buffer)
 *     reader :: memory.share(&buffer)        // a second owner
 *     spawn_reader(reader)                    // moved to the reader, which releases it
 *     log_info("% bytes", buffer.size)        // the value's fields, through using shared_value
 *
 * A SharedPtr is #owned: each one is released or moved on, and the compiler checks it is. The last release runs what
 * make_shared was given to destroy the value with, or, for a value that's #owned itself, its own release function, then
 * frees the block.
 *
 * SharedPtr[mut T] can change the value, and SharedPtr[T] only read it; one becomes the other by itself. Counting is
 * atomic, so owners can be on different threads; SharedPtr[T, false], or LocalPtr[T], counts with plain arithmetic, for
 * values that stay on one thread: it's #thread_bound, so the compiler stops one being given to another
 * (docs/multitasking.md). The counts are shared safely, but the value itself isn't guarded: owners on several threads
 * that change it need a lock of their own.
 *
 * It's #unrestricted: it points at its block on the heap, never into a stack, so it can be kept anywhere.
 *
 * @tparam T The value's type; mut T for owners that can change it.
 * @tparam atomic Whether the counts are changed atomically, so owners can be on different threads. False is cheaper,
 *     and binds the pointer to its thread.
 */
SharedPtr :: struct[T, atomic = true] #owned(release) #unrestricted #thread_bound(!atomic) {
    /**
     * The value, in its block on the heap, right after the block's SharedHeader; null in a zeroed SharedPtr, which owns
     * nothing. Named so it's unlikely to hide a field of the value's own, since using makes the value's fields the
     * SharedPtr's.
     */
    using shared_value : ptr[T],
}

/**
 * A SharedPtr that counts without atomics, for values that stay on one thread.
 *
 * @tparam T The value's type.
 */
LocalPtr :: alias[T] SharedPtr[T, false]

/**
 * A reference that doesn't keep the value: upgrade gives a SharedPtr while there's still one, and null once the last is
 * released.
 *
 * The block, though not the value, stays until the weak references are released too, so upgrade can always look at
 * its counts. A WeakPtr is #owned, and released with release_weak.
 *
 * @tparam T The value's type.
 * @tparam atomic Whether the counts are changed atomically, as the SharedPtr it was made from does.
 */
WeakPtr :: struct[T, atomic = true] #owned(release_weak) #unrestricted #thread_bound(!atomic) {
    /** The value, which may already be destroyed: only reached through a SharedPtr from upgrade. */
    shared_value : ptr[T],
}

/**
 * What runs when the last owner is done, to destroy the value before its block is freed.
 *
 * @param value The value, by its address. It's not to be freed: the block is freed after this returns.
 */
Destroy :: alias fn(value: rawptr)

/**
 * A destroy function for one type's values, as make_shared takes it.
 *
 * @tparam T The value's type.
 * @param value The value, which it destroys in place but doesn't free.
 */
DestroyValue :: alias[T] fn(value: ptr[mut T])

/**
 * The counts and bookkeeping before a shared value, in the same allocation, at an offset that keeps the value aligned.
 *
 * weak counts the weak references, and one more for all the strong ones together, so the block goes when both are
 * done.
 */
SharedHeader :: struct {
    /** How many SharedPtrs own the value; the value is destroyed when it reaches 0. */
    strong : u32,
    /** How many WeakPtrs there are, plus one while strong is above 0; the block is freed when it reaches 0. */
    weak : u32,
    /** What destroys the value when strong reaches 0, or null when it needs nothing. */
    destroy : Destroy?,
    /** The allocator the block came from, which it's given back to. */
    allocator : runtime.Allocator,
    /** The start of the whole block, header included, as the allocator gave it. */
    block : rawptr,
    /** The whole block's size in bytes, as it was allocated. */
    size : usize,
    /** The block's alignment in bytes, as it was allocated: the larger of the value's and the header's. */
    alignment : usize,
}

/**
 * Find the header before a value in its block.
 *
 * @tparam T The value's type.
 * @param value A value in a block from make_shared; anything else gives a pointer to memory that isn't a header.
 * @return Its header, directly before it.
 */
header_of :: fn[T](value: ptr[T]) -> ptr[mut SharedHeader] {
    return cast[ptr[mut SharedHeader]](cast[rawptr](value) - size_of(SharedHeader))
}

/**
 * Release an #owned value in a block with its own release function, for one made without a destroy of its own.
 *
 * @tparam T The value's type, which is #owned.
 * @param value The value, by its address, taken out of the block and released; the block isn't freed.
 */
release_in_place :: fn[T](value: rawptr) {
    compiler.release(compiler.take(cast[ptr[mut T]](value)))
}

/**
 * Move a value into a new shared block with its counts, and make its first owner.
 *
 * @tparam T The value's type.
 * @tparam atomic Whether the counts are changed atomically, so owners can be on different threads.
 * @param value The value, moved into the block.
 * @param destroy What runs when the last owner releases it. Null means a value whose type is #owned is released with
 *     its own release function, and anything else needs nothing.
 * @param allocator Where the block comes from, and goes back to once the last owner and weak reference are released.
 * @param location Where the call is, for the allocator and for the report if allocation fails.
 * @return The first owner, never null: if the block can't be allocated, the assertion fails ("make_shared couldn't
 *     allocate: out of memory").
 */
make_shared :: fn[T, atomic = true](value #escaping : T, destroy : DestroyValue[T]? = null, allocator := context.allocator,
    location := #caller_location) -> SharedPtr[mut T, atomic] {

    // The header right before the value, at an offset that keeps the value aligned
    alignment :: if align_of(T) > align_of(SharedHeader) { align_of(T) } else { align_of(SharedHeader) }
    offset :: (size_of(SharedHeader) + alignment - 1) / alignment * alignment
    size :: offset + size_of(T)
    memory, error :: allocator.function(allocator.data, size, alignment, null, 0, location)
    runtime.assert(error == null, "make_shared couldn't allocate: out of memory", location)
    block :: cast[rawptr](memory.data)
    at :: cast[ptr[mut T]](block + offset)
    at^ = value
    header :: header_of(at)
    header.strong = 1
    header.weak = 1
    header.destroy = null
    header.allocator = allocator
    header.block = block
    header.size = size
    header.alignment = alignment
    match destroy {
        case Some(function) => header.destroy = bit_cast[Destroy](function)
        case None => {
            #if !compiler.satisfies(compiler.Copyable(T)) {
                header.destroy = release_in_place[T]
            }
        }
    }
    return SharedPtr[mut T, atomic].{shared_value = at}
}

/**
 * Get the value's address, for passing on: a SharedPtr isn't a pointer itself.
 *
 * @tparam T The value's type.
 * @tparam atomic Whether the counts are atomic.
 * @param shared An owner of the value.
 * @return The value's address, good while some owner holds it; it doesn't keep the value itself.
 */
pointer_of :: fn[T, atomic: bool](shared: ptr[SharedPtr[T, atomic]]) -> ptr[T] {
    return shared.shared_value
}

/**
 * Make another owner of the same value, counting it.
 *
 * @tparam T The value's type.
 * @tparam atomic Whether the count is changed atomically.
 * @param shared An owner of the value, which stays one; it must own something, not be zeroed.
 * @return The new owner, which the caller releases or moves on.
 */
share :: fn[T, atomic: bool](shared: ptr[SharedPtr[T, atomic]]) -> SharedPtr[T, atomic] {
    header :: header_of(shared.shared_value)
    #if atomic {
        // The caller already holds a reference, so there's nothing to order
        _ = intrinsics.interlocked_increment_u32_no_fence(&header.strong)
    }
    #else {
        header.strong += 1
    }
    return compiler.duplicate(shared)
}

/**
 * Drop the block's weak count, freeing the block when it's the last.
 *
 * @tparam atomic Whether the count is changed atomically.
 * @param header The block's header; invalid afterwards if this was the last count.
 */
release_block :: fn[atomic: bool](header: ptr[mut SharedHeader]) {
    last := false
    #if atomic {
        last = intrinsics.interlocked_decrement_u32_release(&header.weak) == 1
        if last {
            intrinsics.fence_acquire()
        }
    }
    #else {
        header.weak -= 1
        last = header.weak == 0
    }
    if last {
        allocator :: header.allocator
        allocator.function(allocator.data, 0, header.alignment, header.block, header.size)
    }
}

/**
 * Drop an owner: the SharedPtr's release function.
 *
 * The last one destroys the value, then lets the block go, once the weak references have too. With atomic counts, each
 * owner's writes to the value happen before the destroy that the last one runs.
 *
 * @tparam T The value's type.
 * @tparam atomic Whether the count is changed atomically.
 * @param shared The owner, consumed. A zeroed SharedPtr owns nothing, and releasing it does nothing.
 */
release :: fn[T, atomic: bool](shared: SharedPtr[T, atomic]) {
    if cast[rawptr](shared.shared_value) == null {
        compiler.forget(shared)
        return void
    }
    header :: header_of(shared.shared_value)
    last := false
    #if atomic {
        // Release, so this owner's writes happen before the count drops; acquire, to see every other owner's
        last = intrinsics.interlocked_decrement_u32_release(&header.strong) == 1
        if last {
            intrinsics.fence_acquire()
        }
    }
    #else {
        header.strong -= 1
        last = header.strong == 0
    }
    if last {
        match header.destroy {
            case Some(destroy) => destroy(cast[rawptr](shared.shared_value))
            case None => {}
        }
        release_block[atomic](header)
    }
    compiler.forget(shared)
}

/**
 * Make a weak reference to a shared value, which keeps its block but not the value.
 *
 * @tparam T The value's type.
 * @tparam atomic Whether the counts are changed atomically.
 * @param shared An owner of the value; it must own something, not be zeroed.
 * @return The weak reference, which the caller releases with release_weak.
 */
weaken :: fn[T, atomic: bool](shared: ptr[SharedPtr[T, atomic]]) -> WeakPtr[T, atomic] {
    header :: header_of(shared.shared_value)
    #if atomic {
        _ = intrinsics.interlocked_increment_u32_no_fence(&header.weak)
    }
    #else {
        header.weak += 1
    }
    return WeakPtr[T, atomic].{shared_value = shared.shared_value}
}

/**
 * Make an owner of the value from a weak reference, if any owner is left.
 *
 * With atomic counts it counts up only while the count is above zero, so it never revives a value being destroyed.
 *
 * @tparam T The value's type.
 * @tparam atomic Whether the counts are changed atomically.
 * @param weak The weak reference, which stays one.
 * @return A new owner, which the caller releases or moves on; null once the last owner was released. With atomic
 *     counts it's null too if the count kept changing under it for a million attempts, which contention that heavy
 *     shouldn't reach.
 */
upgrade :: fn[T, atomic: bool](weak: ptr[WeakPtr[T, atomic]]) -> SharedPtr[T, atomic]? {
    header :: header_of(weak.shared_value)
    #if atomic {
        // Count up only while it's still above zero
        strong := intrinsics.atomic_load_u32_acquire(&header.strong)
        for attempt in 0..<1000000 {
            if strong == 0 {
                return null
            }
            old, swapped :: intrinsics.interlocked_compare_exchange_u32_acquire(&header.strong, strong + 1, strong)
            if swapped {
                return SharedPtr[T, atomic].{shared_value = weak.shared_value}
            }
            strong = old
        }
        return null
    }
    #else {
        if header.strong == 0 {
            return null
        }
        header.strong += 1
        return SharedPtr[T, atomic].{shared_value = weak.shared_value}
    }
}

/**
 * Drop a weak reference: the WeakPtr's release function. The last of the weak references and owners frees the block.
 *
 * @tparam T The value's type.
 * @tparam atomic Whether the count is changed atomically.
 * @param weak The weak reference, consumed. A zeroed one refers to nothing, and releasing it does nothing.
 */
release_weak :: fn[T, atomic: bool](weak: WeakPtr[T, atomic]) {
    if cast[rawptr](weak.shared_value) != null {
        release_block[atomic](header_of(weak.shared_value))
    }
    compiler.forget(weak)
}
