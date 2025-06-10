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
ptr_result              :: fn() -> ptr<int> { return &some_number }
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


//-----------------------------------------------------------------------------
//                           Arithmetic Expressions
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
//                            Boolean Expressions
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
//                              Branching Logic
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
//                                   Loops
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
//                                Annotations
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
//                                Directives
//-----------------------------------------------------------------------------

