package inserted_code

import compiler from "base"

/*
 * #insert outside a quote (docs/compilation.md, Code Values): code made at compile time, put in a body as
 * statements, whose definitions are seen after them, and as expressions, checked and generated as if
 * written there. main returns 42 if every insertion did what it should.
 */

Color :: enum {
    Red,
    Green,
    Blue,
}

seven :: fn() -> compiler.Code {
    return #code(3 + 4)
}

square_of :: fn(code: compiler.Code) -> compiler.Code {
    return #code(#insert code * #insert code)
}

definitions :: fn() -> compiler.Code {
    return #code {
        total := 0
        total += 40
    }
}

size_code :: fn() -> compiler.Code {
    return #code(size_of(#insert u64))
}

green :: fn() -> compiler.Code {
    return #code(#insert Color.Green)
}

main :: fn() -> int {
    #insert definitions()
    // (3 + 4) - 5, since #insert binds like a prefix operator
    total += #insert seven() - 5
    if #insert square_of(seven()) != 49 {
        return 1
    }
    if #insert size_code() != 8 {
        return 2
    }
    color := #insert green()
    if color != Color.Green {
        return 3
    }
    return total
}
