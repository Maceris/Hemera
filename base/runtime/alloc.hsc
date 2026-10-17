package runtime

// Give back a T from new or new_aligned, to the allocator it came from.
free :: fn[T](
    pointer: ptr[T],
    allocator := context.allocator,
    loc := #caller_location,
) {
    allocator.function(allocator.data, 0, 0, cast[rawptr](pointer), size_of(T), loc)
}

free_all :: fn[T](
    allocator := context.allocator,
    loc := #caller_location,
) {
    todo("free_all")
}

// Give back an array from new_array or new_array_aligned, to the allocator it came from.
free_array :: fn[T](
    array: T[],
    allocator := context.allocator,
    loc := #caller_location,
) {
    if array.count == 0 {
        return void
    }
    allocator.function(allocator.data, 0, 0, cast[rawptr](array.data), array.count * size_of(T), loc)
}

/*
 * A new T, from the allocator. If it can't be allocated, calls context.assertion_handler, which ends
 * the program; new_aligned and new_array return the error instead, for code that handles it.
 */
new :: fn[T](
    T: type,
    allocator := context.allocator,
    loc := #caller_location,
) -> ptr[mut T] {
    result, error :: new_aligned(T, align_of(T), allocator, loc)
    if error is_some {
        context.assertion_handler(loc, "out of memory")
    }
    return result
}

new_aligned :: fn[T](
    T: type,
    alignment: usize,
    allocator := context.allocator,
    loc := #caller_location,
) -> (ptr[mut T], AllocatorError?) {
    memory, error :: allocator.function(allocator.data, size_of(T), alignment, null, 0, loc)
    return cast[ptr[mut T]](memory.data), error
}

new_array :: fn[T](
    T: type,
    count: usize,
    allocator := context.allocator,
    loc := #caller_location,
) -> (T[], AllocatorError?) {
    return new_array_aligned(T, count, align_of(T), allocator, loc)
}

new_array_aligned :: fn[T](
    T: type,
    count: usize,
    alignment: usize,
    allocator := context.allocator,
    loc := #caller_location,
) -> (T[], AllocatorError?) {
    empty : T[]
    if count == 0 {
        return empty, null
    }
    memory, error :: allocator.function(allocator.data, count * size_of(T), alignment, null, 0, loc)
    if error != null {
        return empty, error
    }
    return view_of(cast[ptr[mut T]](memory.data), count), null
}

/*
 * An allocator with no memory: every allocation fails with OutOfMemory, and freeing does
 * nothing. For a Context needed before any heap exists, like early in a kernel's boot.
 * It holds no state, so FAILING_ALLOCATOR is a constant.
 */
failing_allocator_function : AllocatorFn : fn(
    allocator_data: rawptr,
    size: usize,
    alignment: usize,
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
