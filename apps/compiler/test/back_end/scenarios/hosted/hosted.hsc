/*
 * A hosted program for the back end's test, of the language's everyday forms: main runs the
 * package's tests, reporting to standard output, and returns 42 if they all passed.
 */
package hosted

import compiler from "base"
import intrinsics from "base"
import runtime from "base"
import concurrency from "std"
import memory from "std"
import testing from "std"
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
    runtime.assert(values.count > 0, "first takes at least one value")
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

// A varargs view passed on, with a value after it for the next parameter, of a type an int can't be taken for
count_with :: fn(values: int..., extra: string) -> int {
    return cast[int](values.count) + cast[int](extra.count)
}

forward :: fn(values: int...) -> int {
    return count_with(values, "ten characters")
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
// #scoped, since the test chains links on the stack (docs/memory.md, Scoped Structs)
Link :: struct #scoped {
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

lookup_size :: fn(fail: bool) -> Result[int?, Fault] {
    if fail {
        return .Error(.Busy)
    }
    return .Ok(7)
}

// A result unwrapped where it's matched on
sized :: fn(fail: bool) -> Result[int, Fault] {
    match lookup_size(fail)? {
        case Some(size) => return .Ok(size)
        case None => return .Ok(0)
    }
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

// What a value formats as, through its any's type information, in storage the caller gives.
formatted :: fn(storage: mut u8[], format: string, values: any...) -> string {
    if storage.count == 0 {
        return ""
    }
    text := text_buffer.make(storage)
    text_buffer.append_format(&text, format, values)
    // A view of the caller's storage; the text buffer itself is on this stack
    return string_of(&storage[0], text.count)
}

// The type information an any carries.
info_of :: fn(value: any) -> ptr[compiler.TypeInfo] {
    return type_info_of(value.type)
}

// Compile-time execution: constants whose values call functions, and #run, worked out while compiling.
SQUARE_TABLE :: int.[1, 4, 9, 16]

fibonacci :: fn(n: int) -> int {
    if n < 2 {
        return n
    }
    return fibonacci(n - 1) + fibonacci(n - 2)
}

squares :: fn() -> int[] {
    return SQUARE_TABLE
}

labeled_point :: fn(weight: int) -> Labeled {
    return Labeled.{Point.{weight, weight * 2}, weight * 3}
}

compile_time_name :: fn() -> string {
    if #is_compile_time {
        return "compiling"
    }
    return "running"
}

FIBONACCI_20 :: fibonacci(20)
// Reflection: a package this file imports, as compile-time code sees it
reflected_parameters :: fn() -> int {
    info :: compiler.package_info("text_buffer") or_else compiler.PackageInfo.{}
    format :: compiler.find_function(&info, "append_format") or_else compiler.FunctionInfo.{}
    digits :: compiler.find_constant(&info, "DIGITS") or_else compiler.ConstantInfo.{}
    if info.name != "text_buffer" || digits.type != string || !format.has_body || (compiler.package_info("missing") is_some) {
        return -1
    }
    // Its own type: a function's, with the same parameters
    signature :: type_info_of(format.type)
    if signature.variant != .FUNCTION || cast[ptr[compiler.TypeInfoFunction]](signature).input.count != format.parameters.count {
        return -1
    }
    // An import's from is the literal's text, without its quotes
    for &edge in info.imports {
        if edge.alias == "runtime" && edge.from != "base" {
            return -1
        }
    }
    return cast[int](format.parameters.count)
}

REFLECTED_PARAMETERS :: reflected_parameters()

/*
 * A package's constants, worked out together: one holding functions, like a logger, has no value, without
 * keeping the others from theirs.
 */
reflected_constants :: fn() -> bool {
    info :: compiler.package_info("runtime") or_else compiler.PackageInfo.{}
    segment :: compiler.find_constant(&info, "STACK_SEGMENT_SIZE") or_else compiler.ConstantInfo.{}
    logger :: compiler.find_constant(&info, "STANDARD_LOGGER") or_else compiler.ConstantInfo.{}
    // What a body discards with _ =: schema_reach's first is a usize, at its line
    reach :: compiler.find_function(&info, "schema_reach") or_else compiler.FunctionInfo.{}
    discarded :: reach.discards.count > 0 && reach.discards[0].type == usize && reach.discards[0].location.line > reach.location.line
    return segment.value.type == int && segment.value.data != null && logger.name == "STANDARD_LOGGER"
        && logger.value.data == null && discarded
}

REFLECTED_CONSTANTS :: reflected_constants()

// Compile-time code gets memory from its context, and can log
SQUARES_SUM :: sum_of_squares(6)

sum_of_squares :: fn(count: int) -> int {
    runtime.log_info("adding up % squares", count)
    memory, error :: context.allocator.function(context.allocator.data, cast[usize](count) * 8, 8, null, 0, #caller_location)
    if (error is_some) || memory.count == 0 {
        return -1
    }
    squares :: view_of(cast[ptr[mut int]](cast[rawptr](&memory[0])), cast[usize](count))
    for index in 0..<count {
        squares[index] = index * index
    }
    total := 0
    for square in squares {
        total += square
    }
    return total
}
// Run while checking, since checking needs them: an array's count, an #if and an #assert
FIBONACCI_7 :: fibonacci(7)
LARGE :: fibonacci(7) > 10
#assert FIBONACCI_7 == 13
#assert fibonacci(6) == 8 && #run fibonacci(5) == 5

#if LARGE {
    size_name :: fn() -> string {
        return "large"
    }
}
#else {
    size_name :: fn() -> string {
        return "small"
    }
}
SQUARES :: squares()
LABELED :: labeled_point(5)
WHEN :: compile_time_name()

// Tables of thousands of numbers worked out while compiling, which the program holds as one constant each.
WORD_TABLE :: #run word_table()
HALF_TABLE :: #run half_table()
RAMP :: ramp()

word_table :: fn() -> u64[4096] {
    table : u64[4096]
    for i in 0..<4096 {
        table[i] = cast[u64](i) * 0x1_0000_0001 + 7
    }
    return table
}

half_table :: fn() -> f32[3000] {
    table : f32[3000]
    for i in 0..<3000 {
        table[i] = cast[f32](i) * 0.5
    }
    return table
}

// A view, whose elements the constant points to
RAMP_VALUES :: u16.[3, 1, 4, 1, 5, 9, 2, 6]

ramp :: fn() -> u16[] {
    return RAMP_VALUES
}

tables_hold :: fn() -> bool {
    for i in 0..<4096 {
        if WORD_TABLE[i] != cast[u64](i) * 0x1_0000_0001 + 7 {
            return false
        }
    }
    for i in 0..<3000 {
        if HALF_TABLE[i] != cast[f32](i) * 0.5 {
            return false
        }
    }
    // A copy of a whole table, which comes from a constant kept in the program
    copy := WORD_TABLE
    if copy[0] != 7 || copy[4095] != 4095 * 0x1_0000_0001 + 7 {
        return false
    }
    ramp := RAMP
    return ramp.count == 8 && ramp[5] == 9 && ramp[7] == 6
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

// Values in generic lists (docs/types.md, Values in Generic Lists)
Ring :: struct[T, capacity: usize] {
    items : T[capacity],
    head : usize,
}

push :: fn[T, capacity: usize](ring: ptr[mut Ring[T, capacity]], item: T) {
    if ring.head < capacity {
        ring.items[ring.head] = item
        ring.head += 1
    }
}

// A value only given explicitly, sizing a local and the result
filled :: fn[count: usize](value: u8) -> u8[count] {
    result : u8[count]
    for i in 0..<count {
        result[i] = value
    }
    return result
}

verbosity :: fn[verbose: bool]() -> int {
    #if verbose {
        return 2
    }
    #else {
        return 1
    }
}

// One argument after a generic type is its argument, not an array's count; sizes can be arithmetic
Bits :: struct[size: usize] {
    words : u64[(size + 63) / 64],
}

RING_SIZE :: 2

// Fields with defaults, which literals and declarations start with (docs/types.md, Structs)
Defaults :: struct {
    width : uint = 10,
    height : uint = WIDE / 2,
    shown : bool = true,
    color : Color = .Blue,
    plain : int,
}

WIDE :: 40

// Constants of a union with values, built without memory
PICKED : Shape : .Rectangle(3, 4)
ROUND : Shape : .Circle(5)

Framed :: struct {
    inner : Defaults,
    border : u8 = 3,
}

// Parameter defaults: an enum member, a union variant without values, and a struct with its defaults
painted :: fn(color: Color = .Green, shape: Shape = .Empty, frame: Defaults = Defaults.{}) -> int {
    return cast[int](color) * 1000 + area(shape) * 100 + cast[int](frame.width)
}

// Defaults that are expressions: run in the caller, checked with this function
scaled :: fn(value: int, factor: int = LIMIT * 2 + 1, offset: int = sum_to(LIMIT)) -> int {
    return value * factor + offset
}

matches_unions_and_enums #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    p := Point.{3, 4}
    shapes := Shape.[.Circle(2), .Rectangle(p.x, p.y), .Empty]
    total := 0
    for shape in shapes {
        total += area(shape)
    }
    testing.expect_eq(t, total, 24, "12 for the circle, 12 for the rectangle, 0 for Empty")
    c : Color = .Blue
    color_value := match c {
        case .Red => 1
        case .Green => 2
        case .Blue => 3
    }
    testing.expect_eq(t, color_value, 3, "a match on an enum takes Blue's arm")
    testing.expect_eq(t, area(PICKED), 12, "a constant union with values, built without memory: a 3 by 4 rectangle")
    testing.expect_eq(t, area(ROUND), 75, "and a circle of radius 5")
    return .Ok
}

loops_and_breaks #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, sum_to(5), 10, "0 + 1 + 2 + 3 + 4")
    testing.expect_eq(t, count_odd(10), 5, "a loop with a with block and a while after it, continuing past evens")
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
    testing.expect_eq(t, hits, 6, "two inner rounds for each of three outer ones, before break 2 leaves both")
    fixed : int[3]
    for &slot, index in fixed {
        slot^ = cast[int](index) * 10
    }
    testing.expect_eq(t, fixed[2], 20, "a loop over pointers to elements writes them")
    return .Ok
}

runs_deferred_statements #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    n := 0
    bump(&n)
    testing.expect_eq(t, n, 11, "the deferred += 10 runs after the += 1, as bump returns")
    testing.expect_eq(t, order(), 21, "deferred statements run last first: 2, then 1")
    deferred := 0
    for i in 0..<4 {
        defer deferred += 1
        if i == 1 {
            continue
        }
    }
    testing.expect_eq(t, deferred, 4, "a loop body's defer runs each round, continue or not")
    return .Ok
}

branches #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, classify(4) + classify(1) + classify(9), 60, "a switch's range, list and default cases: 20 + 10 + 30")
    a, b := two()
    choice := if a > 5 { 1 } else { 2 }
    testing.expect_eq(t, choice, 1, "an if expression takes its first branch for 7")
    testing.expect_eq(t, grade(95), 4, "each else belongs to the if before it: over 90")
    testing.expect_eq(t, grade(85), 3, "over 80")
    testing.expect_eq(t, grade(75), 2, "over 70")
    testing.expect_eq(t, grade(5), 1, "the last else")
    testing.expect_eq(t, sign(5), 1, "an if expression with else if: positive")
    testing.expect_eq(t, sign(-5), -1, "negative")
    testing.expect_eq(t, sign(0), 0, "zero")
    return .Ok
}

works_out_operators #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, 10 - 3 - 2, 5, "- is left associative")
    testing.expect_eq(t, 100 / 10 / 5, 2, "/ is left associative")
    f := double
    testing.expect_eq(t, f(4) |> double(), 16, "a function value's result piped to another call")
    shift : u8 = 1
    shift <<= 3
    testing.expect_eq(t, shift, 8, "<<= shifts in place")
    testing.expect_eq(t, -7 %% 3, 2, "%% takes the divisor's sign")
    testing.expect_eq(t, -7 % 3, -1, "% takes the dividend's sign")
    _ = double(3)
    return .Ok
}

gives_several_results_and_takes_varargs #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a, b := two()
    testing.expect_eq(t, a, 7, "the first of two results")
    testing.expect(t, b, "the second")
    testing.expect_eq(t, sum(1, 2, 3, LIMIT), 10, "varargs, a constant among them")
    testing.expect_eq(t, forward(1, 2, 3), 17, "a varargs view passed on whole, then a string: 3 values and 14 characters")
    _, second :: two_results()
    first, _ := two_results()
    testing.expect(t, second, "_ drops the first result, and the second is kept")
    testing.expect_eq(t, first, 3, "_ drops the second result, and the first is kept")
    return .Ok
}

instantiates_generics #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    numbers := int.[5, 6, 7]
    testing.expect_eq(t, first(numbers), 5, "a generic function given an int view")
    ring : Ring[u8, RING_SIZE * 1]
    push[u8, 2](&ring, cast[u8](1))
    push(&ring, cast[u8](2))
    push(&ring, cast[u8](3))
    testing.expect_eq(t, ring.head, 2, "a ring of capacity 2 refuses the third push")
    testing.expect_eq(t, ring.items[1], 2, "the second push, with its arguments inferred, is kept")
    testing.expect_eq(t, size_of(Ring[u8, 2]), 16, "two u8s and a usize, aligned")
    nines :: filled[4](cast[u8](9))
    bits : Bits[130]
    testing.expect_eq(t, nines.count, 4, "a value given only explicitly sizes the result")
    testing.expect_eq(t, nines[3], 9, "and the local it was filled in")
    testing.expect_eq(t, verbosity[true](), 2, "a bool value picks an #if branch")
    testing.expect_eq(t, verbosity[false](), 1, "and the other")
    testing.expect_eq(t, bits.words.count, 3, "(130 + 63) / 64 words, arithmetic in a generic type's argument")
    return .Ok
}

unwraps_optionals #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, quarter(8) or_else 0, 2, "8 halves twice")
    testing.expect_eq(t, quarter(6) or_else 99, 99, "6 halves to 3, which ? passes on as none")
    is_quiet := false
    match quiet() {
        case Some(found) => is_quiet = true
        case None => {}
    }
    testing.expect(t, is_quiet, "a variant without values, as an optional, is some")
    testing.expect_eq(t, value_or_stop(7), 7, "or_else with a #never_returns call isn't taken for a value")
    testing.expect_eq(t, described(Point.{8, 9}), 8, "a struct given for an optional parameter")
    testing.expect_eq(t, apply(twice, 5), 10, "an optional function value given a function")
    testing.expect_eq(t, apply(null, 5), 5, "and given null")
    // A match's values are copies: changing what was matched doesn't change them
    held : int? = 5
    match held {
        case Some(value) => {
            held = null
            testing.expect_eq(t, value, 5, "the matched value is a copy, kept when the optional is emptied")
        }
        case None => testing.fail(t, "held holds 5")
    }
    return .Ok
}

keeps_optional_pointers_as_pointers #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    last := Link.{null, 3}
    first := Link.{&last, 4}
    none : ptr[Link]? = null
    testing.expect_eq(t, chain_total(&first), 7, "or_break walks the chain to its null end")
    testing.expect(t, !(none is_some), "a null optional pointer is none")
    testing.expect(t, !(first.next is_none), "a pointer in an optional pointer is some")
    // None is a null pointer in memory
    testing.expect_eq(t, cast[ptr[u64]](&last)^, 0, "the last link's next, none, is stored as a null pointer")
    return .Ok
}

uses_structs #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    labeled := Labeled.{Point.{1, 2}, 3}
    testing.expect_eq(t, labeled.x + labeled.y + labeled.weight, 6, "using reaches Point's fields through Labeled")
    moved := ORIGIN
    move(&moved, 5)
    testing.expect_eq(t, moved.x, 15, "a constant's copy changed through a pointer")
    testing.expect_eq(t, moved.y, 15, "both fields")
    big : Big
    big.values[31] = 5
    copy := big
    big.values[31] = 6
    testing.expect_eq(t, copy.values[31], 5, "a struct big enough for memmove is copied, not shared")
    testing.expect_eq(t, POINTS[1].y, 4, "an array constant of structs")
    return .Ok
}

takes_any_word_as_a_name #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    origin := Origin.{package = "hosted", match = 2}
    direction : Direction = .else
    testing.expect_eq(t, origin.match, 2, "match is a field's name")
    testing.expect_eq(t, origin.package.count, 6, "and package")
    testing.expect_eq(t, direction, Direction.else, "else is a member's name")
    testing.expect_eq(t, total_of(1, 2, 3, 4), 10, "contextual keywords are parameters' names")
    return .Ok
}

starts_with_defaults #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    declared : Defaults
    empty :: Defaults.{}
    some :: Defaults.{height = 7, plain = 1}
    framed : Framed
    testing.expect_eq(t, declared.width, 10, "a declaration starts with a field's default")
    testing.expect_eq(t, declared.height, 20, "a default from a constant declared after it, WIDE / 2")
    testing.expect(t, declared.shown, "a bool default")
    testing.expect_eq(t, declared.color, Color.Blue, "an enum default")
    testing.expect_eq(t, declared.plain, 0, "a field without a default is zero")
    testing.expect_eq(t, empty.width, 10, "an empty literal starts with the defaults")
    testing.expect_eq(t, empty.height, 20, "every one")
    testing.expect_eq(t, some.height, 7, "a field given in a literal replaces its default")
    testing.expect_eq(t, some.width, 10, "and the rest keep theirs")
    testing.expect_eq(t, some.plain, 1, "a field without a default, given")
    testing.expect_eq(t, framed.inner.height, 20, "a struct field holds its own defaults")
    testing.expect_eq(t, framed.border, 3, "beside the outer struct's")
    // Green is 1, Empty's area 0, the default width 10
    testing.expect_eq(t, painted(), 1010, "parameter defaults: an enum member, a variant without values, a struct's defaults")
    testing.expect_eq(t, painted(.Red, .Circle(1)), 310, "the defaults given: Red 0, a circle's area 3, the width 10")
    // 2 * 9 + (0 + 1 + 2 + 3), then with the factor given
    testing.expect_eq(t, scaled(2), 24, "defaults that are expressions run in the caller")
    testing.expect_eq(t, scaled(2, 1), 8, "the factor given, the offset's default still worked out")
    return .Ok
}

views_arrays_and_strings #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    text := "hello"
    testing.expect_eq(t, text.count, 5, "a literal's count")
    // A view of an array refers to it, so changes through the view reach it
    numbers_to_change : int[3]
    view : mut int[] = numbers_to_change
    view[1] = 5
    testing.expect_eq(t, numbers_to_change[1], 5, "a change through a view reaches the array it views")
    testing.expect_eq(t, sum_bytes(PRIMES), 28, "a table of integer constants, as a view")
    word : u8[] = WORD
    testing.expect_eq(t, word.count, 6, "#file_data holds word.txt's six bytes")
    testing.expect_eq(t, word[0], 0x48, "its first, H")
    testing.expect_eq(t, WORD[5], 0x41, "its last, A")
    greeting := "hello world"
    if 5 <= greeting.count {
        prefix :: greeting[0..<5]
        testing.expect_eq(t, prefix, "hello", "a slice of a string compares by its bytes")
    }
    testing.expect_ne(t, greeting, "hello", "a string and its prefix differ")
    testing.expect_eq(t, DIGITS[3], '3', "a constant string indexed")
    // A string made at run time, and its bytes through string_bytes
    made_storage : u8[16]
    made :: formatted(made_storage, "ab%", 7)
    made_bytes :: string_bytes(made)
    testing.expect_eq(t, made_bytes.count, 3, "string_bytes views a string made at run time")
    if 2 < made_bytes.count {
        testing.expect_eq(t, made_bytes[0], cast[u8]('a'), "its first byte")
        testing.expect_eq(t, made_bytes[2], cast[u8]('7'), "its last, the formatted 7")
    }
    testing.expect_eq(t, string_bytes("").count, 0, "an empty string has no bytes")
    return .Ok
}

uses_the_stack #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_ne(t, frames_above(), 0, "a stack trace sees at least this function's callers")
    testing.expect_eq(t, big_frame(), 3, "a frame bigger than a page is probed and used")
    return .Ok
}

holds_any_type_in_a_variant #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    counted := 1
    event : Event = .Counter(&counted)
    match event {
        case Counter(target) => target^ += 1
        case _ => {}
    }
    testing.expect_eq(t, counted, 2, "a variant holding a pointer writes through it")
    testing.expect_eq(t, larger(if counted > 1 { 10 } else { 0 }, 5), 10, "an if expression as an argument")
    return .Ok
}

handles_results #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_error(t, attempt_twice(true), Fault.Busy, "? passes the second attempt's error on")
    failures := 0
    attempt(true) or_else count_up(&failures)
    attempt(false) or_else count_up(&failures)
    testing.expect_eq(t, failures, 1, "or_else runs only for the error")
    testing.expect_eq(t, successes(), 2, "or_continue skips the three failed attempts of five")
    sized_ok :: sized(false)
    size :: testing.require_ok(t, sized_ok, "a result unwrapped where it's matched on")?
    testing.expect_eq(t, size, 7, "and the optional in it matched")
    testing.expect_error(t, sized(true), Fault.Busy, "? in a match's subject passes the error on")
    return .Ok
}

reflects_types #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    color_info :: cast[ptr[compiler.TypeInfoEnum]](info_of(Color.Blue))
    testing.expect_eq(t, color_info.variant, compiler.TypeInfoVariant.ENUM, "an any's type information says it's an enum")
    testing.expect_eq(t, color_info.name, "Color", "named as declared")
    if 2 < color_info.members.count && 2 < color_info.values.count {
        member :: color_info.members[2]
        value :: color_info.values[2]
        testing.expect_eq(t, member, "Blue", "its third member's name")
        testing.expect_eq(t, value, 2, "and value")
    }
    else {
        testing.fail(t, "Color has three members")
    }
    labeled_info :: cast[ptr[compiler.TypeInfoStruct]](type_info_of(Labeled))
    testing.require_eq(t, labeled_info.members.count, 2, "Labeled has a using Point and a weight")?
    if 1 < labeled_info.members.count {
        point :: labeled_info.members[0]
        weight :: labeled_info.members[1]
        testing.expect(t, point.is_using, "the first is using")
        testing.expect_eq(t, weight.offset, 16, "the weight is after the Point's two ints")
    }
    some_number : any = 5
    testing.expect(t, some_number.type == int, "an untyped integer in an any is an int")
    testing.expect(t, some_number.type != i64, "int is a type of its own, not i64")
    origin := Origin.{package = "hosted", match = 2}
    testing.expect(t, type_of(origin) == Origin, "type_of gives a value's type")
    return .Ok
}

formats_values_by_their_types #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    last := Link.{null, 3}
    first := Link.{&last, 4}
    none : ptr[Link]? = null
    shape_storage, colors_storage, point_storage, pointer_storage : u8[128]
    shape_text :: formatted(shape_storage, "% %", Shape.Rectangle(2, 3), first.next)
    testing.expect_ge(t, shape_text.count, 16, "a variant with values and a pointer, each written out")
    colors :: formatted(colors_storage, "%2 %1 %%", Color.Green, true)
    testing.expect_eq(t, colors, "true Green %", "numbered %s pick values, and %% is a %")
    point :: formatted(point_storage, "%", Point.{1, -2})
    testing.expect_eq(t, point, "Point{x = 1, y = -2}", "a struct is written with its fields' names")
    pointer :: formatted(pointer_storage, "% %", ptr[mut Point], none)
    testing.expect_eq(t, pointer, "ptr[mut Point] none", "a type is written by name, and an empty optional as none")
    return .Ok
}

runs_code_while_compiling #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, FIBONACCI_20, 6765, "a constant whose value calls a function")
    testing.expect_eq(t, #run fibonacci(10), 55, "#run in an expression")
    testing.expect_eq(t, SQUARES.count, 4, "a constant view made by a function")
    squares :: SQUARES
    if 3 < squares.count {
        last :: squares[3]
        testing.expect_eq(t, last, 16, "its last element")
    }
    testing.expect_eq(t, LABELED.y, 10, "a struct with using made while compiling")
    testing.expect_eq(t, LABELED.weight, 15, "its own field")
    testing.expect_eq(t, WHEN, "compiling", "#is_compile_time is true while compiling")
    testing.expect_eq(t, compile_time_name(), "running", "and false at run time")
    fibonacci_bytes : u8[FIBONACCI_7]
    testing.expect_eq(t, fibonacci_bytes.count, 13, "an array's count worked out while checking")
    testing.expect_eq(t, size_name(), "large", "an #if on a constant worked out while checking")
    testing.expect_eq(t, SQUARES_SUM, 55, "compile-time code allocates from its context: 0 + 1 + 4 + 9 + 16 + 25")
    testing.expect(t, tables_hold(), "tables of thousands of numbers, worked out while compiling, hold each value")
    testing.expect(t, REFLECTED_CONSTANTS, "a package's constants are worked out together, a logger's without a value")
    testing.expect_eq(t, REFLECTED_PARAMETERS, 3, "reflection finds text_buffer's append_format and its three parameters")
    return .Ok
}

knows_each_numbers_limits #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, max_value(u8), 255, "the largest u8")
    testing.expect_eq(t, min_value(i8), -128, "the smallest i8")
    testing.expect_eq(t, max_value(u64), 0xffff_ffff_ffff_ffff, "the largest u64")
    testing.expect_eq(t, min_value(u16), 0, "the smallest unsigned value is 0")
    testing.expect_gt(t, max_value(f32), 3.0e38, "the largest f32 is about 3.4e38")
    testing.expect_lt(t, min_value(f64), -1.0e308, "the smallest f64 is about -1.8e308")
    return .Ok
}

fails_allocations_on_purpose #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // The second allocation through a FailingAllocator fails, and the rest go through, each counted
    testing.expect(t, fails_the_second(), "a FailingAllocator fails only the allocation it's told to")
    // array_try_add gives the error, and the array stays as it was
    testing.expect(t, arrays_try(), "array_try_add and array_try_reserve give the error and leave the array as it was")
    return .Ok
}

ranks_locks #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Ranked locks: in order, out of order, and two of one rank by address
    testing.expect(t, ranks_hold(), "a lower rank after a higher is refused, and one rank is taken in address order")
    return .Ok
}

/**
 * Run the package's tests, reporting to standard output. It's a program, not only tests, so the back end's test can
 * also build it as one.
 *
 * @return 42 if every test passed; 1 if any failed.
 */
main :: fn() -> int {
    failed :: testing.run(#insert testing.tests_of(compiler.load_package(".")), testing.STANDARD_OUTPUT)
    return if failed == 0 { 42 } else { 1 }
}


// A FailingAllocator with fail_at 2: the first allocation works, the second fails, the third works; two blocks live
fails_the_second :: fn() -> bool {
    failing :: memory.make_failing(2) or_return false
    defer memory.free_failing(failing)
    first : mut u8[]
    third : mut u8[]
    first_error : runtime.AllocatorError?
    second_error : runtime.AllocatorError?
    third_error : runtime.AllocatorError?
    push_context failing_context (allocator = memory.failing_allocator(failing)) {
        first, first_error = runtime.new_array(u8, 16)
        _, second_error = runtime.new_array(u8, 16)
        third, third_error = runtime.new_array(u8, 16)
    }
    held :: failing.live
    if first_error == null {
        runtime.free_array(first)
    }
    if third_error == null {
        runtime.free_array(third)
    }
    return first_error == null && second_error != null && third_error == null && failing.allocations == 3 && failing.failed && held == 2
}

// array_try_add and array_try_reserve, through a FailingAllocator failing the first allocation: errors, the array unchanged
arrays_try :: fn() -> bool {
    failing :: memory.make_failing(1) or_return false
    defer memory.free_failing(failing)
    held := true
    push_context failing_context (allocator = memory.failing_allocator(failing)) {
        numbers : int[..]
        added :: runtime.array_try_add(&numbers, 7)
        held = added != null && numbers.count == 0 && numbers.capacity == 0
        // The second allocation works
        reserved :: runtime.array_try_reserve(&numbers, 4)
        held = held && reserved == null && numbers.capacity == 4 && runtime.array_try_add(&numbers, 8) == null && numbers.count == 1
        runtime.array_free(&numbers)
    }
    return held && failing.allocations == 2 && failing.live == 0
}

// lock_ranked and unlock_ranked: a higher rank after a lower is in order, a lower after a higher isn't
ranks_hold :: fn() -> bool {
    held : concurrency.HeldRanks
    locks : concurrency.SpinLock[3]
    first :: concurrency.lock_ranked(&locks[0], 10, &held)
    second :: concurrency.lock_ranked(&locks[1], 20, &held)
    // Lower than what's held: out of order
    inverted :: concurrency.lock_ranked(&locks[2], 5, &held)
    released :: concurrency.unlock_ranked(&locks[2], 5, &held) && concurrency.unlock_ranked(&locks[1], 20, &held)
    // Of the same rank, at a higher address, after: in order; and the first given back last
    same :: concurrency.lock_ranked_after(&locks[1], 10, &held)
    all :: concurrency.unlock_ranked(&locks[1], 10, &held) && concurrency.unlock_ranked(&locks[0], 10, &held)
    // Nothing held now: giving back what isn't held says so
    stray :: concurrency.unlock_ranked(&locks[0], 10, &held)
    return first && second && !inverted && released && same && all && !stray && held.count == 0
}
