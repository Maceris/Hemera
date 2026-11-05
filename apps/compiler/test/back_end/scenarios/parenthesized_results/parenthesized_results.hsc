/*
 * Results whose types are in parentheses (docs/functions.md, Multiple Returns): an optional view alone, named, and
 * listed with another result, as (mut u8[])? is written for a variable.
 */
package parenthesized_results

import testing from "std"

/**
 * View a whole buffer, or nothing, through a result written in parentheses.
 *
 * @param buffer The buffer viewed, which the view writes into.
 * @param ok Whether to give a view.
 * @return All 4 bytes of buffer; none when ok is false.
 */
pick :: fn(buffer: ptr[mut u8[4]], ok: bool) -> ((mut u8[])?) {
    if !ok {
        return null
    }
    return view_of(&buffer[0], 4)
}

/**
 * View the end of a buffer, or nothing, through a named result written in parentheses.
 *
 * @param buffer The buffer viewed, which the view writes into.
 * @param ok Whether to give a view.
 * @return view The buffer's last 3 bytes, from index 1; none when ok is false.
 */
named :: fn(buffer: ptr[mut u8[4]], ok: bool) -> (view : (mut u8[])?) {
    if !ok {
        return null
    }
    return view_of(&buffer[1], 3)
}

/**
 * Give a count and a view, the view's type in parentheses beside it.
 *
 * @param buffer The buffer viewed.
 * @return 2, and buffer's last 2 bytes, read-only.
 */
counted :: fn(buffer: ptr[mut u8[4]]) -> (int, (u8[])?) {
    return 2, view_of(cast[ptr[u8]](&buffer[2]), 2)
}

returns_an_optional_view_alone #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    buffer : u8[4]
    testing.expect(t, pick(&buffer, false) is_none, "asked for nothing, it gives none")
    match pick(&buffer, true) {
        case Some(view) => {
            testing.expect_eq(t, view.count, 4, "the view is the whole buffer")
            if view.count > 0 {
                view[0] = 7
            }
        }
        case None => testing.fail(t, "asked for a view, it gives one")
    }
    testing.expect_eq(t, buffer[0], 7, "what's written through the view lands in the buffer")
    return .Ok
}

returns_an_optional_view_named #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    buffer : u8[4]
    testing.expect(t, named(&buffer, false) is_none, "asked for nothing, it gives none")
    match named(&buffer, true) {
        case Some(view) => {
            testing.expect_eq(t, view.count, 3, "the view is the buffer's last 3 bytes")
            if view.count > 0 {
                view[0] = 9
            }
        }
        case None => testing.fail(t, "asked for a view, it gives one")
    }
    testing.expect_eq(t, buffer[1], 9, "what's written through the view lands in the buffer, from index 1")
    return .Ok
}

returns_an_optional_view_listed #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    buffer : u8[4]
    count, rest :: counted(&buffer)
    testing.expect_eq(t, count, 2, "the result before the view is as returned")
    view :: testing.require_some(t, rest, "the view listed after it is there")?
    testing.expect_eq(t, view.count, 2, "the view is the buffer's last 2 bytes")
    return .Ok
}
