package secret_in_slow_body

import compiler from "base:compiler"

Key :: struct #secret {
    bytes : u8[32],
}

// A body that's slow to make, with a secret in it, which an #insert holds back
fields :: fn() -> compiler.Code {
    spin := 0
    for i in 0..<200000 {
        spin = (spin + i) % 7
    }
    return if spin >= 0 { #code fields { name : u32, key : Key, } } else { #code fields {} }
}

Entry :: struct {
    #insert fields(),
}

// Nothing here needs Entry laid out: it's on the heap, behind a pointer
Table :: struct {
    entries : Entry[..],
}

show :: fn(value: any) {
}

// Points to a secret, through the Entry a Table holds, however late Entry's body is made
print :: fn(table: ptr[Table]) {
    show(table)
}

main :: fn() {
}
