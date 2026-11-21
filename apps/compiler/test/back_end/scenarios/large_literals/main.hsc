package main

import runtime from "base:runtime"

/** A struct larger than a selection DAG node's operands: 65,536 bytes and more around them. */
Big :: struct {
    count : usize,
    bytes : u8[65536],
    flag : bool,
}

Holder :: struct {
    bigs : Big[2],
}

/** A literal assigned through a pointer into an element, which is stored a part at a time. */
fill :: fn(holder : ptr[mut Holder], index : usize, count : usize) {
    holder.bigs[index % 2] = Big.{count = count, flag = true}
}

/** Built unoptimized as well as optimized: 42 if the literal's parts landed, and what it didn't name is zero. */
main :: fn() -> int {
    holder :: runtime.new(Holder)
    holder.bigs[1].bytes[100] = 9
    fill(holder, 1, 40)
    zeroed := holder.bigs[1].bytes[100] == 0
    flagged := holder.bigs[1].flag
    return cast[int](holder.bigs[1].count) + (if zeroed { 1 } else { 0 }) + (if flagged { 1 } else { 0 })
}
