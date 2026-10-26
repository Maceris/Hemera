package owned_known_before_body

import compiler from "base"

// A struct's #owned is known before its body is: drop is checked while File's fields are still being made
fields :: fn() -> compiler.Code {
    spin := 0
    for i in 0..<200000 {
        spin = (spin + i) % 7
    }
    return if spin >= 0 { #code fields { handle : int, } } else { #code fields {} }
}

File :: struct #owned(close) {
    #insert fields(),
}

close :: fn(file: File) {
    compiler.forget(file)
}

// Its elements are on the heap, so nothing here needs File laid out
drop :: fn(files: File[..]) {
}

main :: fn() {
}
