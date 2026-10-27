package unwrap_member

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

main :: fn() -> int {
    total :: sum(true) or_return 1
    if total != 42 {
        return 2
    }
    match sum(false) {
        case Ok(value) => return 3
        case Error(error) => {
            if error != 7 {
                return 4
            }
        }
    }
    if (far_end(true) or_else 0) != 4 || (far_end(false) is_some) {
        return 5
    }
    if (second(true) or_else 0) != 6 || (second(false) is_ok) {
        return 6
    }
    return total
}
