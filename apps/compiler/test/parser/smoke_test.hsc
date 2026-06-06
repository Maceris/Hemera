/*
 * Used to smoke test the parser. Everything in this file should parse
 * successfully, but we don't care much about the exact output.
 */
package smoketest

/*
 * Double checking that this:
 * /*
 *  * // example
 *  */
 * won't break anything
 */

//-----------------------------------------------------------------------------
//                                 Imports
//-----------------------------------------------------------------------------

import io
import memory as mem
import library1 from "user"
import library2 from "../../foo/bar/baz"
import library3 as lib3 from "user"

#if OS == .WINDOWS {
	import windows_io from "user"
	#if PLATFORM == .X86 {
		import more_specific_windows_io from "user"
	}
	#else {
		import less_specific_windows_io from "user"
	}
}

//-----------------------------------------------------------------------------
//                                Annotations
//-----------------------------------------------------------------------------

@Deprecated
this_has_an_annotation :: fn() {}

//-----------------------------------------------------------------------------
//                           Arithmetic Expressions
//-----------------------------------------------------------------------------

arithmetic_expressions :: fn() {
	result: int

	result = +3
	result = -3
	result = ~0x1f
	result = 1 + 2
	result = 2 * 4
	result = 5 - 3
	result = 10 / 3
	result = 17 % 5
	result = 17 %% 5
	result = 0b0000_1111 & 0b0101_0101
	result = 0b0000_1111 | 0b0101_0101
	result = 0b0000_1111 ~ 0b0101_0101
	result = 1 >> 4
	result = -42 >>> 4
	result = 1024 << 2
	result = 0o71

	result = +3 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = -3 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = ~0x1f * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = 1 + 2 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = 2 * 4 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = 5 - 3 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = 10 / 3 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = 17 % 5 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = 17 %% 5 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = 0b0000_1111 & 0b0101_0101 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = 0b0000_1111 | 0b0101_0101 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = 0b0000_1111 ~ 0b0101_0101 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = 1 >> 4 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = -42 >>> 4 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = 1024 << 2 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2
	result = 0o71 * 3 * 2 + 1 * 5 + 1 + 1 + 2 / 2

	result += 4
	result -= 5
	result *= 22
	result /= 3
	result %= 4
	result %%= 30
	result &= 0b1111_1001
	result |= 0b0000_0110
	result ~= 4256
	result <<= 4
	result >>= 3
	result >>>= 2

	result += 4 + 1 * 2
	result -= 5 + 1 * 2
	result *= 22 + 1 * 2
	result /= 3 + 1 * 2
	result %= 4 + 1 * 2
	result %%= 30 + 1 * 2
	result &= 0b1111_1001 + 1 * 2
	result |= 0b0000_0110 + 1 * 2
	result ~= 4256 + 1 * 2
	result <<= 4 + 1 * 2
	result >>= 3 + 1 * 2
	result >>>= 2 + 1 * 2

	result = 1 + 2 * 4 + 5
	result = 1 * 2 - 4 * 5
	result += 9 / 3 + 4 - 5 * 2 - 1 + (4 * 3 - (5 / 2))

	optional_result :: fn() -> int? {
		return 4
	}

	result = one_result() + one_result() * 2
	result = (optional_result() or_else 4) + 3
}

//-----------------------------------------------------------------------------
//                                  Arrays
//-----------------------------------------------------------------------------

arrays_example :: fn() {
	a : int[10]
	b : int[] : a
	c : int[] : a[2..<5]
	d : int[] : a[2..=4]
	e : int[] : a[5..]
	e2: int[] : a[5..<a.count]
	f : int[] : a[..<5]
	f2 : int[] : a[0..<5]
	g : int[] : a[..=5]
	g2 : int[] : a[0..=5]

	h : f64[2]
	i : i8[10][5]
	j : u32[..]
	k : string[..]

	l : int : nested_array.foo.bar[3].foo[2][3].bar
	l = nested_array[2][4].nested_array[3].foo.bar[3].foo[2][3].bar[1]
}

//-----------------------------------------------------------------------------
//                                Assignment
//-----------------------------------------------------------------------------

assignment_example :: fn() {
	x : int = 3
	y : int = 2
	z : int = 1

	x, y = y, x = z, y
	// By the way here x = 1, y = 2
	x, y <<= y, x += 3 * 1 - 1
	// and here x = 48, y = 32. Don't write code like this.

	x, y = 1
}

//-----------------------------------------------------------------------------
//                            Boolean Expressions
//-----------------------------------------------------------------------------

boolean_expressions :: fn() {
	result : bool
	a := true
	b := false
	x : = 4
	y : = 5

	optional_result :: fn() -> int? {
		return 4
	}

	result = true || false
	result = true && false
	result = a && !b || false && a
	result = a != b || x <= 5 && y >= 5
	result = x > y || x < 4 || x == 5
	result = optional_result() is_none
	result = optional_result() is_some
	result = if a { b } else { a || !b }
	result &&= a
	result ||= b
}

//-----------------------------------------------------------------------------
//                              Branching Logic
//-----------------------------------------------------------------------------

branching_logic :: fn() {
	result : int
	a := true
	b := false
	x : = 4
	y : = 5

	if x > 4 {
		result = x + 4
	}
	else if x < 2 {
		result = x - 1
	}
	else {
		result = -1	
	}

	if x < 5 && y == 5 {
		result = 43
	}
	if a || !b {
		result = 3
	}
	else {
		result = -result
	}
}

//-----------------------------------------------------------------------------
//                                  Casting
//-----------------------------------------------------------------------------

casting_example :: fn() {
	my_uint8 : u8 = 1
	my_uint16 : u16 = 2
	my_uint32 : u32 = 3
	my_uint : uint = 4
	my_float32 : f32 = 2e-2

	my_uint = cast[uint](my_uint8)
	my_uint = auto_cast(my_uint8)
	my_float32 = bit_cast[f32](my_uint32)
}

//-----------------------------------------------------------------------------
//                                  Context
//-----------------------------------------------------------------------------

context_example :: fn() {
	my_context: Context
	push_context my_context {
		// context here is referring to my_context
		context.allocator = memory.ArenaAllocator
		print_something("You can do whatever you want here")
	}
	// my_context would no longer be the context once we leave the block
}

//-----------------------------------------------------------------------------
//                                Directives
//-----------------------------------------------------------------------------

#if OS == .WINDOWS {
	EXAMPLE_CONSTANT : int : 1	
}
#else_if OS == .LINUX {
	EXAMPLE_CONSTANT : int : 2
}
#else {
	EXAMPLE_CONSTANT : int : 3	
}

#run println("Processing the smoke_test file")

inside_function :: fn() {
	#run println("Processing a function inside smoke_test")

	#if OS == .WINDOWS {
		println("This is Windows")
	}
	#else {
		println("This is not windows")
	}

	square :: fn(x : int) -> int {
		return x * x
	}

	even : bool = is_even(#run square(13))
}

//-----------------------------------------------------------------------------
//                                   Enums
//-----------------------------------------------------------------------------

enum1 :: enum {
	yes,
	no
}
enum2 :: enum {
	yes,
	no,
	maybe,
}
enum3 :: enum {
	clubs,
	hearts,
	spades,
	diamonds,
}

enum4 :: enum #backed_by(u8) {
	clubs,
	hearts,
	spades,
	diamonds,
}

//-----------------------------------------------------------------------------
//                                 Functions
//-----------------------------------------------------------------------------

implicitly_no_return    :: fn() {/* ... */}
explicitly_no_return    :: fn() -> void {/* ... */}
one_result              :: fn() -> int { return 1 }
one_result_still_same   :: fn() -> (int) { return 1 }
ptr_result              :: fn() -> ptr[int] { return &CONSTANT_INTEGER }
named_result            :: fn() -> (x: int) { return 4 }
two_results             :: fn() -> (int, int) { return 2, 3 }
two_named_results       :: fn() -> (x, y: int) { return 4, 5 }
three_named_results     :: fn() -> (a: u16, b, c: f32) { return 1, 2.3, 3.4 }
returning_pure_fn       :: fn() -> (fn()) { return implicitly_no_return }
returning_a_fn          :: fn() -> (fn() -> int) { return one_result }
ret_a_fn_with_2_returns :: fn() -> (fn() -> (int, int)) { return two_results }
returning_int_and_fn    :: fn() -> (int, (fn() -> int)) { return 1, one_result }
returning_fn_and_int    :: fn() -> ((fn() -> int), int) { return one_result, 2 }
print_something         :: fn(text: string) {}
print_something2        :: fn(text: string = "hello") {}
log_something           :: fn(text: string, location := #caller_location) {}
mutable_parameters      :: fn(rect: ptr[mut Rectangle], mut rawptr) {}
maybe_a_bool            :: fn() -> bool? { return None() }
result_return           :: fn() -> Result[u16, string] { return Ok(3) }

is_even :: fn(x: int) -> (result: bool, mod: int) {
    mod = x % 2
    result = mod == 0
    return result, mod
}

add_numbers : BinaryIntFunc : fn(x, y : int) -> int {
    return x + y
}

function_in_a_function :: fn() {
	just_a_dude_playing_a_dude :: fn(x: int) -> int {
		return x
	}
}

default_values :: fn(x: int = 3, y: int = 4) -> int { return x + y }

create_rectangle :: fn(x, y: int, width, height: uint) -> Rectangle {
	result : Rectangle = ---
	result.x = x
	result.y = y
	result.width = width
	result.height = height
	return result
}

format :: fn(format: string, args: any...) -> string {
	return "I forgot how to format strings"
}

//-----------------------------------------------------------------------------
//                              Function calls
//-----------------------------------------------------------------------------

function_calls :: fn() {
	a : int = one_result()
	b : int
	is_even_result : bool
	mod : int
	is_even_result, mod = one_result() |> is_even()

	b = one_result() |> add_numbers(a, _)
	b = one_result() |> add_numbers(_, a)
	b = one_result() |> add_numbers(a, $1)

	create_rectangle(1, 2, 50, 75)
    create_rectangle(x=1, y=2, 50, 75)
    create_rectangle(x=1, y=2, width=50, height=75)

	foo()
	foos[1+45-44]()
	foos.bar()
	// First class functions can be used for typecrimes
	cattle.dattle[4].asdf().foo[3][12].ghkl()(2)[2].baz()
	// dattle is an array of functions
	// asdf returns foo, a 2d array
	// foo is a 2d array of structs
	/* 
	 * ghkl returns a function - ()
	 * that returns a function - (2)
	 * that returns an array of structs - [2]
	 * that have a function stored in them - .baz()
	 */
}

//-----------------------------------------------------------------------------
//                                 Literals
//-----------------------------------------------------------------------------

decimal_int : int : 12345
negative_int : int : -12345
decimal_with_underscores : int : 1_234_567
hex_int : int : 0xabcd_ef01_2345
octal_int : int : 0o12_345_670
binary_int : int : 0b0110_1101_0001
plain_float : f32 : 1
decimal_float : f32 : 1.02
power_float : f32 : 4.02e3
power_capital_float : f32 : 4.0203E3
power_negative_float : f32 : 4.02e-3
string_literal :: "foobar"
multiline_string :: \\ This is a multline string
	\\ we can have these on several lines
	\\ if we really want to I guess
char_literal :: 'x'
bool_literal :: true
double_nested_ptr_type :: ptr[ptr[int]]
triple_nested_ptr_type :: ptr[ptr[ptr[int]]]
array_of_nested_ptrs :: ptr[ptr[u8]][..]

//-----------------------------------------------------------------------------
//                                   Loops
//-----------------------------------------------------------------------------

loops_example :: fn() {
	for i in 0..<10 {
		is_even(i)
	}

	for i in 1..=10 {
		is_even(i)
	}

	for i in one_result() ..< (one_result() + 10) {
		is_even(i)
	}

	some_array : int[3] : {1, 3, 19}

	for value in some_array {
		is_even(value)
	}

	for value, index in some_array {
		is_even(value + index)
	}

	for &value in some_array {
		is_even(value)
	}

	for &value, index in some_array {
		is_even(value + index)
	}

	for i in 0..=10 #reverse {
		is_even(i)
	}

	loop {
		break
	}

	loop {
		loop {
			break 2
		}
		loop {
			loop {
				break all
			}
		}
	}

	with {
		i : int = 0
	}
	loop {
		is_even(i)
		i += 1
	}
	while i <= 10

	loop #at_least_once {
		is_even(i)
	}
	while false

	loop {
		// This will not run
	}
	while false

}

deferring_example :: fn() {
	defer println("This prints last")
    defer println("This prints second")
    println("This prints first")

    with {
        i : int = 0
        matched : bool = false
    }
    loop {
        defer i += 1
        defer matched = false
        defer println()
        defer if !matched { print(i) }

        if i % 3 == 0 {
            print("fizz")
            matched = true
        }
        if i % 5 == 0 {
            println("buzz")
            matched = true
        }

        if i % 8 == 0 {
            break
        }
    }
    while i <= 10
}

//-----------------------------------------------------------------------------
//                                  Matches
//-----------------------------------------------------------------------------

match_example :: fn() {
	foo : string : match x {
		1 => "one"
		2, 3 => "two"
		4..<6 => "three"
		6..=30, 32, 44 => "four"
		_ => "default"
	}

	bar : int = match y {
		.FOO => 3
		example_enum.BAR => 43
		.BAZ, .CAZ => 2
	}

	baz : f32 = match z {
		"foo" => 4.3
		"bar", "Baz" => 2.1
		_ => 9.0
	}

	caz : example_enum : switch a {
		'a' => .FOO
		'b'..='m', 'o'..<'y' => .BAR
		_ => .UNKNOWN
	}

	match a {
		Ok(foo) => print(foo)
		Fail(_) => return 5
	}

	daf : i64be = switch x {
		true => 0xABCD_0123_FFFE_2398_0001_2223_DAF3_CAFB
		false => 0x0000_0000_0001_0000_1111_BBB7_00FF_CAFE
	}
}

//-----------------------------------------------------------------------------
//                                 Optionals
//-----------------------------------------------------------------------------

optionals :: fn() -> string? {
	possible : bool? : maybe_a_bool()

	if possible is_none {
		return .Some("foo")
	}
	else if possible is_some {
		return .Some("bar")
	}

	improbable : bool = maybe_a_bool() or_else false
	improbable = possible or_return .Some("I decided I don't care")
	improbable = maybe_a_bool()?

	loop {
		mission_maybe :: maybe_a_bool() or_break
		mission_not :: maybe_a_bool() or_continue
	}
	while false
}

optionals_without_result :: fn() {
	possible : bool : maybe_a_bool() or_return void
}

//-----------------------------------------------------------------------------
//                                 Pointers
//-----------------------------------------------------------------------------

pointer_example :: fn() {
	x : int = 4
	my_x : ptr[int] = &x
	my_x^ = 2

	rect : ptr[Rectangle] = new(Rectangle)
	defer delete(rect)
	rect.x = 4
	rect.y = 5
	rect2 := new(Rectangle)
	rect2^ = rect^
}

//-----------------------------------------------------------------------------
//                                 Results
//-----------------------------------------------------------------------------

results :: fn() -> Result[f32, string] {
	value : u16 = result_return() ?
	value = result_return() or_else 5
	value = result_return() or_return Ok(54)

	loop {
		age :: result_return() or_break
		age2 :: result_return() or_continue
	}
	while false
}

//-----------------------------------------------------------------------------
//                                 Structs
//-----------------------------------------------------------------------------

struct1 :: struct {}
struct2 :: struct {
	x: int,
	y: int
}
struct3 :: struct {
	x: f32,
}
struct4 :: struct[X, Y] {
	foo1: fn(X) -> Y
}

Rectangle :: #packed #align(8) struct {
	x : int,
	y : int,
	width : uint = 10,
	height : uint = 10,
}

struct_creation :: fn() {
	r1 := Rectangle.{}
	r2 : Rectangle = Rectangle.{1, 2, 3, 4}
	r3 := Rectangle.{y=1, x=2}
	r4 := new(Rectangle)
	defer delete r4
	r4^ = r3 
}

c_style_union :: struct #union {
	f : f32,
	i : i32,
	_ : struct { b1, b2, b3, b4 : i8 },
}

//-----------------------------------------------------------------------------
//                                 Switches
//-----------------------------------------------------------------------------

switch_example :: fn() {
	switch x {
		case 1: print("one")
		case 2, 3: print("two")
		#fall_through
		case 4..<6: print("three")
		case 6..=30, 32, 44: print("four")
		case _: {
			print("default")
		}
	}

	switch y {
		case .FOO: print("fooo")
		case example_enum.BAR: print("bar")
		case .BAZ, .CAZ: print("baz")
	}

	switch z {
		case "foo": print("1")
		case "bar", "Baz": print("2")
		case _: print("4")
	}

	switch a {
		case 'a': print("3")
		case 'b'..='m', 'o'..<'y': print("4")
		case _: print("45")
	}
}

//-----------------------------------------------------------------------------
//                                  Types
//-----------------------------------------------------------------------------

CONSTANT_INTEGER : int : 5
OTHER_INTEGER :: 1
int_fn :: fn(int) -> int
my_float :: alias f32
my_float2 :: f32
my_float3 : type : float
meters :: distinct alias int
BinaryIntFunc :: fn(int, int) -> int

MultipleNames :: fn(a, b, c : int)
MultipleNamesWithDefault :: fn(a, b, c : int = 1)
MultipleNamesComplex :: fn(a, b: int, c, d: float, e : int, f, g : float)
FuncResult :: fn() -> (fn())
FuncsAsArg :: fn(a, b: (fn()), c : (fn(int, int, int)) = MultipleNames)

//-----------------------------------------------------------------------------
//                                  Unions
//-----------------------------------------------------------------------------

union1 :: union { // Should parse, but not really reasonable
	yes,
	no
}
union2 :: union[T] {
	Some(T),
	None,
}
union3 :: union[X, Y]{
	just_x(X),
	just_y(Y),
	both(X, Y),
}
