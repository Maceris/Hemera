/*
 * Macros (docs/compilation.md, Macros): #macro functions called as name!(arguments), whose code is put in
 * place hygienically. The locals a macro's code declares are its own, and its names are looked up where
 * the macro was written (helpers), while the code it's given stays the caller's.
 */
package macros_test

import compiler from "base"
import helpers from "helpers"
import testing from "std"

// Not the doubled the macros in helpers call
doubled :: fn(n: int) -> int {
    return n * 100
}

// A macro in the caller's own file
negated #macro :: fn(x: compiler.Code) -> compiler.Code {
    return #code(0 - #insert x)
}

keeps_a_macros_locals_its_own #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    temporary := 5
    a := 1
    b := 30
    helpers.swap!(a, b)
    testing.expect_eq(t, a, 30, "swap! gave a b's value")
    testing.expect_eq(t, b, 1, "and b a's")
    testing.expect_eq(t, temporary, 5, "the macro's temporary is its own, not the caller's")
    // The caller's temporary, swapped with the macro's own beside it
    helpers.swap!(temporary, b)
    testing.expect_eq(t, temporary, 1, "the caller's temporary, given as an argument, is the caller's")
    testing.expect_eq(t, b, 5, "and swapped with b, apart from the macro's own temporary")
    return .Ok
}

looks_up_a_macros_names_where_it_was_written #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a := 30
    testing.expect_eq(t, helpers.twice_doubled!(3), 12, "the macro's doubled is helpers', 3 * 2 twice, not this package's")
    testing.expect_eq(t, helpers.quadrupled!(a), 240, "a macro's code calls another macro, both with helpers' doubled")
    testing.expect_eq(t, negated!(doubled(1)), -100, "code given to a macro keeps the caller's names, so doubled is 100")
    return .Ok
}

takes_values_as_macro_arguments #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    total := 0
    helpers.add!(total, 40)
    helpers.add!(total, 2)
    testing.expect_eq(t, total, 42, "each expansion adds the value given to the caller's total")
    return .Ok
}
