/*
 * == and != on fixed arrays, structs and tagged unions (docs/types.md, Equality): element by element, member by member,
 * and by variant and its values. main returns 42 if they all held, or the number of the first that didn't.
 */
package equality

Guid :: u8[16]

Point :: struct {
    x : f64,
    y : f64,
}

// A byte, then padding, then a u64: the padding isn't compared
Padded :: struct {
    small : u8,
    large : u64,
    last : u16,
}

Shape :: union {
    Circle(f64),
    Rectangle(Point, Point),
    Nothing,
}

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

guid :: fn(byte: u8) -> Guid {
    made : Guid
    for &each in made {
        each^ = byte
    }
    return made
}

padded :: fn(small: u8, large: u64, last: u16, junk: u8) -> Padded {
    made : Padded
    // Junk in the padding, which == doesn't look at
    bytes :: cast[ptr[mut u8]](&made)
    for i in 0..<size_of(Padded) {
        cast[ptr[mut u8]](cast[u64](bytes) + cast[u64](i))^ = junk
    }
    made.small = small
    made.large = large
    made.last = last
    return made
}

main :: fn() -> int {
    errors := 0
    errors += check(guid(1) == guid(1) && guid(1) != guid(2), 1)
    a := guid(3)
    a[15] = 4
    errors += check(a != guid(3), 2)
    one :: Point.{1, 2}
    also_one :: Point.{1, 2}
    two :: Point.{2, 1}
    errors += check(one == also_one && one != two, 3)
    points :: Point.[Point.{1, 2}, Point.{3, 4}]
    others :: Point.[Point.{1, 2}, Point.{3, 5}]
    errors += check(points == points && points != others, 4)
    errors += check(padded(1, 2, 3, 0) == padded(1, 2, 3, 0xff), 5)
    errors += check(padded(1, 2, 3, 0) != padded(1, 2, 4, 0), 6)
    circle : Shape = .Circle(1.5)
    same : Shape = .Circle(1.5)
    bigger : Shape = .Circle(2.5)
    box : Shape = .Rectangle(Point.{0, 0}, Point.{1, 1})
    nothing : Shape = .Nothing
    errors += check(circle == same && circle != bigger && circle != box && box == box && nothing == nothing && nothing != circle, 7)
    // A typed literal on the left of an operator
    errors += check(Point.{1, 2} == one && Point.{1, 2} != Point.{2, 1}, 8)
    if errors == 0 {
        return 42
    }
    return errors
}
