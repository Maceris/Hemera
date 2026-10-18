package memory

import intrinsics from "base"
import runtime from "base"

/*
 * A reference-counted value, safe to share between threads. Owners share one SharedPtr
 * through a pointer, and the last one to call decrement runs destructor.
 *
 *     shared :: memory.SharedPtr[Buffer].{count = 1, value = buffer, destructor = destroy_buffer}
 *     memory.increment(&shared)   // a second owner
 *     memory.decrement(&shared)   // ... which is done with it
 *     memory.decrement(&shared)   // the last owner: destroy_buffer(buffer) runs
 *
 * value is mutable for now. There's no way yet to share an immutable value, like C++'s
 * shared_ptr<const T>, since mutability isn't something a generic type can take.
 */
SharedPtr :: struct[T] {
	count : u32,
	value : ptr[mut T],
	destructor: fn(value: ptr[mut T]),
}

increment :: fn[T](pointer: ptr[mut SharedPtr[T]]) {
	// The caller already holds a reference, so there is nothing to order.
	_ = intrinsics.interlocked_increment_u32_no_fence(&pointer.count)
}

// Drops a reference, and runs the destructor if it was the last. Returns whether it was.
decrement :: fn[T](pointer: ptr[mut SharedPtr[T]]) -> bool {
	// Release, so this owner's writes happen before the count drops.
	previous :: intrinsics.interlocked_decrement_u32_release(&pointer.count)
	runtime.assert(previous > 0, "a SharedPtr was decremented more times than it was referenced")

	if previous != 1 {
		return false
	}
	// Acquire, to see every other owner's writes before destroying.
	intrinsics.fence_acquire()
	pointer.destructor(pointer.value)
	return true
}
