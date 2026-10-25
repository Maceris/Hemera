/*
 * A struct field's default is any constant (docs/types.md, Structs): beyond integers, booleans and enum members, a
 * float or string literal, or a function or a constant named, of any type, here or in another package. main returns
 * 42 if they all held, or the number of the first that didn't.
 */
package field_defaults

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

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

main :: fn() -> int {
    config := Config.{}
    errors := 0
    errors += check(config.scale == 1.5 && config.offset == -2.5, 1)
    errors += check(config.name == "config" && config.named == "abc", 2)
    errors += check(config.small == 0.25 && config.on && config.count == 7, 3)
    errors += check(config.op(4) == 8, 4)
    errors += check(config.at.x == 3 && config.at.y == 4, 5)
    // Given members keep what they're given, and the rest their defaults
    given := Config.{name = "given", count = 1}
    errors += check(given.name == "given" && given.count == 1 && given.named == "abc" && given.scale == 1.5, 6)
    // A zeroed one, as a variable's starting value, has them too
    zeroed : Config
    errors += check(zeroed.named == "abc" && zeroed.op(5) == 10, 7)
    if errors == 0 {
        return 42
    }
    return errors
}
