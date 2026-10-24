package runtime

import compiler from "base"
import intrinsics from "base"

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

ARRAY_MINIMUM_CAPACITY : usize : 4

// The array's fields, as ResizableArray.
resizable :: fn[T](array: ptr[mut T[..]]) -> ptr[mut ResizableArray] {
    return cast[ptr[mut ResizableArray]](cast[rawptr](array))
}

// Where element index is.
element_address :: fn[T](raw: ptr[ResizableArray], index: usize, T: type) -> ptr[mut T] {
    return cast[ptr[mut T]](raw.data + index * size_of(T))
}

/*
 * Makes room for at least new_capacity elements, keeping the ones there are. Does nothing if
 * there's room already.
 */
array_reserve :: fn[T](array: ptr[mut T[..]], new_capacity: usize, location := #caller_location) {
    raw :: resizable(array)
    if new_capacity <= raw.capacity {
        return void
    }
    if cast[rawptr](raw.allocator.function) == null {
        raw.allocator = context.allocator
    }
    allocator :: raw.allocator
    memory, error :: allocator.function(allocator.data, new_capacity * size_of(T), align_of(T), null, 0, location)
    if error != null {
        context.assertion_handler(location, "out of memory")
    }
    if raw.count > 0 {
        intrinsics.mem_copy_non_overlapping(cast[mut rawptr](memory.data), raw.data, raw.count * size_of(T))
    }
    if raw.capacity > 0 {
        allocator.function(allocator.data, 0, align_of(T), raw.data, raw.capacity * size_of(T), location)
    }
    raw.data = cast[rawptr](memory.data)
    raw.capacity = new_capacity
}

// Adds value at the end, growing the array if it's full.
array_add :: fn[T](array: ptr[mut T[..]], value #escaping : T, location := #caller_location) {
    raw :: resizable(array)
    if raw.count == raw.capacity {
        doubled :: raw.capacity * 2
        array_reserve(array, if doubled > ARRAY_MINIMUM_CAPACITY { doubled } else { ARRAY_MINIMUM_CAPACITY }, location)
    }
    element_address(raw, raw.count, T)^ = value
    raw.count += 1
}

// Adds each of source's elements at the end of target, in order.
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

// Where value first is in array, or none.
array_find :: fn[T: compiler.Equatable](array: T[], value: T) -> usize? {
    for element, index in array {
        if element == value {
            return index
        }
    }
    return null
}

// Gives the array's memory back to its allocator, leaving it empty. It keeps the allocator.
array_free :: fn[T](array: ptr[mut T[..]], location := #caller_location) {
    raw :: resizable(array)
    if raw.capacity > 0 {
        raw.allocator.function(raw.allocator.data, 0, align_of(T), raw.data, raw.capacity * size_of(T), location)
    }
    raw.data = null
    raw.count = 0
    raw.capacity = 0
}

/*
 * An array of owned values (docs/memory.md, Owned Types), given up: each element released with release,
 * then the array's memory given back.
 *
 *     runtime.array_release(files, close_file)
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

// Empties the array, keeping its memory for what's added next.
array_reset :: fn[T](array: ptr[mut T[..]]) {
    resizable(array).count = 0
}

// Removes the element at position, moving the ones after it down one, so their order is kept.
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

// Removes the element at position by moving the last element into its place: faster, but the order changes.
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

// The last element. The array mustn't be empty.
peek :: fn[T](array: T[], location := #caller_location) -> T {
    if array.count == 0 {
        context.assertion_handler(location, "peek at an empty array")
    }
    return array[array.count - 1]
}

// Removes the last element and gives it back. The array mustn't be empty.
pop :: fn[T](array: ptr[mut T[..]], location := #caller_location) -> T {
    raw :: resizable(array)
    if raw.count == 0 {
        context.assertion_handler(location, "pop from an empty array")
    }
    raw.count -= 1
    return element_address(raw, raw.count, T)^
}
