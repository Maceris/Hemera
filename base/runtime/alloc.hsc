package runtime

free :: fn[T](
    pointer: ptr[T],
    allocator := context.allocator,
    loc := #caller_location,
) {
    //TODO(ches) free
}

free_all :: fn[T](
    allocator := context.allocator,
    loc := #caller_location,
) {
    //TODO(ches) free
}

free_array :: fn[T](
    array: T[],
    allocator := context.allocator,
    loc := #caller_location,
) {
    //TODO(ches) free
}

new :: fn[T](
    t: type, 
    allocator := context.allocator,
    loc := #caller_location,
) -> (ptr[mut T], AllocatorError?) {
    return new_aligned(t, align_of(T), allocator, loc)
}

new_aligned :: fn[T](
    t: type,
    alignment: int,
    allocator := context.allocator,
    loc := #caller_location,
) -> (ptr[mut T], AllocatorError?) {
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
) -> (T[], AllocatorError?) {
    //TODO(ches) allocate
}

/*
 * An allocator with no memory: every allocation fails with OutOfMemory, and freeing does
 * nothing. For a Context needed before any heap exists, like early in a kernel's boot.
 * It holds no state, so FAILING_ALLOCATOR is a constant.
 */
failing_allocator_function : AllocatorFn : fn(
    allocator_data: rawptr,
    size: usize,
    alignment: int,
    old_memory: rawptr,
    old_size: usize,
    location := #caller_location,
) -> (u8[], AllocatorError?) {
    empty : u8[]
    if size == 0 {
        return empty, null
    }
    return empty, AllocatorError.OutOfMemory
}

FAILING_ALLOCATOR :: Allocator.{failing_allocator_function, null}
