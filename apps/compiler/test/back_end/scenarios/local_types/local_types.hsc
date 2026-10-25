/*
 * Types declared inside a function (docs/types.md, Types Declared in Functions): a struct, enum, union or alias seen by
 * what comes after it in its block, the types and functions declared there among them, and not outside it. main returns
 * 42 if they all held, or the number of the first that didn't.
 */
package local_types

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

// A package-level Point, which the local ones below hide where they're seen
Point :: struct {
    name : string,
}

measured :: fn() -> int {
    Point :: struct {
        x : int,
        y : int,
    }
    // A local type made of another
    Line :: struct {
        from : Point,
        to : Point,
    }
    Direction :: enum {
        Across,
        Up,
    }
    Shape :: union {
        Dot(Point),
        Segment(Line),
    }
    Length :: alias int

    // A function declared after them sees them too
    span :: fn(line: Line, direction: Direction) -> Length {
        return if direction == .Across { line.to.x - line.from.x } else { line.to.y - line.from.y }
    }

    line := Line.{from = Point.{x = 1, y = 2}, to = Point.{x = 6, y = 9}}
    shape := Shape.Segment(line)
    total : Length = 0
    match shape {
        case Segment(given) => total = span(given, .Across) * 10 + span(given, .Up)
        case Dot(_) => total = -1
    }
    return total
}

// The same name in two functions, two types
other :: fn() -> int {
    Point :: struct {
        z : u8,
    }
    p := Point.{z = 3}
    return cast[int](size_of(Point)) + cast[int](p.z)
}

// A block's type is its own: outside it, the package's is seen again
blocks :: fn() -> bool {
    if true {
        Point :: struct {
            x : f64,
        }
        inner := Point.{x = 0.5}
        if inner.x != 0.5 {
            return false
        }
    }
    outer := Point.{name = "package"}
    return outer.name == "package"
}

// In a generic function, each instance's types are its own, made with its parameters
boxed :: fn[T, count: usize](value: T) -> usize {
    Box :: struct {
        items : T[count],
    }
    box : Box
    for i in 0..<count {
        box.items[i] = value
    }
    return size_of(Box)
}

main :: fn() -> int {
    errors := 0
    errors += check(measured() == 57, 1)
    errors += check(other() == 4, 2)
    errors += check(blocks(), 3)
    errors += check(boxed[u8, 3](7) == 3 && boxed[u64, 2](7) == 16, 4)
    if errors == 0 {
        return 42
    }
    return errors
}
