package memory

import compiler from "base"
import intrinsics from "base"
import runtime from "base"

/*
 * Shared ownership (docs/memory.md, Owned Types): a value on the heap with several owners, released
 * when the last one is done with it.
 *
 *     buffer #release :: memory.make_shared(Buffer.{size = 4096}, destroy_buffer)
 *     reader :: memory.share(&buffer)        // a second owner
 *     spawn_reader(reader)                    // moved to the reader, which releases it
 *     log_info("% bytes", buffer.size)        // the value's fields, through using shared_value
 *
 * A SharedPtr is #owned: each one is released or moved on, and the compiler checks it is. The last
 * release runs what make_shared was given to destroy the value with, or, for a value that's #owned
 * itself, its own release function, then frees the block.
 *
 * SharedPtr[mut T] can change the value, and SharedPtr[T] only read it; one becomes the other by
 * itself. Counting is atomic, so owners can be on different threads; SharedPtr[T, false], or
 * LocalPtr[T], counts with plain arithmetic, for values that stay on one thread: it's #thread_bound, so
 * the compiler stops one being given to another (docs/multitasking.md).
 *
 * It's #unrestricted: it points at its block on the heap, never into a stack, so it can be kept anywhere.
 */
SharedPtr :: struct[T, atomic = true] #owned(release) #unrestricted #thread_bound(!atomic) {
    // Named so it's unlikely to hide a field of the value's own
    using shared_value : ptr[T],
}

// A SharedPtr that counts without atomics, for values that stay on one thread.
LocalPtr :: alias[T] SharedPtr[T, false]

/*
 * A reference that doesn't keep the value: upgrade gives a SharedPtr while there's still one, and
 * null once the last is released. The block stays until the weak references are released too.
 */
WeakPtr :: struct[T, atomic = true] #owned(release_weak) #unrestricted #thread_bound(!atomic) {
    shared_value : ptr[T],
}

/*
 * Before the value, in the same allocation. weak counts the weak references, and one more for all
 * the strong ones together, so the block goes when both are done.
 */
// What runs when the last owner is done: given the value, by its address
Destroy :: alias fn(value: rawptr)

// A destroy function for one type's values
DestroyValue :: alias[T] fn(value: ptr[mut T])

SharedHeader :: struct {
    strong : u32,
    weak : u32,
    destroy : Destroy?,
    allocator : runtime.Allocator,
    block : rawptr,
    size : usize,
}

// The header before a value in its block.
header_of :: fn[T](value: ptr[T]) -> ptr[mut SharedHeader] {
    return cast[ptr[mut SharedHeader]](cast[rawptr](value) - size_of(SharedHeader))
}

// Releases an #owned value in a block, for one made without its own destroy.
release_in_place :: fn[T](value: rawptr) {
    compiler.release(compiler.take(cast[ptr[mut T]](value)))
}

/*
 * value, moved into a new block with its counts, and its first owner. destroy runs when the last owner
 * releases it; without one, a value whose type is #owned is released with its own release function,
 * and anything else needs nothing.
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

// The value's address, for passing on: a SharedPtr isn't a pointer itself.
pointer_of :: fn[T, atomic: bool](shared: ptr[SharedPtr[T, atomic]]) -> ptr[T] {
    return shared.shared_value
}

// Another owner of the same value.
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

// Drops the block's weak count, freeing it when it's the last.
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
        allocator.function(allocator.data, 0, 0, header.block, header.size, #caller_location)
    }
}

/*
 * Drops an owner. The last one destroys the value, then lets the block go, once the weak references
 * have too. A zeroed SharedPtr owns nothing.
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

// A weak reference to a shared value.
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

// An owner of the value, if any owner is left; null once the last was released.
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

release_weak :: fn[T, atomic: bool](weak: WeakPtr[T, atomic]) {
    if cast[rawptr](weak.shared_value) != null {
        release_block[atomic](header_of(weak.shared_value))
    }
    compiler.forget(weak)
}
