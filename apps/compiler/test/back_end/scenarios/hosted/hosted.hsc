/*
 * A hosted program for the back end's test: main returns 42 if everything worked, or the number
 * of the first check that failed.
 */
package hosted

Point :: struct {
    x : int,
    y : int,
}

Labeled :: struct {
    using Point,
    weight : int,
}

Shape :: union {
    Circle(int),
    Rectangle(int, int),
    Empty,
}

Color :: enum {
    Red,
    Green,
    Blue,
}

ORIGIN : Point : Point.{10, 20}
LIMIT :: 4

area :: fn(shape: Shape) -> int {
    return match shape {
        case Circle(radius) => 3 * radius * radius
        case Rectangle(width, height) => width * height
        case Empty => 0
    }
}

sum_to :: fn(limit: int) -> int {
    total := 0
    for i in 0..<limit {
        total += i
    }
    return total
}

// Deferred statements run when the scope is left, last first
bump :: fn(value: ptr[mut int]) {
    defer value^ += 10
    value^ += 1
}

order :: fn() -> int {
    result := 0
    {
        defer result = result * 10 + 1
        defer result = result * 10 + 2
    }
    return result
}

count_odd :: fn(limit: int) -> int {
    count := 0
    with {
        i := 0
    }
    loop {
        i += 1
        if i % 2 == 0 {
            continue
        }
        count += 1
    }
    while i < limit
    return count
}

classify :: fn(n: int) -> int {
    result := 0
    switch n {
        case 1, 2:
            result = 10
        case 3..=5:
            result = 20
        case _:
            result = 30
    }
    return result
}

two :: fn() -> (int, bool) {
    return 7, true
}

sum :: fn(values: int...) -> int {
    total := 0
    for value in values {
        total += value
    }
    return total
}

first :: fn[T](values: T[]) -> T {
    return values[0]
}

half :: fn(n: int) -> int? {
    if n % 2 != 0 {
        return null
    }
    return n / 2
}

quarter :: fn(n: int) -> int? {
    h := half(n)?
    return half(h)
}

double :: fn(n: int) -> int {
    return n * 2
}

// Each else belongs to the if before it
grade :: fn(n: int) -> int {
    if n > 90 {
        return 4
    }
    else if n > 80 {
        return 3
    }
    else if n > 70 {
        return 2
    }
    else {
        return 1
    }
}

sign :: fn(n: int) -> int {
    return if n > 0 { 1 } else if n < 0 { -1 } else { 0 }
}

// A varargs view passed on, with a value after it for the next parameter
count_with :: fn(values: int..., extra: int) -> int {
    return cast[int](values.count) + extra
}

forward :: fn(values: int...) -> int {
    return count_with(values, 10)
}

move :: fn(p: ptr[mut Point], by: int) {
    p.x += by
    p.y -= by
}

main :: fn() -> int {
    p := Point.{3, 4}
    shapes := Shape.[.Circle(2), .Rectangle(p.x, p.y), .Empty]
    total := 0
    for shape in shapes {
        total += area(shape)
    }
    if total != 24 {
        return 1
    }
    if sum_to(5) != 10 {
        return 2
    }
    n := 0
    bump(&n)
    if n != 11 {
        return 3
    }
    if order() != 21 {
        return 4
    }
    if count_odd(10) != 5 {
        return 5
    }
    if classify(4) + classify(1) + classify(9) != 60 {
        return 6
    }
    c : Color = .Blue
    color_value := match c {
        case .Red => 1
        case .Green => 2
        case .Blue => 3
    }
    if color_value != 3 {
        return 7
    }
    if 10 - 3 - 2 != 5 || 100 / 10 / 5 != 2 {
        return 8
    }
    a, b := two()
    if a != 7 || !b {
        return 9
    }
    if sum(1, 2, 3, LIMIT) != 10 {
        return 10
    }
    numbers := int.[5, 6, 7]
    if first(numbers) != 5 {
        return 11
    }
    if (quarter(8) or_else 0) != 2 || (quarter(6) or_else 99) != 99 {
        return 12
    }
    labeled := Labeled.{Point.{1, 2}, 3}
    if labeled.x + labeled.y + labeled.weight != 6 {
        return 13
    }
    moved := ORIGIN
    move(&moved, 5)
    if moved.x != 15 || moved.y != 15 {
        return 14
    }
    hits := 0
    for i in 0..<5 {
        for j in 0..<5 {
            if j == 2 {
                break
            }
            if i == 3 {
                break 2
            }
            hits += 1
        }
    }
    if hits != 6 {
        return 15
    }
    fixed : int[3]
    for &slot, index in fixed {
        slot^ = cast[int](index) * 10
    }
    if fixed[2] != 20 {
        return 16
    }
    deferred := 0
    for i in 0..<4 {
        defer deferred += 1
        if i == 1 {
            continue
        }
    }
    if deferred != 4 {
        return 17
    }
    text := "hello"
    if text.count != 5 {
        return 18
    }
    f := double
    if f(4) |> double() != 16 {
        return 19
    }
    shift : u8 = 1
    shift <<= 3
    if shift != 8 || -7 %% 3 != 2 || -7 % 3 != -1 {
        return 20
    }
    choice := if a > 5 { 1 } else { 2 }
    if choice != 1 {
        return 21
    }
    if grade(95) != 4 || grade(85) != 3 || grade(75) != 2 || grade(5) != 1 {
        return 22
    }
    if sign(5) != 1 || sign(-5) != -1 || sign(0) != 0 {
        return 23
    }
    _ = double(3)
    if forward(1, 2, 3) != 13 {
        return 24
    }
    return 42
}
