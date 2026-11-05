/*
 * Relative pointers (docs/types.md, Relative Pointers): a ring of nodes linked by relptr32, set by assigning each a
 * pointer, then copied whole to another address and walked there, where the links still lead around the copy. An
 * optional one is None at offset 0.
 */
package relative_pointers

import intrinsics from "base"
import runtime from "base"
import testing from "std"

/** A node of a ring, linked to the next by a relative pointer. */
Node :: struct {
    /** Its number, 1 to NODES around the ring. */
    value : int,
    /** The node after it; the last one's is the first. */
    next : relptr32[Node],
    /** The node before, or None for the first. */
    previous : relptr16[Node]?,
}

/** How many nodes a ring has. */
NODES :: 4
/** A ring's nodes, side by side. */
Ring :: Node[NODES]

/**
 * Walk around a ring, gathering its values.
 *
 * @param first Where to start.
 * @return The NODES values from first, following next, as one decimal number: 1234 for 1, 2, 3, 4.
 */
walk :: fn(first: ptr[Node]) -> int {
    total := 0
    at := first
    for i in 0..<NODES {
        total = total * 10 + at.value
        at = at.next
    }
    return total
}

/**
 * Make a ring on the heap, each node's next the one after and previous the one before.
 *
 * @return The ring, numbered 1 to NODES, which the caller frees with runtime.free.
 */
linked :: fn() -> ptr[mut Ring] {
    ring := runtime.new(Ring)
    for i in 0..<NODES {
        ring[i].value = i + 1
        ring[i].next = &ring[(i + 1) % NODES]
        ring[i].previous = if i == 0 { null } else { &ring[i - 1] }
    }
    return ring
}

links_a_ring #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    ring :: linked()
    defer runtime.free(ring)
    testing.expect_eq(t, walk(&ring[0]), 1234, "each next leads to the node after")
    testing.expect(t, ring[3].next == &ring[0], "the last node's next reads back as the first's address")
    // The offset is from the pointer's own address to what it points to
    offset := intrinsics.volatile_load_u32(cast[ptr[u32]](&ring[0].next))
    testing.expect_eq(t, cast[int](cast[i32](offset)), cast[int](size_of(Node)) - cast[int](offset_of(Node, next)),
        "next to the following node is a node's size on from next itself")
    return .Ok
}

leads_around_a_copy #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    ring :: linked()
    defer runtime.free(ring)
    copy := runtime.new(Ring)
    defer runtime.free(copy)
    // Copied whole, the links lead around the copy
    intrinsics.mem_copy_non_overlapping(cast[mut rawptr](copy), cast[rawptr](ring), size_of(Ring))
    testing.expect_eq(t, walk(&copy[0]), 1234, "offsets copied with their nodes lead around the copy")
    testing.expect(t, copy[1].next == &copy[2], "a copied link reads back as the copy's address, not the original's")
    testing.expect(t, ring[0].previous == null && copy[0].previous == null, "an optional relative pointer set to null is none, copied or not")
    match copy[2].previous {
        case Some(before) => testing.expect(t, before == &copy[1] && before.value == 2, "a copied optional one leads to the copy's node before")
        case None => testing.fail(t, "the third node has one before it")
    }
    // Following one through a pointer to it, and pointing it elsewhere
    link := &copy[0].next
    testing.expect_eq(t, link^.value, 2, "one read through a pointer to it leads where it does in place")
    copy[0].next = &copy[2]
    testing.expect_eq(t, walk(&copy[0]), 1341, "pointed past the second node, the walk skips it")
    return .Ok
}
