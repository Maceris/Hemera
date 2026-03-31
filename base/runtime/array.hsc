package runtime

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

array_add :: fn[T](array: mut T[..], value: T) ---
array_copy :: fn[T](source: T[..], target: mut T[..]) ---
array_find :: fn[T](array: T[..], value: T) -> (bool, usize) ---
array_free :: fn[T](array: mut T[..]) ---
// Remove an element from an array, shifting the remainder of the array left
array_remove :: fn[T](array: mut T[..], position: usize) ---
// Swap the last element and the given element, and reduce the size of the array by 1
array_remove_fast :: fn[T](array: mut T[..], position: usize) ---
array_reserve :: fn[T](array: mut T[..], new_capacity: usize) ---
array_reset :: fn[T](array: ptr[mut T[..]]) ---

peek :: fn[T](array: T[..]) -> T ---
pop :: fn[T](array: mut T[..]) -> T ---
