/*
 * std/memory's SharedPtr (docs/memory.md, Shared Ownership): owners made, shared and released,
 * a weak reference upgraded, a value released with what make_shared was given or, for an #owned
 * one, its own release function, and a LocalPtr's plain counting.
 */
package shared_test

import compiler from "base"
import memory from "std"
import runtime from "base"
import testing from "std"

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

shares_and_upgrades_owners_and_counts_local_ones #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    buffer #release :: memory.make_shared(Buffer.{size = 4096}, count_destroy)
    buffer.size = 40
    reader :: memory.share(&buffer)
    testing.expect_eq(t, read_size(reader), 40, "a shared owner sees what the first one wrote")
    weak #release :: memory.weaken(&buffer)
    match memory.upgrade(&weak) {
        case Some(again) => {
            again.size += 2
            memory.release(again)
        }
        case None => testing.fail(t, "a weak reference upgrades while an owner remains")
    }
    testing.expect_eq(t, buffer.size, 42, "what's written through an upgraded weak reference is the value the owners share")
    /*
     * A LocalPtr, here rather than in a test of its own: make_shared[int, false] checked beside the make_shared above,
     * in another function, can give its destroy parameter DestroyValue[int]? there (a compiler race)
     */
    local :: memory.make_shared[int, false](7)
    other :: memory.share(&local)
    memory.release(local)
    testing.expect_eq(t, memory.pointer_of(&other)^, 7, "a LocalPtr's value lives while one owner remains")
    memory.release(other)
    return .Ok
}

releases_an_owned_value_with_its_own_function #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    closed :: runtime.new(int)
    defer runtime.free(closed)
    file :: memory.make_shared(File.{handle = closed})
    memory.release(file)
    testing.expect_eq(t, closed^, 1, "the last release of an #owned value, without a destroy function, calls its own close")
    return .Ok
}
