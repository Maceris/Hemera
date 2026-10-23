package insert_statements_as_expression

import compiler from "base"

statements :: fn() -> compiler.Code {
    return #code {
        x := 1
    }
}

// Statements, where a value goes
main :: fn() -> int {
    return #insert statements()
}
