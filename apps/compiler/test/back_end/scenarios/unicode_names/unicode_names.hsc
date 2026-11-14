package unicode_names

import compiler from "base:compiler"
import testing from "std:testing"

/*
 * Names outside ASCII (docs/formatting.md): UAX #31's identifiers, of any script, for types, fields, enum members,
 * functions, parameters and locals, and one made with compiler.name. They're symbols in the object file and in the
 * assembly the compiler writes, quoted there. Run with hemera --test.
 */

Точка :: struct {
    x : int,
    высота : int,
}

Цвет :: enum {
    КРАСНЫЙ,
    緑,
    γαλάζιο,
}

面積 :: fn(幅: int, 高さ: int) -> int {
    return 幅 * 高さ
}

// A function named with compiler.name, which takes a name of any script as the lexer does
doubler :: fn() -> compiler.Code {
    return #code {
        #insert compiler.name("удвоить") :: fn(число: int) -> int {
            return число * 2
        }
    }
}

#insert doubler()

uses_names_of_any_script #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    точка := Точка.{ x = 3, высота = 4 }
    testing.expect_eq(t, 面積(точка.x, точка.высота), 12, "a function, its parameters and a struct's fields")
    цвет := Цвет.緑
    testing.expect_eq(t, cast[int](цвет), 1, "an enum member")
    testing.expect(t, Цвет.γαλάζιο != .КРАСНЫЙ, "enum members compared")
    testing.expect_eq(t, удвоить(21), 42, "a function named by compiler.name")
    return .Ok
}

writes_code_points_as_escapes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, "\u{41C}\u{438}\u{440}", "Мир", "a string's \\u{...} escapes are its code points' UTF-8")
    testing.expect_eq(t, "\u{202E}".count, 3, "a bidirectional control, written as an escape")
    return .Ok
}
