/*
 * Used to smoke test the parser. Everything in this file should parse
 * successfully, but we don't care much about the exact output.
 */
package smoketest

// Imports
import io
import memory as mem
import library1 from "user"
import library2 from "../../foo/bar/baz"
import library3 as lib3 from "user"

// Structs
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

// Unions
union1 :: union {
	yes,
	no
}
union2 :: union {
	yes,
	no,
	maybe,
}
union3 :: union<T> {
	Some(T),
	None
}
union4 :: union<X, Y> {
	just_x(X),
	just_y(Y),
	both(X, Y),
}

// Enums

// Functions

// Arithmetic Expressions

// Boolean Expressions

// Branching Logic

// Loops

// Annotations

// Directives

