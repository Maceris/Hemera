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
array_free :: fn[T](array: mut T[..]) --
array_reserve :: fn[T](array: mut T[..], new_capacity: usize) ---
array_reset :: fn[T](array: ptr[mut T[..]]) ---

peek :: fn[T](array: T[..]) -> T ---
pop :: fn[T](array: mut T[..]) -> T ---
