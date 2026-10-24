package mutability

import compiler from "base"
import runtime from "base"

/*
 * What can be changed only when given mut (docs/types.md, Mutability): a view's elements through a mut T[], a
 * static or dynamic array's where what holds it can be changed, and a mut rawptr. main returns 42 if each
 * works as it should.
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

main :: fn() -> int {
    numbers : int[4]
    fill(numbers, 2)
    // Part of a mut view is one too
    view : mut int[] = numbers
    fill(view[2..<4], 3)
    if total(numbers) != 10 {
        return 1
    }
    storage : u8[2]
    poke(Buffer.{bytes = storage})
    if storage[0] != 7 {
        return 2
    }
    word : u32 = 0xffffffff
    zero(&word, 4)
    if word != 0 {
        return 3
    }
    list : int[..]
    defer runtime.array_free(&list)
    runtime.array_add(&list, 5)
    runtime.array_add(&list, 6)
    double_all(&list)
    // Reflection says which views can be changed through
    info :: cast[ptr[compiler.TypeInfoArray]](type_info_of(mut int[]))
    plain :: cast[ptr[compiler.TypeInfoArray]](type_info_of(int[]))
    for dimension in info.dimensions {
        if !dimension.is_mutable {
            return 4
        }
    }
    for dimension in plain.dimensions {
        if dimension.is_mutable {
            return 5
        }
    }
    // 10 + 7 + 22, then 3
    return total(numbers) + cast[int](storage[0]) + total(list) + 3
}
