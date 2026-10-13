package runtime

/*
 * How strings, array views and dynamic arrays are laid out in memory, for code that works
 * through rawptr and type info, like std's reflection. See docs/types.md (Memory Layout).
 */
StringView :: struct {
    // In bytes.
    count : usize,
    data : rawptr,
}

ArrayView :: struct {
    count : usize,
    data : rawptr,
}

ResizableArray :: struct {
    count : usize,
    data : rawptr,
    capacity : usize,
    allocator : Allocator,
}

/*
 * Functions that change a dynamic array take a pointer to it, like array_add(&names, name),
 * so changes to its count, capacity and data reach the caller's array.
 */
array_add : fn[T](array: ptr[mut T[..]], value #escaping : T) : ---
array_copy : fn[T](source: T[], target: ptr[mut T[..]]) : ---
array_find : fn[T](array: T[], value: T) -> (bool, usize) : ---
array_free : fn[T](array: ptr[mut T[..]]) : ---
// Remove an element from an array, shifting the remainder of the array left
array_remove : fn[T](array: ptr[mut T[..]], position: usize) : ---
// Swap the last element and the given element, and reduce the size of the array by 1
array_remove_fast : fn[T](array: ptr[mut T[..]], position: usize) : ---
array_reserve : fn[T](array: ptr[mut T[..]], new_capacity: usize) : ---
array_reset : fn[T](array: ptr[mut T[..]]) : ---

peek : fn[T](array: T[]) -> T : ---
pop : fn[T](array: ptr[mut T[..]]) -> T : ---
