/*
 * std/reflection's as_text: strings, booleans and enum members as as_string gives them, and numbers too, written into
 * storage the caller gives, an integer in decimal and a float as the shortest text that reads back as it. main returns
 * 42 if they all held, or the number of the first that didn't.
 */
package reflection_text

import reflection from "std"

Color :: enum {
    RED,
    GREEN,
}

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

main :: fn() -> int {
    errors := 0
    storage : u8[32]
    negative, negative_valid :: reflection.as_text(-42, storage)
    errors += check(negative_valid && negative == "-42", 1)
    byte, byte_valid :: reflection.as_text(cast[u8](200), storage)
    errors += check(byte_valid && byte == "200", 2)
    smallest, smallest_valid :: reflection.as_text(cast[i8](-128), storage)
    errors += check(smallest_valid && smallest == "-128", 3)
    tenth, tenth_valid :: reflection.as_text(0.1, storage)
    errors += check(tenth_valid && tenth == "0.1", 4)
    single : f32 = 1.5
    half, half_valid :: reflection.as_text(single, storage)
    errors += check(half_valid && half == "1.5", 5)
    // What as_string gives needs no storage
    green, green_valid :: reflection.as_text(Color.GREEN, storage)
    errors += check(green_valid && green == "GREEN", 6)
    // A number storage can't hold isn't valid
    small : u8[2]
    _, long_valid :: reflection.as_text(12345, small)
    errors += check(!long_valid, 7)
    if errors == 0 {
        return 42
    }
    return errors
}
