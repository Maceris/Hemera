package runtime

/*
 * Freeing passes the block's size and alignment, as it was allocated (docs/memory.md, Allocators): free and
 * free_array give back what new and new_array made, and free_aligned and free_array_aligned what new_aligned
 * and new_array_aligned made, with the same alignment.
 */

// Give back a T from new, to the allocator it came from.
free :: fn[T](
    pointer: ptr[T],
    allocator := context.allocator,
    loc := #caller_location,
) {
    allocator.function(allocator.data, 0, align_of(T), cast[rawptr](pointer), size_of(T), loc)
}

// Give back a T from new_aligned, with the alignment it was allocated with.
free_aligned :: fn[T](
    pointer: ptr[T],
    alignment: usize,
    allocator := context.allocator,
    loc := #caller_location,
) {
    allocator.function(allocator.data, 0, alignment, cast[rawptr](pointer), size_of(T), loc)
}

free_all :: fn[T](
    allocator := context.allocator,
    loc := #caller_location,
) {
    todo("free_all")
}

// Give back an array from new_array, to the allocator it came from.
free_array :: fn[T](
    array: T[],
    allocator := context.allocator,
    loc := #caller_location,
) {
    free_array_aligned(array, align_of(T), allocator, loc)
}

// Give back an array from new_array_aligned, with the alignment it was allocated with.
free_array_aligned :: fn[T](
    array: T[],
    alignment: usize,
    allocator := context.allocator,
    loc := #caller_location,
) {
    if array.count == 0 {
        return void
    }
    allocator.function(allocator.data, 0, alignment, cast[rawptr](array.data), array.count * size_of(T), loc)
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

// A new T aligned to alignment, a power of two, which free_aligned gives back with the same alignment.
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

// count Ts aligned to alignment, a power of two, which free_array_aligned gives back with the same alignment.
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
