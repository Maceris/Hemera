/*
 * Used to smoke test the parser. Everything in this file should parse
 * successfully, but we don't care much about the exact output.
 */
package smoketest

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

function_in_a_function :: fn() {
	just_a_dude_playing_a_dude :: fn(x: int) -> int {
		return x
	}
}

default_values :: fn(x: int = 3, y: int = 4) -> int { return x + y }

//-----------------------------------------------------------------------------
//                              Function calls
//-----------------------------------------------------------------------------

//TODO(ches) add examples

function_calls :: fn() {

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

}

//-----------------------------------------------------------------------------
//                                 Pointers
//-----------------------------------------------------------------------------

//TODO(ches) add examples

//-----------------------------------------------------------------------------
//                                  Casting
//-----------------------------------------------------------------------------

//TODO(ches) add examples


//-----------------------------------------------------------------------------
//                                   Loops
//-----------------------------------------------------------------------------

//TODO(ches) add examples

//-----------------------------------------------------------------------------
//                                Annotations
//-----------------------------------------------------------------------------

@Deprecated
this_has_an_annotation :: fn() {}

//-----------------------------------------------------------------------------
//                                Directives
//-----------------------------------------------------------------------------

//TODO(ches) add examples
