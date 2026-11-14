package insert_statements_as_expression

import compiler from "base:compiler"

statements :: fn() -> compiler.Code {
    return #code {
        x := 1
    }
}

// Statements, where a value goes
main :: fn() -> int {
    return #insert statements()
}
