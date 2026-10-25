/*
 * Relative pointers (docs/types.md, Relative Pointers): a ring of nodes linked by relptr32, set by assigning each a
 * pointer, then copied whole to another address and walked there, where the links still lead around the copy. An
 * optional one is None at offset 0. main returns 42 if they all held, or the number of the first that didn't.
 */
package relative_pointers

import intrinsics from "base"
import runtime from "base"

Node :: struct {
    value : int,
    next : relptr32[Node],
    // The node before, or None for the first
    previous : relptr16[Node]?,
}

NODES :: 4
Ring :: Node[NODES]

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

// The values around a ring from first, NODES of them, as one number: 1234 for 1, 2, 3, 4.
walk :: fn(first: ptr[Node]) -> int {
    total := 0
    at := first
    for i in 0..<NODES {
        total = total * 10 + at.value
        at = at.next
    }
    return total
}

main :: fn() -> int {
    errors := 0
    ring := runtime.new(Ring)
    copy := runtime.new(Ring)
    for i in 0..<NODES {
        ring[i].value = i + 1
        ring[i].next = &ring[(i + 1) % NODES]
        ring[i].previous = if i == 0 { null } else { &ring[i - 1] }
    }
    errors += check(walk(&ring[0]) == 1234, 1)
    errors += check(ring[3].next == &ring[0], 2)
    // The offset is from the pointer's own address to what it points to
    offset := intrinsics.volatile_load_u32(cast[ptr[u32]](&ring[0].next))
    errors += check(cast[int](cast[i32](offset)) == cast[int](size_of(Node)) - cast[int](offset_of(Node, next)), 3)
    // Copied whole, the links lead around the copy
    intrinsics.mem_copy_non_overlapping(cast[mut rawptr](copy), cast[rawptr](ring), size_of(Ring))
    errors += check(walk(&copy[0]) == 1234, 4)
    errors += check(copy[1].next == &copy[2], 5)
    errors += check(ring[0].previous == null && copy[0].previous == null, 6)
    match copy[2].previous {
        case Some(before) => errors += check(before == &copy[1] && before.value == 2, 7)
        case None => errors += 7
    }
    // Following one through a pointer to it, and pointing it elsewhere
    link := &copy[0].next
    errors += check(link^.value == 2, 8)
    copy[0].next = &copy[2]
    errors += check(walk(&copy[0]) == 1341, 9)
    runtime.free(copy)
    runtime.free(ring)
    if errors == 0 {
        return 42
    }
    return errors
}
