/*
 * A hosted program for the back end's test: main returns 42 if everything worked, or the number
 * of the first check that failed.
 */
package hosted

import compiler from "base"
import intrinsics from "base"
import text_buffer from "std"

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

// A file's bytes, from next to this one
WORD :: #file_data("word.txt")

// A table of integer constants, generated as one constant
PRIMES : u8[5] : u8.[2, 3, 5, 7, 11]

sum_bytes :: fn(values: u8[]) -> int {
    total := 0
    for value in values {
        total += cast[int](value)
    }
    return total
}

// How many frames are above this one: at least main's caller
frames_above :: fn() -> usize {
    addresses : rawptr[8]
    return intrinsics.capture_stack_trace(addresses)
}

// A variant can hold any type, like a pointer or a function
Event :: union {
    Counter(ptr[mut int]),
    Callback(fn(n: int) -> int),
    Quiet,
}

POINTS :: Point.[.{1, 2}, .{3, 4}]

// A variant without values, named through its union, as an optional
quiet :: fn() -> Event? {
    return Event.Quiet
}

stop :: fn() -> int #never_returns {
    loop {
    }
}

value_or_stop :: fn(value: int?) -> int {
    return value or_else stop()
}

larger :: fn(a, b: int) -> int {
    return if a > b { a } else { b }
}

// A value for an optional parameter
described :: fn(where: Point?) -> int {
    return match where {
        case Some(point) => point.x
        case None => -1
    }
}

DIGITS :: "0123456789"

// Big enough to be copied with memmove
Big :: struct {
    values : int[32],
}

// Any word is a member's name (docs/keywords.md)
Origin :: struct {
    package : string,
    match : int,
}

Direction :: enum {
    in,
    else,
}

// The contextual keywords are names outside the constructs they start
total_of :: fn(from: int, in: int, all: int, alias: int) -> int {
    return from + in + all + alias
}

// An optional pointer is just the pointer, null when there's none (docs/types.md, Optional Types)
Link :: struct {
    next : ptr[Link]?,
    value : int,
}

#assert size_of(ptr[int]?) == 8
#assert size_of(Link) == 16

chain_total :: fn(first: ptr[Link]) -> int {
    total := 0
    current : ptr[Link]? = first
    loop {
        link :: current or_break
        total += link.value
        current = link.next
    }
    return total
}

twice :: fn(n: int) -> int {
    return n * 2
}

Transform :: alias fn(n: int) -> int

apply :: fn(function: Transform?, n: int) -> int {
    return match function {
        case Some(f) => f(n)
        case None => n
    }
}

// A result with nothing on success (docs/operators.md, Result Operators)
Fault :: enum {
    Busy,
}

attempt :: fn(fail: bool) -> Result[void, Fault] {
    if fail {
        return .Error(.Busy)
    }
    return .Ok
}

attempt_twice :: fn(fail: bool) -> Result[void, Fault] {
    attempt(false)?
    attempt(fail)?
    return .Ok
}

successes :: fn() -> int {
    count := 0
    for i in 0..<5 {
        attempt(i % 2 == 0) or_continue
        count += 1
    }
    return count
}

count_up :: fn(counter: ptr[mut int]) {
    counter^ += 1
}

move :: fn(p: ptr[mut Point], by: int) {
    p.x += by
    p.y -= by
}

// What a value formats as, through its any's type information.
formatted :: fn(format: string, values: any...) -> string {
    storage : u8[128]
    text := text_buffer.make(storage)
    text_buffer.append_format(&text, format, values)
    return text_buffer.as_string(&text)
}

// The type information an any carries.
info_of :: fn(value: any) -> ptr[compiler.TypeInfo] {
    return type_info_of(value.type)
}

// A frame bigger than a page, which Windows code probes a page at a time with __chkstk.
big_frame :: fn() -> u8 {
    buffer : u8[16384]
    buffer[0] = 1
    buffer[16383] = 2
    return buffer[0] + buffer[16383]
}

// Two results, for definitions that drop one with _.
two_results :: fn() -> (u32, bool) {
    return 3, true
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
    // A view of an array refers to it, so changes through the view reach it
    numbers_to_change : int[3]
    view : int[] = numbers_to_change
    view[1] = 5
    if numbers_to_change[1] != 5 {
        return 25
    }
    if sum_bytes(PRIMES) != 28 {
        return 26
    }
    if frames_above() == 0 {
        return 27
    }
    word : u8[] = WORD
    if word.count != 6 || word[0] != 0x48 || WORD[5] != 0x41 {
        return 28
    }
    counted := 1
    event : Event = .Counter(&counted)
    match event {
        case Counter(target) => target^ += 1
        case _ => {}
    }
    if counted != 2 {
        return 29
    }
    if POINTS[1].y != 4 {
        return 30
    }
    is_quiet := false
    match quiet() {
        case Some(found) => is_quiet = true
        case None => {}
    }
    if !is_quiet || value_or_stop(7) != 7 {
        return 31
    }
    if larger(if counted > 1 { 10 } else { 0 }, 5) != 10 {
        return 32
    }
    if described(Point.{8, 9}) != 8 {
        return 33
    }
    greeting := "hello world"
    if greeting[0..<5] != "hello" || greeting == "hello" || DIGITS[3] != '3' {
        return 34
    }
    big : Big
    big.values[31] = 5
    copy := big
    big.values[31] = 6
    if copy.values[31] != 5 {
        return 35
    }
    origin := Origin.{package = "hosted", match = 2}
    direction : Direction = .else
    if origin.match != 2 || origin.package.count != 6 || direction != Direction.else || total_of(1, 2, 3, 4) != 10 {
        return 36
    }
    last := Link.{null, 3}
    first := Link.{&last, 4}
    none : ptr[Link]? = null
    // None is a null pointer in memory
    if chain_total(&first) != 7 || (none is_some) || (first.next is_none) || cast[ptr[u64]](&last)^ != 0 {
        return 37
    }
    if apply(twice, 5) != 10 || apply(null, 5) != 5 {
        return 38
    }
    failed_twice := match attempt_twice(true) {
        case Ok => false
        case Error(fault) => true
    }
    failures := 0
    attempt(true) or_else count_up(&failures)
    attempt(false) or_else count_up(&failures)
    if !failed_twice || successes() != 2 || failures != 1 {
        return 39
    }
    // Type information: an any's type, type values, and descriptors
    color_info :: cast[ptr[compiler.TypeInfoEnum]](info_of(Color.Blue))
    if color_info.variant != .ENUM || color_info.name != "Color" || color_info.members[2] != "Blue" || color_info.values[2] != 2 {
        return 40
    }
    labeled_info :: cast[ptr[compiler.TypeInfoStruct]](type_info_of(Labeled))
    if labeled_info.members.count != 2 || !labeled_info.members[0].is_using || labeled_info.members[1].offset != 16 {
        return 41
    }
    some_number : any = 5
    if some_number.type != int || some_number.type == i64 || type_of(origin) != Origin {
        return 43
    }
    shape_text :: formatted("% %", Shape.Rectangle(2, 3), first.next)
    if formatted("%2 %1 %%", Color.Green, true) != "true Green %" || shape_text.count < 16 {
        return 44
    }
    if formatted("%", Point.{1, -2}) != "Point{x = 1, y = -2}" || formatted("% %", ptr[mut Point], none) != "ptr[mut Point] none" {
        return 45
    }
    _, second :: two_results()
    first, _ := two_results()
    if !second || first != 3 {
        return 46
    }
    if big_frame() != 3 {
        return 47
    }
    return 42
}
