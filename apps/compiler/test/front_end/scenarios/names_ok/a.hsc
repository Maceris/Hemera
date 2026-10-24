package names_ok

import lib from "../names_ok_lib"
import runtime from "base"

// COUNT and Item are declared in the other file
LIMIT :: COUNT * 2

// Pointing to itself is fine; Pair holds Item by value, so Item must resolve first
Node :: struct {
    next : ptr[Node],
    value : Pair[int, Item],
    items : Item[],
    // Sized by another package's constant, in any dimension
    grid : u8[lib.VALUE][2],
    rows : u8[2][lib.VALUE],
}

Pair :: struct[A, B] {
    first : A,
    second : B,
}

use :: fn[T](value: T, current: runtime.Context) -> lib.Status {
    return value
}
