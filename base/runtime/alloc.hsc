package runtime

import intrinsics from "base"

/*
 * Freeing passes the block's size and alignment, as it was allocated (docs/memory.md, Allocators): free and
 * free_array give back what new and new_array made, and free_aligned and free_array_aligned what new_aligned
 * and new_array_aligned made, with the same alignment. Memory of a #secret type is zeroed first, so no key is
 * left where the allocator gives it out again (docs/memory.md, Secrets).
 */

/**
 * Give back a T from new, to the allocator it came from.
 *
 * A #secret T is zeroed before it's given back. The block is freed with T's natural alignment, so a T from
 * new_aligned goes back through free_aligned instead.
 *
 * @tparam T The type pointed to, whose size and alignment are passed to the allocator as the block's.
 * @param pointer The T, from new (or new_aligned with align_of(T)) on this same allocator. It mustn't be used
 *     afterwards, nor freed twice; whether null is accepted is up to the allocator.
 * @param allocator The allocator it came from; the context's by default.
 * @param loc Where the free was called, which the allocator may report; the caller's own by default.
 */
free :: fn[T](
    pointer: ptr[T],
    allocator := context.allocator,
    loc := #caller_location,
) {
    if is_secret_type(T) {
        intrinsics.secure_zero(cast[mut rawptr](cast[rawptr](pointer)), size_of(T))
    }
    allocator.function(allocator.data, 0, align_of(T), cast[rawptr](pointer), size_of(T), loc)
}

/**
 * Give back a T from new_aligned, with the alignment it was allocated with.
 *
 * A #secret T is zeroed before it's given back.
 *
 * @tparam T The type pointed to, whose size is passed to the allocator as the block's.
 * @param pointer The T, from new_aligned on this same allocator. It mustn't be used afterwards, nor freed twice.
 * @param alignment The alignment, in bytes, that new_aligned was given for it; an allocator may use it to find the
 *     block, so it has to be the same.
 * @param allocator The allocator it came from; the context's by default.
 * @param loc Where the free was called, which the allocator may report; the caller's own by default.
 */
free_aligned :: fn[T](
    pointer: ptr[T],
    alignment: usize,
    allocator := context.allocator,
    loc := #caller_location,
) {
    if is_secret_type(T) {
        intrinsics.secure_zero(cast[mut rawptr](cast[rawptr](pointer)), size_of(T))
    }
    allocator.function(allocator.data, 0, alignment, cast[rawptr](pointer), size_of(T), loc)
}

/**
 * Give back everything an allocator gave out, at once. Not written yet: calling it stops the program, through
 * todo and context.assertion_handler.
 *
 * @tparam T Unused so far.
 * @param allocator The allocator whose memory would all be given back; the context's by default.
 * @param loc Where it was called, which the assertion handler reports; the caller's own by default.
 */
free_all :: fn[T](
    allocator := context.allocator,
    loc := #caller_location,
) {
    todo("free_all")
}

/**
 * Give back an array from new_array, to the allocator it came from.
 *
 * A #secret T's elements are zeroed first. An empty array is left alone, since new_array allocates nothing for
 * one.
 *
 * @tparam T The element type, whose alignment the array was allocated with.
 * @param array The array, whole, as new_array gave it: its count and data have to be the ones allocated, not a
 *     slice of them, since the allocator is given count times T's size as the block's size. None of its elements
 *     may be used afterwards.
 * @param allocator The allocator it came from; the context's by default.
 * @param loc Where the free was called, which the allocator may report; the caller's own by default.
 */
free_array :: fn[T](
    array: T[],
    allocator := context.allocator,
    loc := #caller_location,
) {
    free_array_aligned(array, align_of(T), allocator, loc)
}

/**
 * Give back an array from new_array_aligned, with the alignment it was allocated with.
 *
 * A #secret T's elements are zeroed first. An empty array is left alone, since nothing was allocated for one.
 *
 * @tparam T The element type.
 * @param array The array, whole, as new_array_aligned gave it: its count and data have to be the ones allocated,
 *     not a slice of them. None of its elements may be used afterwards.
 * @param alignment The alignment, in bytes, that new_array_aligned was given for it.
 * @param allocator The allocator it came from; the context's by default.
 * @param loc Where the free was called, which the allocator may report; the caller's own by default.
 */
free_array_aligned :: fn[T](
    array: T[],
    alignment: usize,
    allocator := context.allocator,
    loc := #caller_location,
) {
    if array.count == 0 {
        return void
    }
    if is_secret_type(T) {
        intrinsics.secure_zero(cast[mut rawptr](cast[rawptr](array.data)), array.count * size_of(T))
    }
    allocator.function(allocator.data, 0, alignment, cast[rawptr](array.data), array.count * size_of(T), loc)
}

/**
 * Allocate a new T, with its fields' defaults as a variable starts with them (docs/types.md, Structs).
 *
 * If it can't be allocated, calls context.assertion_handler with "out of memory", which ends the program;
 * new_aligned and new_array return the error instead, for code that handles it.
 *
 * @tparam T The type to allocate.
 * @param T The type, given as a value so a call reads new(Point).
 * @param allocator Where the memory comes from, and where free has to give it back to; the context's by default.
 * @param loc Where it was called, which the allocator and the assertion handler may report; the caller's own by
 *     default.
 * @return The new T, aligned to T's natural alignment, owned by the caller until it's given to free. Never null.
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

/**
 * Allocate a new T aligned to a given alignment, which free_aligned gives back with the same alignment.
 *
 * Its fields start with their defaults, as new's do.
 *
 * @tparam T The type to allocate.
 * @param T The type, given as a value so a call reads new_aligned(Page, 4096).
 * @param alignment The alignment in bytes: a power of two, which may be more than T's own.
 * @param allocator Where the memory comes from, and where free_aligned has to give it back to; the context's by
 *     default.
 * @param loc Where it was called, which the allocator may report; the caller's own by default.
 * @return The new T, owned by the caller until it's given to free_aligned. When there's an error, it's whatever the
 *     allocator gave with the error (null for the runtime's allocators) and mustn't be used.
 * @return Null on success, or the allocator's error, OutOfMemory when there wasn't the memory.
 */
new_aligned :: fn[T](
    T: type,
    alignment: usize,
    allocator := context.allocator,
    loc := #caller_location,
) -> (ptr[mut T], AllocatorError?) {
    memory, error :: allocator.function(allocator.data, size_of(T), alignment, null, 0, loc)
    made :: cast[ptr[mut T]](memory.data)
    // Allocators give zeroed memory, so only a type with defaults needs them stored (docs/types.md, Structs)
    #if has_defaults(T) {
        if error == null {
            intrinsics.store_defaults(made)
        }
    }
    return made, error
}

/**
 * Allocate an array of count Ts, each with its fields' defaults, which free_array gives back.
 *
 * Unlike new, running out of memory isn't fatal: the error is returned for the caller to handle.
 *
 * @tparam T The element type.
 * @param T The element type, given as a value so a call reads new_array(u8, 64).
 * @param count How many elements, not bytes. 0 allocates nothing and gives an empty array.
 * @param allocator Where the memory comes from, and where free_array has to give it back to; the context's by
 *     default.
 * @param loc Where it was called, which the allocator may report; the caller's own by default.
 * @return The array, count elements long and aligned to T's natural alignment, owned by the caller until it's given
 *     to free_array. Empty when count is 0 or there's an error.
 * @return Null on success, or the allocator's error, OutOfMemory when there wasn't the memory.
 */
new_array :: fn[T](
    T: type,
    count: usize,
    allocator := context.allocator,
    loc := #caller_location,
) -> (mut T[], AllocatorError?) {
    return new_array_aligned(T, count, align_of(T), allocator, loc)
}

/**
 * Allocate an array of count Ts aligned to a given alignment, which free_array_aligned gives back with the same
 * alignment.
 *
 * Each element starts with its fields' defaults, as new's do.
 *
 * @tparam T The element type.
 * @param T The element type, given as a value so a call reads new_array_aligned(u8, 4096, 4096).
 * @param count How many elements, not bytes. 0 allocates nothing and gives an empty array. count times T's size
 *     isn't checked for overflow.
 * @param alignment The alignment of the first element, in bytes: a power of two, which may be more than T's own.
 * @param allocator Where the memory comes from, and where free_array_aligned has to give it back to; the context's
 *     by default.
 * @param loc Where it was called, which the allocator may report; the caller's own by default.
 * @return The array, count elements long, owned by the caller until it's given to free_array_aligned. Empty when
 *     count is 0 or there's an error.
 * @return Null on success, or the allocator's error, OutOfMemory when there wasn't the memory.
 */
new_array_aligned :: fn[T](
    T: type,
    count: usize,
    alignment: usize,
    allocator := context.allocator,
    loc := #caller_location,
) -> (mut T[], AllocatorError?) {
    empty : mut T[]
    if count == 0 {
        return empty, null
    }
    memory, error :: allocator.function(allocator.data, count * size_of(T), alignment, null, 0, loc)
    if error != null {
        return empty, error
    }
    made :: view_of(cast[ptr[mut T]](memory.data), count)
    #if has_defaults(T) {
        for &element in made {
            intrinsics.store_defaults(element)
        }
    }
    return made, null
}

/**
 * Allocate nothing: the function of an allocator with no memory, FAILING_ALLOCATOR.
 *
 * For a Context needed before any heap exists, like early in a kernel's boot. It holds no state, so
 * FAILING_ALLOCATOR is a constant.
 *
 * @param allocator_data Unused; FAILING_ALLOCATOR's is null.
 * @param size The bytes asked for. 0, which frees, succeeds and does nothing; anything more fails.
 * @param alignment Unused.
 * @param old_memory Unused, since nothing it could be given was allocated by it.
 * @param old_size Unused.
 * @param location Unused.
 * @return An empty view, always.
 * @return Null when size is 0, otherwise OutOfMemory.
 */
failing_allocator_function : AllocatorFn : fn(
    allocator_data: rawptr,
    size: usize,
    alignment: usize,
    old_memory: rawptr,
    old_size: usize,
    location := #caller_location,
) -> (mut u8[], AllocatorError?) {
    empty : mut u8[]
    if size == 0 {
        return empty, null
    }
    return empty, AllocatorError.OutOfMemory
}

/**
 * An allocator with no memory: every allocation fails with OutOfMemory, and freeing does nothing
 * (failing_allocator_function).
 */
FAILING_ALLOCATOR :: Allocator.{failing_allocator_function, null}
