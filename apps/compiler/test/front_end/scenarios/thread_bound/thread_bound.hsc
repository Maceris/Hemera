package thread_bound

import runtime from "base"

// Values that can't leave their thread, given to what sends them to another (docs/multitasking.md)

// Counted without atomics, like std's LocalPtr
Count :: struct #thread_bound {
    value : int,
}

// Bound only when it's told it is, like SharedPtr[T, atomic]
Shared :: struct[atomic: bool] #thread_bound(!atomic) {
    value : int,
}

Holder :: struct {
    count : ptr[Count],
}

worker :: fn(data: any) {
}

// Hands its value to another thread, like a channel
send :: fn(value #escaping #crosses_threads : any) {
}

main :: fn() {
    count :: runtime.new(Count)
    atomic :: runtime.new(Shared[true])
    plain :: runtime.new(Shared[false])
    holder :: runtime.new(Holder)
    holder.count = count
    // Fine: nothing bound in it
    _ = runtime.thread_create(worker, atomic)
    // Marked itself, bound by its argument, and reached through a pointer
    _ = runtime.thread_create(worker, count)
    _ = runtime.thread_create(worker, plain)
    _ = runtime.thread_create(worker, holder)
    send(count)
}
