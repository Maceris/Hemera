/*
 * match and switch on strings (docs/control_flow.md): a string case matches a string with the same bytes, whatever
 * their length, and `case _` the rest. main returns 42 if they all held, or the number of the first that didn't.
 */
package string_cases

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

kind :: fn(compatible: string) -> int {
    return match compatible {
        case "pci-host-ecam-generic" => 1
        case "arm,gic-v3", "arm,gic-v3-its" => 2
        case "" => 3
        case _ => 4
    }
}

letters :: fn(text: string) -> int {
    found := 0
    switch text {
        case "a": found = 1
        #fall_through
        case "b": found += 10
        case _: found = 100
    }
    return found
}

// A constant's untyped string has a string's members, is indexed as one, and is gone through as one
PUNCTUATION :: "-=[]"

main :: fn() -> int {
    errors := 0
    errors += check(kind("pci-host-ecam-generic") == 1, 1)
    errors += check(kind("arm,gic-v3-its") == 2 && kind("arm,gic-v3") == 2, 2)
    errors += check(kind("") == 3 && kind("arm,gic-v") == 4 && kind("pci-host-ecam-generic!") == 4, 3)
    errors += check(letters("a") == 11 && letters("b") == 10 && letters("c") == 100, 4)
    errors += check(PUNCTUATION.count == 4 && PUNCTUATION[2] == '[', 5)
    sum := 0
    for character, i in PUNCTUATION {
        sum += cast[int](character) * cast[int](i + 1)
    }
    errors += check(sum == 45 + 61 * 2 + 91 * 3 + 93 * 4, 6)
    if errors == 0 {
        return 42
    }
    return errors
}
