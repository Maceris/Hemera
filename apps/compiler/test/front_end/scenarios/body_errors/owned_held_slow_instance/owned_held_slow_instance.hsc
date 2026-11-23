package owned_held_slow_instance

import compiler from "base:compiler"

// A body that's slow to make, which an #insert holds back
fields :: fn() -> compiler.Code {
    spin := 0
    for i in 0..<200000 {
        spin = (spin + i) % 7
    }
    return if spin >= 0 { #code fields { count : int, } } else { #code fields {} }
}

File :: struct #owned(close) {
    handle : int,
}

close :: fn(file: File) {
    compiler.forget(file)
}

// Holds a File once its body is made, which may be after Crate's
Box :: struct[T] {
    #insert fields(),
    item : T,
}

// Holds an owner through a dynamic array of Box[File]s, so it has to say #owned, however late Box[File]'s body is
Crate :: struct {
    boxes : Box[File][..],
}

main :: fn() {
}
