package mutability

import compiler from "base"
import runtime from "base"
import testing from "std"

/*
 * What can be changed only when given mut (docs/types.md, Mutability): a view's elements through a mut T[], a
 * static or dynamic array's where what holds it can be changed, and a mut rawptr.
 */

// Writes through a mut view
fill :: fn(values: mut int[], value: int) {
    for &element in values {
        element^ = value
    }
}

// Reads a view, which a mut view can be given as
total :: fn(values: int[]) -> int {
    sum := 0
    for value in values {
        sum += value
    }
    return sum
}

Buffer :: struct {
    // Its own type says it can be written, whatever reaches the struct
    bytes : mut u8[],
}

poke :: fn(buffer: Buffer) {
    if buffer.bytes.count > 0 {
        buffer.bytes[0] = 7
    }
}

zero :: fn(target: mut rawptr, size: usize) {
    bytes :: view_of(cast[ptr[mut u8]](target), size)
    for &byte in bytes {
        byte^ = 0
    }
}

// A dynamic array's elements change through a pointer to it
double_all :: fn(values: ptr[mut int[..]]) {
    for &value in values^ {
        value^ *= 2
    }
}

writes_through_mut_views #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    numbers : int[4]
    fill(numbers, 2)
    // Part of a mut view is one too
    view : mut int[] = numbers
    fill(view[2..<4], 3)
    testing.expect_eq(t, total(numbers), 10, "2 + 2 + 3 + 3: the array through a mut view, then its last two through a part of one")
    storage : u8[2]
    poke(Buffer.{bytes = storage})
    testing.expect_eq(t, storage[0], 7, "a mut u8[] field writes through, whatever reaches the struct")
    return .Ok
}

writes_through_a_mut_rawptr #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    word : u32 = 0xffffffff
    zero(&word, 4)
    testing.expect_eq(t, word, 0, "a mut rawptr's bytes, viewed as mut u8s, were each zeroed")
    return .Ok
}

changes_a_dynamic_arrays_elements_through_a_pointer #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    list : int[..]
    defer runtime.array_free(&list)
    runtime.array_add(&list, 5)
    runtime.array_add(&list, 6)
    double_all(&list)
    testing.expect_eq(t, total(list), 22, "10 + 12: each element doubled through ptr[mut int[..]]")
    return .Ok
}

reflects_which_views_are_mutable #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    info :: cast[ptr[compiler.TypeInfoArray]](type_info_of(mut int[]))
    plain :: cast[ptr[compiler.TypeInfoArray]](type_info_of(int[]))
    testing.expect_ne(t, info.dimensions.count, 0, "a view has a dimension")
    for dimension in info.dimensions {
        testing.expect(t, dimension.is_mutable, "mut int[]'s elements can be changed through it")
    }
    for dimension in plain.dimensions {
        testing.expect(t, !dimension.is_mutable, "int[]'s can't")
    }
    return .Ok
}
