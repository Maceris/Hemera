/*
 * Arguments and indexes in parentheses, like f((a == b), c), and an enum compared with OS as a generic's argument. A
 * group in parentheses once read as another call on what the first returned, and OS, checked again as a generic call's
 * arguments are, as its enum. A package's own TARGET_ARCH is still its own. main returns 42 if each is what it should be.
 */
package parenthesized_arguments

import compiler from "base"

/** The package's, not the target's architecture. */
TARGET_ARCH :: 7

both :: fn(a: bool, b: bool) -> bool {
    return a && b
}

alone :: fn(a: bool) -> bool {
    return a
}

same :: fn[V](a: V, b: V) -> bool {
    return a == b
}

main :: fn() -> int {
    expected := true
    values := int.[1, 2, 3]
    at := 1
    first := both((1 == 1), expected)
    second := both(expected, (2 == 2))
    third := alone((3 == 3))
    fourth := values[(at + 1)] == 3
    fifth := same(OS == .Windows, OS == compiler.OperatingSystem.Windows)
    sixth := same((OS == .Linux), OS == compiler.OperatingSystem.Linux)
    seventh := same(TARGET_ARCH, 7) && TARGET_ARCH + 1 == 8
    return if first && second && third && fourth && fifth && sixth && seventh { 42 } else { 1 }
}
