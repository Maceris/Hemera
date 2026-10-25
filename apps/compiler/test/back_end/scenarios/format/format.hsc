/*
 * Format string options (docs/format_strings.md), the same in base's output_format and std's
 * text_buffer: main returns 42 if each gave what it should, and prints any that didn't.
 */
package format_test

import runtime from "base"
import text_buffer from "std"

Color :: enum {
    RED,
    GREEN,
}

check :: fn(expected: string, format_string: string, values: any...) -> bool {
    storage : u8[128]
    text := text_buffer.make(storage)
    text_buffer.append_format(&text, format_string, values)
    got :: text_buffer.as_string(&text)
    buffer := runtime.output_buffer(.OUTPUT)
    buffer.capture = true
    runtime.output_format(&buffer, format_string, values)
    base_got :: string_of(&buffer.bytes[0], buffer.count)
    if got != expected {
        runtime.write_output("text_buffer: [")
        runtime.write_output(got)
        runtime.write_output("] wanted [")
        runtime.write_output(expected)
        runtime.write_output("]\n")
        return false
    }
    if base_got != expected {
        runtime.write_output("base: [")
        runtime.write_output(base_got)
        runtime.write_output("] wanted [")
        runtime.write_output(expected)
        runtime.write_output("]\n")
        return false
    }
    return true
}

// Options that aren't well formed, written as %!
UNFIT :: "50%% %{q} x"

main :: fn() -> int {
    address : u64 = 0x1f40
    ok := true
    ok = check("kernel+0x1f40", "kernel+%{#x}", address) && ok
    ok = check("00001f40", "%{08x}", address) && ok
    ok = check("1F40", "%{X}", address) && ok
    ok = check("[    42]", "[%{>6}]", 42) && ok
    ok = check("[42    ]", "[%{<6}]", 42) && ok
    ok = check("[  42  ]", "[%{^6}]", 42) && ok
    ok = check("[***42]", "[%{*>5}]", 42) && ok
    ok = check("101", "%{b}", 5) && ok
    ok = check("0b101", "%{#b}", 5) && ok
    ok = check("+7 -7", "%{+} %{+}", 7, -7) && ok
    ok = check("-0042", "%{05}", -42) && ok
    ok = check("ff 10", "%2{x} %1", 10, 255) && ok
    ok = check("[hi   ]", "[%{5}]", "hi") && ok
    ok = check("[hel]", "[%{.3}]", "hello") && ok
    ok = check("[GREEN  ]", "[%{7}]", Color.GREEN) && ok
    ok = check("1", "%{d}", Color.GREEN) && ok
    ok = check("41", "%{x}", 'A') && ok
    ok = check("[true ]", "[%{5}]", true) && ok
    // Not written in place, so only found when it runs
    ok = check("50% %! x", UNFIT, 1) && ok
    ok = check("plain 3", "plain %", 3) && ok
    // Zero has its digit, in base's formatter as in std's
    ok = check("0 0 [  0]", "% %{x} [%{>3}]", 0, 0, 0) && ok
    // Floats, in text_buffer only
    storage : u8[64]
    text := text_buffer.make(storage)
    text_buffer.append_format(&text, "%{.3}|%{8.2}|%{+.1}|%{08.2}", 3.14159, 2.5, 1.0, -2.5)
    if text_buffer.as_string(&text) != "3.142|    2.50|+1.0|-0002.50" {
        runtime.write_output(text_buffer.as_string(&text))
        runtime.write_output("\n")
        ok = false
    }
    // Without a precision, the shortest text that reads back as the same value, fixed unless scientific is shorter
    tenth_f32 : f32 = 0.1
    tenth_f16 : f16 = 0.1
    largest_f16 : f16 = 65504
    shortest : u8[128]
    floats := text_buffer.make(shortest)
    text_buffer.append_format(&floats, "% % % % % % % % % % %", 0.1, 1.5, 100.0, 0.001, 0.0001, 1e21, 123456.0, -0.0,
        tenth_f32, tenth_f16, largest_f16)
    if text_buffer.as_string(&floats) != "0.1 1.5 100 0.001 1e-04 1e+21 123456 -0 0.1 0.1 65500" {
        runtime.write_output(text_buffer.as_string(&floats))
        runtime.write_output("\n")
        ok = false
    }
    return if ok { 42 } else { 1 }
}
