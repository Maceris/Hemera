/*
 * std/memory's SharedPtr (docs/memory.md, Shared Ownership): owners made, shared and released,
 * a weak reference upgraded, a value released with what make_shared was given or, for an #owned
 * one, its own release function, and a LocalPtr's plain counting. main returns 42 if each worked,
 * or the number of the first check that didn't.
 */
package shared_test

import compiler from "base"
import memory from "std"
import runtime from "base"

Buffer :: struct {
    size : int,
}

File :: struct #owned(close) {
    handle : ptr[mut int],
}

close :: fn(file: File) {
    file.handle^ += 1
    compiler.forget(file)
}

count_destroy :: fn(buffer: ptr[mut Buffer]) {
    buffer.size = -1
}

read_size :: fn(buffer: memory.SharedPtr[Buffer]) -> int {
    size :: buffer.size
    memory.release(buffer)
    return size
}

main :: fn() -> int {
    buffer #release :: memory.make_shared(Buffer.{size = 4096}, count_destroy)
    buffer.size = 40
    reader :: memory.share(&buffer)
    if read_size(reader) != 40 {
        return 1
    }
    weak #release :: memory.weaken(&buffer)
    match memory.upgrade(&weak) {
        case Some(again) => {
            again.size += 2
            memory.release(again)
        }
        case None => return 2
    }
    closed :: runtime.new(int)
    file :: memory.make_shared(File.{handle = closed})
    memory.release(file)
    if closed^ != 1 {
        return 3
    }
    runtime.free(closed)
    local :: memory.make_shared[int, false](7)
    other :: memory.share(&local)
    memory.release(local)
    if memory.pointer_of(&other)^ != 7 {
        memory.release(other)
        return 4
    }
    memory.release(other)
    return buffer.size
}
