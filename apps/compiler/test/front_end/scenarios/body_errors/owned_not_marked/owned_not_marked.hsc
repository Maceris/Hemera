package owned_not_marked

import compiler from "base"

File :: struct #owned(close) {
    handle : int,
}

close :: fn(file: File) {
    compiler.forget(file)
}

// Holds an owner, so it's owned too, and has to say so
Folder :: struct {
    file : File,
}

main :: fn() {
    folder : Folder
}
