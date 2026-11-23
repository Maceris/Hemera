package owned_held_in_cycle

import compiler from "base:compiler"

// Each holds the other on the heap: neither waits for the other, and Folder still has to say #owned
Folder :: struct {
    files : File[..],
}

File :: struct #owned(close) {
    handle : int,
    parents : Folder[..],
}

close :: fn(file: File) {
    compiler.forget(file)
}

main :: fn() {
}
