/*
 * match and switch on strings (docs/control_flow.md): a string case matches a string with the same bytes, whatever
 * their length, and `case _` the rest.
 */
package string_cases

import testing from "std"

/**
 * Sort a devicetree compatible string, through match on strings.
 *
 * @param compatible Any text.
 * @return 1 for PCI's generic host, 2 for either GICv3 name, 3 for "", 4 for anything else.
 */
kind :: fn(compatible: string) -> int {
    return match compatible {
        case "pci-host-ecam-generic" => 1
        case "arm,gic-v3", "arm,gic-v3-its" => 2
        case "" => 3
        case _ => 4
    }
}

/**
 * Sort a letter, through switch on strings with a case that falls through.
 *
 * @param text Any text.
 * @return 11 for "a", which falls through to "b"'s case; 10 for "b"; 100 for anything else.
 */
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

/** A constant's untyped string, which has a string's members, is indexed as one, and is gone through as one. */
PUNCTUATION :: "-=[]"

matches_strings_by_their_bytes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, kind("pci-host-ecam-generic"), 1, "a string with the case's bytes matches it")
    testing.expect_eq(t, kind("arm,gic-v3-its"), 2, "a case of two strings matches the second")
    testing.expect_eq(t, kind("arm,gic-v3"), 2, "and the first, a prefix of the second")
    testing.expect_eq(t, kind(""), 3, "the empty string matches its own case")
    testing.expect_eq(t, kind("arm,gic-v"), 4, "a prefix of a case's string isn't it")
    testing.expect_eq(t, kind("pci-host-ecam-generic!"), 4, "nor is a case's string with more after it")
    return .Ok
}

switches_on_strings #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, letters("a"), 11, "\"a\" falls through into \"b\"'s case")
    testing.expect_eq(t, letters("b"), 10, "\"b\" runs only its own case")
    testing.expect_eq(t, letters("c"), 100, "anything else goes to case _")
    return .Ok
}

uses_a_constant_string_as_a_string #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, PUNCTUATION.count, 4, "an untyped string constant has a count")
    testing.expect_eq(t, PUNCTUATION[2], '[', "and is indexed by byte")
    sum := 0
    for character, i in PUNCTUATION {
        sum += cast[int](character) * cast[int](i + 1)
    }
    testing.expect_eq(t, sum, 45 + 61 * 2 + 91 * 3 + 93 * 4, "and is gone through byte by byte, in order")
    return .Ok
}
