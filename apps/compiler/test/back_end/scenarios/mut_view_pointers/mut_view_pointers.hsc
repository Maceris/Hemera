/*
 * Pointers to views whose elements can be changed (docs/types.md, Mutability): in parentheses, a type keeps its own
 * mut, so ptr[mut (mut u8[])] can change the view and its elements, and ptr[(mut u8[])] only its elements. main
 * returns 42 if they all held, or the number of the first that didn't.
 */
package mut_view_pointers

import runtime from "base"

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

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

main :: fn() -> int {
    errors := 0
    bytes, error :: runtime.new_array(u8, 4)
    if error != null || bytes.count != 4 {
        return 99
    }
    view : mut u8[] = bytes
    advance(&view)
    poke(&view)
    errors += check(view.count == 3 && bytes[0] == 9 && bytes[1] == 7, 1)
    errors += check(maybe_poke(&view) && !maybe_poke(null), 2)
    runtime.free_array(bytes)
    if errors == 0 {
        return 42
    }
    return errors
}
