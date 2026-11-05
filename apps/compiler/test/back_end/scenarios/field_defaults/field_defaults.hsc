/*
 * A struct field's default is any constant (docs/types.md, Structs): beyond integers, booleans and enum members, a
 * float or string literal, or a function or a constant named, of any type, here or in another package. Run with
 * hemera --test.
 */
package field_defaults

import testing from "std"

twice :: fn(x: int) -> int {
    return x * 2
}

NAME :: "abc"
SCALE : f32 : 0.25
Point :: struct {
    x : int,
    y : int,
}
ORIGIN :: Point.{x = 3, y = 4}

Config :: struct {
    scale : f64 = 1.5,
    offset : f32 = -2.5,
    name : string = "config",
    named : string = NAME,
    small : f32 = SCALE,
    on : bool = true,
    count : int = 7,
    op : fn(x: int) -> int = twice,
    at : Point = ORIGIN,
}

defaults_fields_to_floats_and_strings #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    config :: Config.{}
    testing.expect_eq(t, config.scale, 1.5, "an f64 field defaults to its float literal")
    testing.expect_eq(t, config.offset, -2.5, "an f32 field defaults to a negated float literal")
    testing.expect_eq(t, config.name, "config", "a string field defaults to its string literal")
    testing.expect_eq(t, config.named, "abc", "a string field defaults to the string constant it names")
    testing.expect_eq(t, config.small, 0.25, "an f32 field defaults to the f32 constant it names")
    testing.expect(t, config.on, "a bool field defaults to true")
    testing.expect_eq(t, config.count, 7, "an int field defaults to its integer")
    return .Ok
}

defaults_fields_to_functions_and_structs #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    config :: Config.{}
    testing.expect_eq(t, config.op(4), 8, "a function field defaults to twice, which it names")
    testing.expect_eq(t, config.at.x, 3, "a struct field defaults to the constant ORIGIN, x and all")
    testing.expect_eq(t, config.at.y, 4, "a struct field defaults to the constant ORIGIN, y and all")
    return .Ok
}

keeps_given_fields_and_defaults_the_rest #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    given :: Config.{name = "given", count = 1}
    testing.expect_eq(t, given.name, "given", "a string given keeps what it's given")
    testing.expect_eq(t, given.count, 1, "an int given keeps what it's given")
    testing.expect_eq(t, given.named, "abc", "a string not given has its default")
    testing.expect_eq(t, given.scale, 1.5, "a float not given has its default")
    return .Ok
}

defaults_a_variables_starting_value #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    zeroed : Config
    testing.expect_eq(t, zeroed.named, "abc", "a variable declared without a value starts with the string default")
    testing.expect_eq(t, zeroed.op(5), 10, "a variable declared without a value starts with the function default")
    return .Ok
}

