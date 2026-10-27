package returns_from_heap

import runtime from "base"

/*
 * Where a call's result points, from what the callee's body gives back (docs/memory.md, Pointers to the Stack): these
 * are given views of the caller's stack, and give back what's new on the heap, so what they give can be kept by an
 * #escaping parameter and returned, through calls that call each other too.
 */

Box :: struct {
    value : int,
}

Holder :: struct {
    box : ptr[mut Box],
}

// A new box, counted from what's in name and extra, neither of which it gives back
make :: fn(name: u8[], extra: int[]) -> ptr[mut Box] {
    box := runtime.new(Box)
    box.value = cast[int](name.count) + cast[int](extra.count)
    return box
}

keep :: fn(holder: ptr[mut Holder], box #escaping : ptr[mut Box]) {
    holder.box = box
}

// Two that call each other, both giving back what make gives
even :: fn(n: int, name: u8[]) -> ptr[mut Box] {
    if n <= 0 {
        return make(name, int.[])
    }
    return odd(n - 1, name)
}

odd :: fn(n: int, name: u8[]) -> ptr[mut Box] {
    return even(n - 1, name)
}

// A box made from a buffer on this stack, given back
from_frame :: fn() -> ptr[mut Box] {
    bytes : u8[8]
    counts : int[2]
    return make(bytes[0..<5], counts[0..<2])
}

main :: fn() -> int {
    holder := Holder.{}
    bytes : u8[8]
    keep(&holder, even(4, bytes[0..<3]))
    first :: holder.box.value
    runtime.free(holder.box)
    second :: from_frame()
    total :: first + second.value
    runtime.free(second)
    // 3 and 7
    return 32 + total
}
