package inserted_code

import compiler from "base"
import testing from "std"

/*
 * #insert outside a quote (docs/compilation.md, Code Values): code made at compile time, put in a body as
 * statements, whose definitions are seen after them, and as expressions, checked and generated as if
 * written there.
 */

/** Colors, one of which green inserts as a member's name. */
Color :: enum {
    /** Not inserted. */
    Red,
    /** What green's code names. */
    Green,
    /** Not inserted. */
    Blue,
}

/**
 * Make the expression 3 + 4.
 *
 * @return The code (3 + 4), which is 7 where it's inserted.
 */
seven :: fn() -> compiler.Code {
    return #code(3 + 4)
}

/**
 * Make an expression multiplying code by itself.
 *
 * @param code An expression, inserted twice.
 * @return The code (code * code).
 */
square_of :: fn(code: compiler.Code) -> compiler.Code {
    return #code(#insert code * #insert code)
}

/**
 * Make statements defining a local, total, and adding to it.
 *
 * @return Code declaring total := 0 then adding 40, so total is 40 after it where it's inserted.
 */
definitions :: fn() -> compiler.Code {
    return #code {
        total := 0
        total += 40
    }
}

/**
 * Make an expression whose type is inserted as code.
 *
 * @return The code size_of(u64), which is 8.
 */
size_code :: fn() -> compiler.Code {
    return #code(size_of(#insert u64))
}

/**
 * Make an expression naming an enum member.
 *
 * @return The code Color.Green.
 */
green :: fn() -> compiler.Code {
    return #code(#insert Color.Green)
}

defines_locals_with_inserted_statements #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    #insert definitions()
    // (3 + 4) - 5, since #insert binds like a prefix operator
    total += #insert seven() - 5
    testing.expect_eq(t, total, 42, "definitions' total of 40 is seen after it, then 7 - 5 is added")
    return .Ok
}

inserts_expressions #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, #insert square_of(seven()), 49, "code given as an argument is inserted whole, (3 + 4) * (3 + 4)")
    testing.expect_eq(t, #insert size_code(), 8, "a type inserted as code is the type, u64 of 8 bytes")
    color := #insert green()
    testing.expect_eq(t, color, Color.Green, "an inserted member's name reaches the member")
    return .Ok
}
