/*
 * Pointers to views whose elements can be changed (docs/types.md, Mutability): in parentheses, a type keeps its own
 * mut, so ptr[mut (mut u8[])] can change the view and its elements, and ptr[(mut u8[])] only its elements.
 */
package mut_view_pointers

import runtime from "base"
import testing from "std"

// The first element set, and the view moved on past it
advance :: fn(view: ptr[mut (mut u8[])]) {
    current := view^
    if current.count > 1 {
        current[0] = 9
        view^ = current[1..<current.count]
    }
}

// The first element set; the view stays where it is
poke :: fn(view: ptr[(mut u8[])]) {
    current := view^
    if current.count > 0 {
        current[0] = 7
    }
}

// An optional one, in parentheses too
maybe_poke :: fn(view: ptr[(mut u8[])]?) -> bool {
    match view {
        case Some(given) => {
            poke(given)
            return true
        }
        case None => return false
    }
}

changes_views_and_elements_through_pointers #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    bytes, error :: runtime.new_array(u8, 4)
    testing.require(t, error == null && bytes.count == 4, "four bytes are allocated")?
    defer runtime.free_array(bytes)
    view : mut u8[] = bytes
    advance(&view)
    poke(&view)
    testing.expect_eq(t, view.count, 3, "advance moved the view itself on by one, through ptr[mut (mut u8[])]")
    if bytes.count == 4 {
        testing.expect_eq(t, bytes[0], 9, "advance set the first element before moving on")
        testing.expect_eq(t, bytes[1], 7, "poke set an element through ptr[(mut u8[])], where the view now starts")
    }
    testing.expect(t, maybe_poke(&view), "an optional ptr[(mut u8[])] given a pointer holds it")
    testing.expect(t, !maybe_poke(null), "and given null holds none")
    return .Ok
}
