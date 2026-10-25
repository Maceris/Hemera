package owned_errors

import compiler from "base"
import runtime from "base"

// Owners that aren't released or moved, or are used after they were (docs/memory.md, Owned Types)

File :: struct #owned(close) {
    handle : int,
}

open :: fn(handle: int) -> File {
    return File.{handle = handle}
}

close :: fn(file: File) {
    compiler.forget(file)
}

Holder :: struct #owned(release_holder) {
    file : File,
}

release_holder :: fn(holder: Holder) {
    compiler.forget(holder)
}

never_released :: fn() {
    a := open(1)
}

used_after_move :: fn() {
    a := open(1)
    close(a)
    close(a)
}

dropped :: fn() {
    open(1)
}

one_path :: fn(flag: bool) {
    a := open(1)
    if flag {
        close(a)
    }
}

in_a_loop :: fn() {
    a := open(1)
    for i in 0..<3 {
        close(a)
    }
}

replaced :: fn() {
    a := open(1)
    a = open(2)
    close(a)
}

release_moved :: fn() -> File {
    a #release :: open(1)
    return a
}

out_of_a_field :: fn(holder: ptr[Holder]) -> File {
    return holder.file
}

borrowed_element :: fn(files: ptr[File[..]]) {
    for file in files^ {
        close(file)
    }
}

dropped_array :: fn() {
    files : File[..]
    runtime.array_add(&files, open(1))
    runtime.array_free(&files)
}

// #fall_through goes on into the next case, so a is moved again there
moved_by_fall_through :: fn(n: int) {
    a := open(1)
    switch n {
        case 1:
            close(a)
        #fall_through
        case 2:
            close(a)
        case _:
            close(a)
    }
}

main :: fn() {
}
