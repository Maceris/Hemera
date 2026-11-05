package runtime

import compiler from "base"
import intrinsics from "base"

/**
 * How a string is laid out in memory, for code that works through rawptr and type info, like std's reflection
 * (docs/types.md, Memory Layout).
 */
StringView :: struct {
    /** Its length in bytes, not characters. */
    count : usize,
    /** Its first byte, which it doesn't own; null or anything for an empty string. No 0 need follow the last byte. */
    data : rawptr,
}

/**
 * How an array view, T[], is laid out in memory, for code that works through rawptr and type info
 * (docs/types.md, Memory Layout).
 */
ArrayView :: struct {
    /** How many elements it has, not bytes. */
    count : usize,
    /** Its first element, which it doesn't own; null or anything for an empty view. */
    data : rawptr,
}

/**
 * How a dynamic array, T[..], is laid out in memory, for code that works through rawptr and type info
 * (docs/types.md, Memory Layout). Its first two fields are an ArrayView's, so a dynamic array converts to a view.
 */
ResizableArray :: struct {
    /** How many elements it has, not bytes; at most capacity. */
    count : usize,
    /** Its first element, in a block from allocator that the array owns; null until it first has memory. */
    data : rawptr,
    /** How many elements its block holds, not bytes; 0 while it has none. */
    capacity : usize,
    /**
     * Where its memory comes from and goes back to: none until it first needs memory, then the context's allocator
     * at that time, kept from then on, even through array_free.
     */
    allocator : Allocator,
}

/*
 * Dynamic arrays (docs/types.md, Dynamic Arrays). Functions that change one take a pointer to it,
 * like array_add(&names, name), so changes to its count, capacity and data reach the caller's
 * array. Functions that only read one take a view, which a dynamic array converts to.
 *
 *     names : string[..]
 *     defer array_free(&names)
 *     array_add(&names, "first")
 *     array_add(&names, "second")
 *     last :: pop(&names)        // "second"
 *
 * An array starts empty, with no memory and no allocator. The first time it needs memory it takes
 * the context's allocator, which it keeps from then on, so every block comes from and goes back to
 * the same one. It grows by doubling, from ARRAY_MINIMUM_CAPACITY. Running out of memory calls
 * context.assertion_handler, like new.
 */

/** The capacity, in elements, a dynamic array grows to first when array_add finds it full, after which it doubles. */
ARRAY_MINIMUM_CAPACITY : usize : 4

/**
 * View a dynamic array's fields, as a ResizableArray.
 *
 * @tparam T The element type.
 * @param array The dynamic array, which isn't changed by the call; it has to stay where it is while the result is
 *     used.
 * @return Its fields, at the same address as the array, so changing them changes the array; good for as long as
 *     array is.
 */
resizable :: fn[T](array: ptr[mut T[..]]) -> ptr[mut ResizableArray] {
    return cast[ptr[mut ResizableArray]](cast[rawptr](array))
}

/**
 * Find where an element of a dynamic array is.
 *
 * @tparam T The element type.
 * @param raw The dynamic array's fields, as resizable gives them; only data is read, and it isn't checked, so for an
 *     array with no memory yet the address is counted from null.
 * @param index Which element, counted from 0. It isn't checked against count or capacity, so it may be past the
 *     end, as for the place array_add stores into.
 * @param T The element type, given as a value, whose size the address is counted in.
 * @return The element's address, good until the array's memory moves or is freed: until it grows or is freed.
 */
element_address :: fn[T](raw: ptr[ResizableArray], index: usize, T: type) -> ptr[mut T] {
    return cast[ptr[mut T]](raw.data + index * size_of(T))
}

/**
 * Make room in a dynamic array for at least new_capacity elements, keeping the ones there are.
 *
 * Without the memory, calls context.assertion_handler, which ends the program; array_try_reserve gives the error
 * instead.
 *
 * @tparam T The element type.
 * @param array The array. When it grows, its elements move to a new block, so addresses of them taken before are
 *     no longer good.
 * @param new_capacity The least capacity it should have, in elements. Nothing happens when it has that already, so
 *     it never shrinks.
 * @param location Where it was called, which the allocator and the assertion handler may report; the caller's own
 *     by default.
 */
array_reserve :: fn[T](array: ptr[mut T[..]], new_capacity: usize, location := #caller_location) {
    if array_try_reserve(array, new_capacity, location) != null {
        context.assertion_handler(location, "out of memory")
    }
}

/**
 * Make room in a dynamic array for at least new_capacity elements, as array_reserve does, but give back the error
 * without the memory.
 *
 * For code that handles running out, as map_try_put does for maps. The new block holds exactly new_capacity
 * elements; doubling is array_add's own.
 *
 * @tparam T The element type.
 * @param array The array. When it grows, its elements move to a new block, so addresses of them taken before are
 *     no longer good.
 * @param new_capacity The least capacity it should have, in elements. Nothing happens when it has that already, so
 *     it never shrinks.
 * @param location Where it was called, which the allocator may report; the caller's own by default.
 * @return Null when there's room, or the allocator's error, OutOfMemory when there wasn't the memory. The array's
 *     elements, count and capacity are then as they were, though an array that had no allocator yet keeps the
 *     context's from then on.
 */
array_try_reserve :: fn[T](array: ptr[mut T[..]], new_capacity: usize, location := #caller_location) -> AllocatorError? {
    raw :: resizable(array)
    if new_capacity <= raw.capacity {
        return null
    }
    if cast[rawptr](raw.allocator.function) == null {
        raw.allocator = context.allocator
    }
    allocator :: raw.allocator
    memory, error :: allocator.function(allocator.data, new_capacity * size_of(T), align_of(T), null, 0, location)
    if error != null {
        return error
    }
    if raw.count > 0 {
        intrinsics.mem_copy_non_overlapping(cast[mut rawptr](memory.data), raw.data, raw.count * size_of(T))
    }
    if raw.capacity > 0 {
        allocator.function(allocator.data, 0, align_of(T), raw.data, raw.capacity * size_of(T), location)
    }
    raw.data = cast[rawptr](memory.data)
    raw.capacity = new_capacity
    return null
}

/**
 * Give the capacity a full array grows to: twice its own, at least ARRAY_MINIMUM_CAPACITY, and room for one more than
 * it has.
 *
 * @param raw The array, only read; its count may be past its capacity, as a schema's reader leaves one.
 * @return The capacity, in elements.
 */
grown_capacity :: fn(raw: ptr[ResizableArray]) -> usize {
    doubled :: raw.capacity * 2
    wanted :: if doubled > ARRAY_MINIMUM_CAPACITY { doubled } else { ARRAY_MINIMUM_CAPACITY }
    return if wanted > raw.count { wanted } else { raw.count + 1 }
}

/**
 * Add a value at the end of a dynamic array, growing it if it's full.
 *
 * A full array grows to twice its capacity, or to ARRAY_MINIMUM_CAPACITY from empty. Without the memory, calls
 * context.assertion_handler, which ends the program; array_try_add gives the error instead.
 *
 * @tparam T The element type.
 * @param array The array. When it grows, its elements move, so addresses of them taken before are no longer good.
 * @param value The value, copied in; #escaping, since the array keeps it after the call.
 * @param location Where it was called, which the allocator and the assertion handler may report; the caller's own
 *     by default.
 */
array_add :: fn[T](array: ptr[mut T[..]], value #escaping : T, location := #caller_location) {
    raw :: resizable(array)
    // Past its capacity, an array owns none of its elements' memory, like one read back with a schema
    if raw.count >= raw.capacity {
        array_reserve(array, grown_capacity(raw), location)
    }
    element_address(raw, raw.count, T)^ = value
    raw.count += 1
}

/**
 * Add a value at the end of a dynamic array, as array_add does, but give back the error without the memory to grow.
 *
 * @tparam T The element type.
 * @param array The array. When it grows, its elements move, so addresses of them taken before are no longer good.
 * @param value The value, copied in; #escaping, since the array keeps it after the call.
 * @param location Where it was called, which the allocator may report; the caller's own by default.
 * @return Null when it was added, or the allocator's error, OutOfMemory when there wasn't the memory; the array is
 *     then as it was, without value.
 */
array_try_add :: fn[T](array: ptr[mut T[..]], value #escaping : T, location := #caller_location) -> AllocatorError? {
    raw :: resizable(array)
    if raw.count >= raw.capacity {
        error :: array_try_reserve(array, grown_capacity(raw), location)
        if error != null {
            return error
        }
    }
    array_add(array, value, location)
    return null
}

/**
 * Add each of source's elements at the end of target, in order, as array_copy does, but give back the error without
 * the memory.
 *
 * @tparam T The element type.
 * @param source The elements, copied; source itself isn't changed. It mustn't view target's own memory, which may
 *     move as target grows.
 * @param target The array they're added to. When it grows, its elements move, so addresses of them taken before are
 *     no longer good.
 * @param location Where it was called, which the allocator may report; the caller's own by default.
 * @return Null when they were all added, or the allocator's error, OutOfMemory when there wasn't the memory; target
 *     is then as it was, with none of them added.
 */
array_try_copy :: fn[T](source: T[], target: ptr[mut T[..]], location := #caller_location) -> AllocatorError? {
    raw :: resizable(target)
    if raw.count + source.count > raw.capacity {
        error :: array_try_reserve(target, raw.count + source.count, location)
        if error != null {
            return error
        }
    }
    array_copy(source, target, location)
    return null
}

/**
 * Add each of source's elements at the end of target, in order.
 *
 * Room for them all is made at once, exactly enough. Without the memory, calls context.assertion_handler, which ends
 * the program; array_try_copy gives the error instead.
 *
 * @tparam T The element type.
 * @param source The elements, copied; source itself isn't changed, and may be empty, which does nothing. It mustn't
 *     view target's own memory, which may move as target grows.
 * @param target The array they're added to. When it grows, its elements move, so addresses of them taken before are
 *     no longer good.
 * @param location Where it was called, which the allocator and the assertion handler may report; the caller's own
 *     by default.
 */
array_copy :: fn[T](source: T[], target: ptr[mut T[..]], location := #caller_location) {
    raw :: resizable(target)
    if source.count == 0 {
        return void
    }
    if raw.count + source.count > raw.capacity {
        array_reserve(target, raw.count + source.count, location)
    }
    // One at a time, so the elements are checked like array_add's: they're kept, but source isn't
    for element in source {
        array_add(target, element, location)
    }
}

/**
 * Find where a value first is in an array, comparing with ==.
 *
 * @tparam T The element type, which has to be comparable with ==.
 * @param array The elements to look through, from the first; may be empty.
 * @param value The value to find.
 * @return The index of the first element equal to value, or None when there's none, as for an empty array.
 */
array_find :: fn[T: compiler.Equatable](array: T[], value: T) -> usize? {
    for element, index in array {
        if element == value {
            return index
        }
    }
    return null
}

/**
 * Give a dynamic array's memory back to its allocator, leaving it empty, with no memory.
 *
 * A #secret type's elements are zeroed first, the whole capacity of them. The array keeps its allocator, so what's
 * added next comes from the same one. An array with no memory is left as it is, so freeing twice is harmless. The
 * elements aren't released: for owned values, array_release does that.
 *
 * @tparam T The element type.
 * @param array The array. Addresses of its elements are no longer good afterwards.
 * @param location Where it was called, which the allocator may report; the caller's own by default.
 */
array_free :: fn[T](array: ptr[mut T[..]], location := #caller_location) {
    raw :: resizable(array)
    if raw.capacity > 0 {
        // A #secret type's elements, zeroed first, as free_array does (alloc.hsc)
        if is_secret_type(T) {
            intrinsics.secure_zero(cast[mut rawptr](raw.data), raw.capacity * size_of(T))
        }
        raw.allocator.function(raw.allocator.data, 0, align_of(T), raw.data, raw.capacity * size_of(T), location)
    }
    raw.data = null
    raw.count = 0
    raw.capacity = 0
}

/**
 * Give up a dynamic array of owned values (docs/memory.md, Owned Types): each element released, then the array's
 * memory given back.
 *
 * @tparam T The element type, an owned type.
 * @param array The array, taken: it's #escaping, and the caller's copy mustn't be used afterwards.
 * @param release What releases one element, like close_file; it's called once for each, in order, and owns the value
 *     it's given.
 * @param location Where it was called, which the allocator may report; the caller's own by default.
 * @example runtime.array_release(files, close_file)
 */
array_release :: fn[T](array #escaping : T[..], release: (fn(value: T)), location := #caller_location) {
    // Its own now, to take the elements out of
    items := array
    for &item in items {
        release(compiler.take(item))
    }
    array_free(&items, location)
    compiler.forget(items)
}

/**
 * Empty a dynamic array, keeping its memory for what's added next.
 *
 * The elements are only forgotten: they aren't released, and a #secret type's aren't zeroed until array_free.
 *
 * @tparam T The element type.
 * @param array The array, whose count becomes 0 and whose capacity stays.
 */
array_reset :: fn[T](array: ptr[mut T[..]]) {
    resizable(array).count = 0
}

/**
 * Remove the element at a position, moving the ones after it down one, so their order is kept.
 *
 * It takes time in proportion to the elements after it; array_remove_fast doesn't keep the order but takes the same
 * time for any position. The element removed isn't released.
 *
 * @tparam T The element type.
 * @param array The array, one element shorter afterwards; its capacity stays.
 * @param position The element's index, counted from 0. Past the last element, it calls context.assertion_handler,
 *     which ends the program.
 * @param location Where it was called, which the assertion handler reports; the caller's own by default.
 */
array_remove :: fn[T](array: ptr[mut T[..]], position: usize, location := #caller_location) {
    raw :: resizable(array)
    if position >= raw.count {
        context.assertion_handler(location, "array_remove past the end of the array")
    }
    after :: raw.count - position - 1
    if after > 0 {
        intrinsics.mem_copy(cast[mut rawptr](element_address(raw, position, T)), cast[rawptr](element_address(raw, position + 1, T)),
            after * size_of(T))
    }
    raw.count -= 1
}

/**
 * Remove the element at a position by moving the last element into its place: faster, but the order changes.
 *
 * The element removed isn't released.
 *
 * @tparam T The element type.
 * @param array The array, one element shorter afterwards; its capacity stays.
 * @param position The element's index, counted from 0. Past the last element, it calls context.assertion_handler,
 *     which ends the program.
 * @param location Where it was called, which the assertion handler reports; the caller's own by default.
 */
array_remove_fast :: fn[T](array: ptr[mut T[..]], position: usize, location := #caller_location) {
    raw :: resizable(array)
    if position >= raw.count {
        context.assertion_handler(location, "array_remove_fast past the end of the array")
    }
    last :: raw.count - 1
    if position != last {
        element_address(raw, position, T)^ = element_address(raw, last, T)^
    }
    raw.count = last
}

/**
 * Give an array's last element, leaving it there.
 *
 * @tparam T The element type.
 * @param array The array, which mustn't be empty: for an empty one it calls context.assertion_handler, which ends
 *     the program.
 * @param location Where it was called, which the assertion handler reports; the caller's own by default.
 * @return A copy of the last element.
 */
peek :: fn[T](array: T[], location := #caller_location) -> T {
    if array.count == 0 {
        context.assertion_handler(location, "peek at an empty array")
    }
    return array[array.count - 1]
}

/**
 * Remove a dynamic array's last element and give it back.
 *
 * @tparam T The element type.
 * @param array The array, one element shorter afterwards; its capacity stays. It mustn't be empty: for an empty one
 *     it calls context.assertion_handler, which ends the program.
 * @param location Where it was called, which the assertion handler reports; the caller's own by default.
 * @return The last element, now the caller's.
 */
pop :: fn[T](array: ptr[mut T[..]], location := #caller_location) -> T {
    raw :: resizable(array)
    if raw.count == 0 {
        context.assertion_handler(location, "pop from an empty array")
    }
    raw.count -= 1
    return element_address(raw, raw.count, T)^
}
