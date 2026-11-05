/*
 * Owned types (docs/memory.md, Owned Types): owners released by defer, #release and compiler.release,
 * moved into functions and out of them, taken from fields, shared with duplicate, kept in a dynamic
 * array released with array_release, and given to a match's bindings.
 */
package owned_test

import compiler from "base"
import runtime from "base"
import testing from "std"

File :: struct #owned(close) {
    handle : int,
}

open :: fn(handle: int) -> File {
    return File.{handle = handle}
}

close :: fn(file: File) {
    compiler.forget(file)
}

// A second owner, as a shared pointer's share would make
share :: fn(file: ptr[File]) -> File {
    return compiler.duplicate(file)
}

handle_of :: fn(file: ptr[File]) -> int {
    return file.handle
}

Holder :: struct #owned(release_holder) {
    file : File,
}

release_holder :: fn(holder: Holder) {
    inner := holder
    close(compiler.take(&inner.file))
    compiler.forget(inner)
}

// Takes one and releases it when it ends
consume :: fn(file #release : File) -> int {
    return file.handle
}

pass_on :: fn(file: File) -> File {
    return file
}

maybe_open :: fn(handle: int) -> File? {
    if handle > 0 {
        return open(handle)
    }
    return null
}

total_of :: fn(files: ptr[File[..]]) -> int {
    total := 0
    for file in files^ {
        total += file.handle
    }
    return total
}

copies :: fn[T: compiler.Copyable](value: T) -> T {
    return value
}

#assert compiler.satisfies(compiler.Copyable(int)) && !compiler.satisfies(compiler.Copyable(File))

moves_and_releases_owners #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a := open(10)
    defer compiler.release(a)
    b #release :: open(20)
    c := open(5)
    testing.expect_eq(t, consume(pass_on(c)) + handle_of(&a) + b.handle, 35,
        "an owner moved in and out of a function is still the file it was, beside one borrowed and one released at the end")
    holder := Holder.{file = open(1)}
    compiler.release(holder)
    shared := share(&a)
    handle :: shared.handle
    compiler.forget(shared)
    testing.expect_eq(t, handle, 10, "a duplicated owner holds the same file")
    return .Ok
}

keeps_owners_in_arrays_and_matches #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    files : File[..]
    runtime.array_add(&files, open(3))
    runtime.array_add(&files, open(4))
    testing.expect_eq(t, total_of(&files), 7, "a dynamic array of owners holds each one added")
    runtime.array_release(files, close)
    total := 0
    match maybe_open(7) {
        case Some(file) => total = consume(file)
        case None => total = 0
    }
    testing.expect_eq(t, total, 7, "a match's binding takes the owner an optional held")
    testing.expect_eq(t, copies(42), 42, "a Copyable value passes through a generic constrained to them")
    return .Ok
}

