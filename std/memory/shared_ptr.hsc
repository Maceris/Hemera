package memory

import intrinsics from "base"

/*
 * A reference-counted value, safe to share between threads. Owners share one SharedPtr
 * through a pointer, and the last one to call decrement runs destructor.
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
	_ = interlocked_increment_u32_no_fence(&pointer.count)
}

decrement :: fn[T](pointer: ptr[mut SharedPtr[T]]) {
	// Release, so this owner's writes happen before the count drops.
	previous :: interlocked_decrement_u32_release(&pointer.count)
	assert(previous > 0)

	if previous != 1 {
		return void
	}
	// Acquire, to see every other owner's writes before destroying.
	fence_acquire()
	pointer.destructor(pointer.value)
}
