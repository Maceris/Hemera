/*
 * Format string options (docs/format_strings.md), the same in base's output_format and std's
 * text_buffer. Run with hemera --test.
 */
package format_test

import runtime from "base"
import testing from "std"
import text_buffer from "std"

Color :: enum {
    RED,
    GREEN,
}

/**
 * Check that base's output_format and std's text_buffer both format values as expected.
 *
 * @param t The test's state, which a failure of either is recorded in.
 * @param expected What both should write; at most 128 bytes.
 * @param format_string The format string both are given.
 * @param why Why it's expected, for whoever reads a failure.
 * @param values The values for the format string's %s.
 * @param location Where the check is; the caller's own.
 */
expect_formats :: fn(t: ptr[mut testing.T], expected: string, format_string: string, why: string, values: any...,
    location := #caller_location) {
    storage : u8[128]
    text := text_buffer.make(storage)
    text_buffer.append_format(&text, format_string, values)
    got :: text_buffer.as_string(&text)
    testing.expect_eq(t, got, expected, why, location)
    buffer := runtime.output_buffer(.OUTPUT)
    buffer.capture = true
    runtime.output_format(&buffer, format_string, values)
    base_got :: string_of(&buffer.bytes[0], buffer.count)
    testing.expect_eq(t, base_got, expected, why, location)
}

// Options that aren't well formed, written as %!
UNFIT :: "50%% %{q} x"

writes_integers_in_other_bases #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    address : u64 = 0x1f40
    expect_formats(t, "kernel+0x1f40", "kernel+%{#x}", "# puts the base's prefix before lowercase hex", address)
    expect_formats(t, "00001f40", "%{08x}", "a width with 0 pads hex digits with zeros", address)
    expect_formats(t, "1F40", "%{X}", "X writes hex in capitals", address)
    expect_formats(t, "101", "%{b}", "b writes binary", 5)
    expect_formats(t, "0b101", "%{#b}", "# puts 0b before binary", 5)
    expect_formats(t, "41", "%{x}", "a char in hex is its code", 'A')
    return .Ok
}

aligns_and_fills #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    expect_formats(t, "[    42]", "[%{>6}]", "> aligns right in the width", 42)
    expect_formats(t, "[42    ]", "[%{<6}]", "< aligns left in the width", 42)
    expect_formats(t, "[  42  ]", "[%{^6}]", "^ centers in the width", 42)
    expect_formats(t, "[***42]", "[%{*>5}]", "a character before the alignment fills with it", 42)
    return .Ok
}

writes_signs_and_zero_padding #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    expect_formats(t, "+7 -7", "%{+} %{+}", "+ writes a sign on positive numbers as well as negative", 7, -7)
    expect_formats(t, "-0042", "%{05}", "zero padding goes after the sign, within the width", -42)
    return .Ok
}

takes_values_by_position #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    expect_formats(t, "ff 10", "%2{x} %1", "a number before the options picks the value, from 1", 10, 255)
    return .Ok
}

formats_strings_enums_and_bools #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    expect_formats(t, "[hi   ]", "[%{5}]", "text is aligned left in a width by default", "hi")
    expect_formats(t, "[hel]", "[%{.3}]", "a precision cuts text to that many characters", "hello")
    expect_formats(t, "[GREEN  ]", "[%{7}]", "an enum member is written by name, aligned as text", Color.GREEN)
    expect_formats(t, "1", "%{d}", "d writes an enum member's value", Color.GREEN)
    expect_formats(t, "[true ]", "[%{5}]", "a bool is written as text, aligned as text", true)
    return .Ok
}

writes_options_that_arent_well_formed_as_a_mark #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Not written in place, so only found when it runs
    expect_formats(t, "50% %! x", UNFIT, "%% is a percent sign, and options that aren't any are written %!", 1)
    expect_formats(t, "plain 3", "plain %", "a % without options writes the value plainly", 3)
    return .Ok
}

writes_zeros_digit #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    expect_formats(t, "0 0 [  0]", "% %{x} [%{>3}]", "zero has its digit, in base's formatter as in std's", 0, 0, 0)
    return .Ok
}

formats_floats_with_precisions #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // In text_buffer only
    storage : u8[64]
    text := text_buffer.make(storage)
    text_buffer.append_format(&text, "%{.3}|%{8.2}|%{+.1}|%{08.2}", 3.14159, 2.5, 1.0, -2.5)
    testing.expect_eq(t, text_buffer.as_string(&text), "3.142|    2.50|+1.0|-0002.50",
        "a precision rounds to that many decimals, within a width, with a sign or zero padding")
    return .Ok
}

writes_the_shortest_float_that_reads_back #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    tenth_f32 : f32 = 0.1
    tenth_f16 : f16 = 0.1
    largest_f16 : f16 = 65504
    shortest : u8[128]
    floats := text_buffer.make(shortest)
    text_buffer.append_format(&floats, "% % % % % % % % % % %", 0.1, 1.5, 100.0, 0.001, 0.0001, 1e21, 123456.0, -0.0,
        tenth_f32, tenth_f16, largest_f16)
    testing.expect_eq(t, text_buffer.as_string(&floats), "0.1 1.5 100 0.001 1e-04 1e+21 123456 -0 0.1 0.1 65500",
        "without a precision, the shortest text that reads back as the same value, fixed unless scientific is shorter")
    return .Ok
}

writes_large_floats_with_an_exponent #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    large : u8[64]
    scientific := text_buffer.make(large)
    text_buffer.append_float(&scientific, 1e27, 0)
    text_buffer.append(&scientific, " ")
    text_buffer.append_float(&scientific, 1267650600228229401496703205376.0, 0)
    testing.expect_eq(t, text_buffer.as_string(&scientific), "1.000000e+27 1.267650e+30",
        "past 20 digits, cut short with an exponent: 1e27's top group of nine digits is one digit, counted once; 2^100 is exact")
    return .Ok
}
