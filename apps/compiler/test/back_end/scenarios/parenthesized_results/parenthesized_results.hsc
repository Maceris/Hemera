/*
 * Results whose types are in parentheses (docs/functions.md, Multiple Returns): an optional view alone, named, and
 * listed with another result, as (mut u8[])? is written for a variable. main returns 42 if each gave what it should,
 * or the number of the first check that didn't.
 */
package parenthesized_results

// The buffer's view, or nothing.
pick :: fn(buffer: ptr[mut u8[4]], ok: bool) -> ((mut u8[])?) {
    if !ok {
        return null
    }
    return view_of(&buffer[0], 4)
}

named :: fn(buffer: ptr[mut u8[4]], ok: bool) -> (view : (mut u8[])?) {
    if !ok {
        return null
    }
    return view_of(&buffer[1], 3)
}

counted :: fn(buffer: ptr[mut u8[4]]) -> (int, (u8[])?) {
    return 2, view_of(cast[ptr[u8]](&buffer[2]), 2)
}

main :: fn() -> int {
    buffer : u8[4]
    if pick(&buffer, false) is_some {
        return 1
    }
    match pick(&buffer, true) {
        case Some(view) => {
            if view.count != 4 {
                return 2
            }
            view[0] = 7
        }
        case None => return 3
    }
    if buffer[0] != 7 {
        return 4
    }
    if named(&buffer, false) is_some {
        return 5
    }
    match named(&buffer, true) {
        case Some(view) => {
            if view.count != 3 {
                return 6
            }
            view[0] = 9
        }
        case None => return 7
    }
    if buffer[1] != 9 {
        return 8
    }
    count, rest :: counted(&buffer)
    match rest {
        case Some(view) => {
            if count != 2 || view.count != 2 {
                return 9
            }
        }
        case None => return 10
    }
    return 42
}
