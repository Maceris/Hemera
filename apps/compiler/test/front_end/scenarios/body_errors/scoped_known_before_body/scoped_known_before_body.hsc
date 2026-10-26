package scoped_known_before_body

import compiler from "base"

// A struct's #scoped is known before its body is: Parsers is checked while Parser's fields are still being made
fields :: fn() -> compiler.Code {
    spin := 0
    for i in 0..<200000 {
        spin = (spin + i) % 7
    }
    return if spin >= 0 { #code fields { input : u8[], } } else { #code fields {} }
}

Parser :: struct #scoped {
    #insert fields(),
}

Parsers :: struct {
    all : Parser[..],
}

main :: fn() {
    parsers : Parsers
}
