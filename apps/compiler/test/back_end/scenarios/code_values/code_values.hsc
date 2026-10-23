package code_values

import compiler from "base"
import runtime from "base"

/*
 * Code values (docs/compilation.md, Code Values): quotes, made at compile time, with what #insert puts in
 * them, checked by their text. A quote isn't checked itself, so the names in it needn't exist. main
 * returns 42 if every quote came out as it should; a wrong one fails the build.
 */

Color :: enum {
    Red,
    Green,
    Blue,
}

// At compile time, an error fails the build
expect :: fn(code: compiler.Code, text: string) {
    made :: compiler.code_text(code)
    if made != text {
        runtime.log_error("a quote came out as [%], not [%]", made, text)
    }
}

quotes_work :: fn() -> bool {
    sum :: #code(a + b)
    expect(sum, "a + b")
    // Code, with the parentheses its operator needs, and a literal of a value worked out here
    n := 6 * 7
    expect(#code(#insert sum * #insert n), "(a + b) * 42")
    expect(#code(#insert -5 * 2), "-5 * 2")
    expect(#code(2 - #insert -5), "2 - -5")
    // A type, as itself
    expect(#code(size_of(#insert u64)), "size_of(u64)")
    // Statements, with literals of every kind
    expect(#code {
        total := #insert 1.5
        name :: #insert "hi\n"
        flag :: #insert true
        letter :: #insert 'x'
        color :: #insert Color.Green
        #insert sum
    }, "total := 1.5\nname :: \"hi\\n\"\nflag :: true\nletter :: 'x'\ncolor :: Color.Green\na + b\n")
    // Statements inserted among statements go in as statements
    inner :: #code {
        middle()
    }
    expect(#code {
        first()
        #insert inner
        last()
    }, "first()\nmiddle()\nlast()\n")
    expect(#code(#insert sum), "a + b")
    // A quote in a quote keeps its own #insert, for when it's evaluated
    expect(#code(#code(#insert x)), "#code(#insert x)")
    return true
}

QUOTES_WORK :: quotes_work()

/*
 * A Code is numbered within the compile-time code that made it, so the numbers don't depend on what ran
 * meanwhile, on other threads, and a build that reads them comes out the same each time.
 */
first_handle :: fn() -> u64 {
    code :: #code(x)
    return code.handle
}

FIRST :: first_handle()
FIRST_AGAIN :: first_handle()

main :: fn() -> int {
    return if QUOTES_WORK && FIRST == 1 && FIRST_AGAIN == 1 { 42 } else { 1 }
}
