package runtime

new :: fn[T](
    t: type, 
    allocator := context.allocator,
    loc := #caller_location,
) -> (ptr[T], AllocatorError?) {
    return new_aligned(t, align_of(T), allocator, loc)
}

new_aligned :: fn[T](
    t: type,
    alignment: int,
    allocator := context.allocator,
    loc := #caller_location,
) -> (ptr[T], AllocatorError?) {
    //TODO(ches) allocate
}

new_array :: fn[T](
    t: type,
    count: usize,
    allocator := context.allocator,
    loc := #caller_location,
) -> (T[], AllocatorError?) {
    new_array_aligned(t, count, align_of(T), allocator, loc)
}

new_array_aligned :: fn[T](
    t: type,
    count: usize,
    alignment: int,
    allocator := context.allocator,
    loc := #caller_location,
) -> (ptr[T], AllocatorError?) {
    //TODO(ches) allocate
}