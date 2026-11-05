package unwrap_member

import testing from "std"

/*
 * A member, an element and what a pointer points to, of what ? unwraps: f()?.x is (f()?).x, an error or nothing
 * returned as ? returns it, and the member of the value otherwise.
 */

Point :: struct {
    x : int,
    y : int,
}

Line :: struct {
    from : Point,
    to : Point,
}

point_of :: fn(good: bool) -> Result[Point, int] {
    if good {
        return .Ok(Point.{x = 40, y = 2})
    }
    return .Error(7)
}

maybe_line :: fn(good: bool) -> Line? {
    if good {
        return Line.{from = Point.{x = 1, y = 2}, to = Point.{x = 3, y = 4}}
    }
    return null
}

numbers :: fn(good: bool) -> Result[int[3], int] {
    if good {
        return .Ok(int.[5, 6, 7])
    }
    return .Error(9)
}

sum :: fn(good: bool) -> Result[int, int] {
    return .Ok(point_of(good)?.x + point_of(good)?.y)
}

// A chain after it: a member of a member
far_end :: fn(good: bool) -> int? {
    return maybe_line(good)?.to.y
}

second :: fn(good: bool) -> Result[int, int] {
    return .Ok(numbers(good)?[1])
}

reaches_into_what_question_mark_unwraps #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    made :: sum(true)
    total :: testing.require_ok(t, made, "with every point there, the sum is made")?
    testing.expect_eq(t, total, 42, "f()?.x and f()?.y are the point's members")
    testing.expect_error(t, sum(false), 7, "without a point, ? returns its error before the member is read")
    testing.expect_eq(t, far_end(true) or_else 0, 4, "f()?.to.y follows the chain after the unwrapped value")
    testing.expect(t, far_end(false) is_none, "without a line, ? returns nothing")
    testing.expect_eq(t, second(true) or_else 0, 6, "f()?[1] is an element of the unwrapped array")
    testing.expect_error(t, second(false), 9, "without the numbers, ? returns their error")
    return .Ok
}
