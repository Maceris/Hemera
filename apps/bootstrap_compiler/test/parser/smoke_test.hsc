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
struct4 :: struct<X, Y> {
	foo1: fn(X) -> Y
}

Rectangle :: struct {
	x : int,
	y : int,
	width : uint,
	height : uint,
}

//-----------------------------------------------------------------------------
//                                  Unions
//-----------------------------------------------------------------------------

union1 :: union { // Should parse, but not really reasonable
	yes,
	no
}
union2 :: union<T> {
	Some(T),
	None,
}
union3 :: union<X, Y> {
	just_x(X),
	just_y(Y),
	both(X, Y),
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

//-----------------------------------------------------------------------------
//                                 Functions
//-----------------------------------------------------------------------------

implicitly_no_return    :: fn() {/* ... */}
explicitly_no_return    :: fn() -> void {/* ... */}
one_result              :: fn() -> int { return 1 }
one_result_still_same   :: fn() -> (int) { return 1 }
ptr_result              :: fn() -> ptr<int> { return &CONSTANT_INTEGER }
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

is_even :: fn(x: int) -> (result: bool, mod: int) {
    mod = x % 2
    result = mod == 0
    return // allowed, but not encouraged, if all results are assigned
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
	result : Rectangle
	result.x = x
	result.y = y
	result.width = width
	result.height = height
	return result
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
}

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

	result = 1 + 2 * 4 + 5
	result += 9 / 3 + 4 - 5 * 2 - 1 + (4 * 3 - (5 / 2))

	optional_result :: fn() -> int? {
		return 4
	}

	result = one_result() + one_result() * 2
	result = (optional_result() or_else 4) + 3
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
//                                 Pointers
//-----------------------------------------------------------------------------

pointer_example :: fn() {
	x : int = 4
	my_x : ptr<int> = &x
	my_x^ = 2

	rect : ptr<Rectangle> = new(Rectangle)
	defer delete(rect)
	rect.x = 4
	rect.y = 5
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

	my_uint = cast<uint>(my_uint8)
	my_uint = auto_cast(my_uint8)
	my_float32 = bit_cast<f32>(my_uint32)
}

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
	while (i <= 10)

	loop #at_least_once {
		is_even(i)
	}
	while(false)

	loop {
		// This will not run
	}
	while(false)

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
    while(i <= 10)
}

//-----------------------------------------------------------------------------
//                                Annotations
//-----------------------------------------------------------------------------

@Deprecated
this_has_an_annotation :: fn() {}

//-----------------------------------------------------------------------------
//                                Directives
//-----------------------------------------------------------------------------

#if OS == .WINDOWS {
	EXAMPLE_CONSTANT : int = 1	
}
#else_if OS == .LINUX {
	EXAMPLE_CONSTANT : int = 2
}
#else {
	EXAMPLE_CONSTANT : int = 3	
}

inside_function :: fn() {
	#if OS == .WINDOWS {
		println("This is Windows")
	}
	#else {
		println("This is not windows")
	}
}
