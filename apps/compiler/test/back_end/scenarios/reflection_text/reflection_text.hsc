/*
 * std/reflection's as_text: strings, booleans and enum members as as_string gives them, and numbers too, written into
 * storage the caller gives, an integer in decimal and a float as the shortest text that reads back as it.
 */
package reflection_text

import reflection from "std"
import testing from "std"

/** An enum whose members have names to write. */
Color :: enum {
    RED,
    GREEN,
}

writes_integers_in_decimal #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    storage : u8[32]
    negative, negative_valid :: reflection.as_text(-42, storage)
    testing.expect(t, negative_valid && negative == "-42", "a negative int is written with its sign")
    byte, byte_valid :: reflection.as_text(cast[u8](200), storage)
    testing.expect(t, byte_valid && byte == "200", "a u8 above i8's range is unsigned")
    smallest, smallest_valid :: reflection.as_text(cast[i8](-128), storage)
    testing.expect(t, smallest_valid && smallest == "-128", "the smallest i8, whose negation overflows, is written whole")
    return .Ok
}

writes_floats_as_the_shortest_text_that_reads_back #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    storage : u8[32]
    tenth, tenth_valid :: reflection.as_text(0.1, storage)
    testing.expect(t, tenth_valid && tenth == "0.1", "0.1 isn't exact in binary, but 0.1 is the shortest text giving it back")
    single : f32 = 1.5
    half, half_valid :: reflection.as_text(single, storage)
    testing.expect(t, half_valid && half == "1.5", "an f32 is written as itself, not as the f64 it widens to")
    return .Ok
}

writes_enum_members_by_name #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // What as_string gives needs no storage
    storage : u8[32]
    green, green_valid :: reflection.as_text(Color.GREEN, storage)
    testing.expect(t, green_valid && green == "GREEN", "an enum member is written as its name")
    return .Ok
}

refuses_a_number_too_long_for_its_storage #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    small : u8[2]
    _, long_valid :: reflection.as_text(12345, small)
    testing.expect(t, !long_valid, "five digits don't fit in two bytes")
    return .Ok
}
