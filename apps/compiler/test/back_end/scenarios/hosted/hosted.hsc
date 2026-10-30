/*
 * A hosted program for the back end's test: main returns 42 if everything worked, or the number
 * of the first check that failed.
 */
package hosted

import compiler from "base"
import intrinsics from "base"
import runtime from "base"
import memory from "std"
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
    if forward(1, 2, 3) != 17 {
        return 24
    }
    // A view of an array refers to it, so changes through the view reach it
    numbers_to_change : int[3]
    view : mut int[] = numbers_to_change
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
    sized_ok := match sized(false) {
        case Ok(size) => size == 7
        case Error(fault) => false
    }
    sized_failed := match sized(true) {
        case Ok(size) => false
        case Error(fault) => true
    }
    if !sized_ok || !sized_failed {
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
    shape_storage, colors_storage, point_storage, pointer_storage : u8[128]
    shape_text :: formatted(shape_storage, "% %", Shape.Rectangle(2, 3), first.next)
    if formatted(colors_storage, "%2 %1 %%", Color.Green, true) != "true Green %" || shape_text.count < 16 {
        return 44
    }
    if formatted(point_storage, "%", Point.{1, -2}) != "Point{x = 1, y = -2}"
        || formatted(pointer_storage, "% %", ptr[mut Point], none) != "ptr[mut Point] none" {
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
    if FIBONACCI_20 != 6765 || #run fibonacci(10) != 55 || SQUARES.count != 4 || SQUARES[3] != 16 {
        return 48
    }
    if LABELED.y != 10 || LABELED.weight != 15 || WHEN != "compiling" || compile_time_name() != "running" {
        return 49
    }
    fibonacci_bytes : u8[FIBONACCI_7]
    if fibonacci_bytes.count != 13 || size_name() != "large" {
        return 50
    }
    if SQUARES_SUM != 55 {
        return 51
    }
    if !tables_hold() {
        return 62
    }
    if !REFLECTED_CONSTANTS {
        return 63
    }
    if REFLECTED_PARAMETERS != 3 {
        return 52
    }
    ring : Ring[u8, RING_SIZE * 1]
    push[u8, 2](&ring, cast[u8](1))
    push(&ring, cast[u8](2))
    push(&ring, cast[u8](3))
    if ring.head != 2 || ring.items[1] != 2 || size_of(Ring[u8, 2]) != 16 {
        return 53
    }
    nines :: filled[4](cast[u8](9))
    bits : Bits[130]
    if nines.count != 4 || nines[3] != 9 || verbosity[true]() != 2 || verbosity[false]() != 1 || bits.words.count != 3 {
        return 54
    }
    // A match's values are copies: changing what was matched doesn't change them
    held : int? = 5
    match held {
        case Some(value) => {
            held = null
            if value != 5 {
                return 55
            }
        }
        case None => return 55
    }
    declared : Defaults
    empty :: Defaults.{}
    some :: Defaults.{height = 7, plain = 1}
    framed : Framed
    if declared.width != 10 || declared.height != 20 || !declared.shown || declared.color != .Blue || declared.plain != 0
        || empty.width != 10 || empty.height != 20 || some.height != 7 || some.width != 10 || some.plain != 1
        || framed.inner.height != 20 || framed.border != 3 {
        return 56
    }
    if area(PICKED) != 12 || area(ROUND) != 75 {
        return 57
    }
    // Green is 1, Empty's area 0, the default width 10
    if painted() != 1010 || painted(.Red, .Circle(1)) != 310 {
        return 58
    }
    // 2 * 9 + (0 + 1 + 2 + 3), then with the factor given
    if scaled(2) != 24 || scaled(2, 1) != 8 {
        return 59
    }
    // The most and least each kind of number holds
    if max_value(u8) != 255 || min_value(i8) != -128 || max_value(u64) != 0xffff_ffff_ffff_ffff || min_value(u16) != 0 {
        return 60
    }
    if max_value(f32) <= 3.0e38 || min_value(f64) >= -1.0e308 {
        return 61
    }
    // A string made at run time, and its bytes through string_bytes
    made_storage : u8[16]
    made :: formatted(made_storage, "ab%", 7)
    made_bytes :: string_bytes(made)
    if made_bytes.count != 3 || made_bytes[0] != cast[u8]('a') || made_bytes[2] != cast[u8]('7') || string_bytes("").count != 0 {
        return 64
    }
    // The second allocation through a FailingAllocator fails, and the rest go through, each counted
    if !fails_the_second() {
        return 65
    }
    // array_try_add gives the error, and the array stays as it was
    if !arrays_try() {
        return 66
    }
    return 42
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
