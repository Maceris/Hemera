package runtime

ArrayView :: struct {
    count : u64,
    data : rawptr,
}

ResizableArray :: struct {
    count : u64,
    data : rawptr,
    capacity : u64,
    allocator : Allocator,
}

array_add :: fn<T>(array: mut T[..], value: T) ---
array_copy :: fn<T>(source: T[..], target: mut T[..]) ---
array_find :: fn<T>(array: T[..], value: T) -> (bool, u64) ---
array_reserve :: fn<T>(array: mut T[..], new_capacity: u64) ---
array_reset :: fn<T>(array: ptr<mut T[..]>) ---

peek :: fn<T>(array: T[..]) -> T ---
pop :: fn<T>(array: mut T[..]) -> T ---
