package bodies_ok

import runtime from "base"

Point :: struct {
    x : int,
    y : int,
}

Labeled :: struct {
    using Point,
    name : string,
}

Suit :: enum #backed_by(u8) {
    Clubs,
    Hearts,
}

Shape :: union {
    Circle(f32),
    Square(f32, f32),
    Empty,
}

Pair :: struct[A, B] {
    first : A,
    second : B,
}

LIMIT :: 10
GREETING :: "hello"

add :: fn(a, b: int) -> int {
    return a + b
}

two :: fn() -> (int, bool) {
    return 2, true
}

named :: fn() -> (x, y: int) {
    x = 1
    y = 2
    return x, y
}

defaults :: fn(a: int, b := 3, c : string = "c") -> int {
    return a + b
}

sum :: fn(values: int...) -> int {
    total := 0
    for value in values {
        total += value
    }
    return total
}

first :: fn[T](values: T[]) -> T {
    if values.count == 0 {
        todo()
    }
    return values[0]
}

stops :: fn() #never_returns {
    loop {
    }
}

expressions :: fn(p: ptr[mut Point], q: ptr[Point], maybe: int?, result: Result[int, string]) -> int {
    // Definitions
    a : int = 1
    b := 2
    c :: 3
    d : int : 4
    e : u8
    e = 7
    // Untyped constants take the type they're used as
    f : u16 = LIMIT
    g : f32 = 1.5
    // Arithmetic, comparisons, bit operations, shifts
    h := (a + b) * c - d / 2 % 3
    flags := a & 3 | b ~ 1
    shifted := a << 2
    compare := a < b && b >= c || !(a == d)
    // Through pointers, automatically
    p.x = q.y + p^.x
    // Calls: positional, named, defaults, varargs, results
    i := add(a, b = 2)
    j := defaults(1)
    k := defaults(1, c = "x")
    l := sum(1, 2, 3)
    m, n := two()
    _, o := two()
    // Generic calls
    numbers := int.[1, 2, 3]
    first_number := first(numbers)
    // Literals
    point := Point.{1, 2}
    named_point := Point.{y = 2}
    pair := Pair[int, string].{1, "one"}
    labeled := Labeled.{}
    labeled_x := labeled.x
    suit : Suit = .Hearts
    shape : Shape = .Square(1.0, 2.0)
    text := "text"
    count := text.count
    character := 'c'
    // Optionals and results
    value := maybe or_else 5
    has := maybe is_some
    unwrapped := result or_else 0
    // Casts
    raw := cast[rawptr](p)
    back := cast[ptr[Point]](raw)
    narrow := cast[u8](a)
    same_size := bit_cast[u64](a)
    // Builtins
    size := size_of(Point)
    alignment := align_of(int)
    kind := type_of(a)
    // Arrays and views
    fixed : int[4]
    fixed[0] = 1
    view : int[] = fixed
    part := numbers[1..<3]
    total := 0
    for number, index in numbers {
        total += number
    }
    for &slot in fixed {
        slot^ = 0
    }
    for step in 0..<LIMIT {
        total += step
    }
    with {
        counter := 0
    }
    loop {
        counter += 1
        if counter > 3 {
            break
        }
    }
    while counter < 10
    // if, match and switch
    choice := if a > b { 1 } else { 2 }
    described : string = match suit {
        case .Clubs => "clubs"
        case .Hearts => "hearts"
    }
    area : f32 = match shape {
        case Circle(radius) => radius * radius
        case Square(width, height) => width * height
        case Empty => 0.0
    }
    switch a {
        case 1, 2:
            total += 1
        case 3..=5:
            total += 2
        case _:
            total += 3
    }
    // The context, read
    level := context.log_level
    push_context quiet (log_level = .ERROR) {
        inner := quiet.log_level
    }
    defer total = 0
    nested :: fn(x: int) -> int {
        return x * 2
    }
    doubled := nested(a)
    return total + doubled
}

optional_return :: fn(maybe: int?) -> int? {
    value := maybe?
    return value + 1
}

result_return :: fn(result: Result[int, string]) -> Result[int, string] {
    value := result?
    return .Ok(value)
}

or_returns :: fn(maybe: int?) -> int {
    value := maybe or_return 0
    return value
}

ends_by_never_returning :: fn() -> int {
    stops()
}

ends_by_todo :: fn() -> int {
    todo()
}

FLAG :: true

// docs/types.md, Compile-Time Parameters: an instance for each value
buffer :: fn[count](count: usize) -> u8[count] {
    result : u8[count]
    return result
}

pass_three :: fn() -> (int, bool, string) {
    return 1, true, "three"
}

takes :: fn(a: int, b: string, c: bool) -> int {
    return a
}

takes_all :: fn(a: int, b: bool, c: string) -> int {
    return a
}

later :: fn() {
    // An #if in a body picks its branch at compile time
    #if FLAG {
        picked := 1
    }
    #else {
        picked := "not checked"
    }
    picked += 1
    // Piped values fill _ in order, or $1, $2 by number
    first := pass_three() |> takes(_, "x", _)
    second := pass_three() |> takes($1, $3, $2)
    third := pass_three() |> takes_all()
    // Compile-time values
    bytes := buffer(16)
    sixteen : u8[16] = bytes
    // break 2 leaves both loops
    for i in 0..<3 {
        for j in 0..<3 {
            if j == 1 {
                break 2
            }
        }
    }
    #assert size_of(Point) == 16
}

#assert align_of(Point) == 8
