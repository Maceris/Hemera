package thread_bound_slow_instance

import compiler from "base:compiler"
import runtime from "base:runtime"

// A body that's slow to make, which an #insert holds back
fields :: fn() -> compiler.Code {
    spin := 0
    for i in 0..<200000 {
        spin = (spin + i) % 7
    }
    return if spin >= 0 { #code fields { value : int, } } else { #code fields {} }
}

// Bound to its thread only when it's local, which its body works out, after the #insert
Count :: struct[local: bool] #thread_bound(local) {
    #insert fields(),
}

// Nothing here needs Count[true] laid out: it's on the heap, behind a pointer
Holder :: struct {
    counts : Count[true][..],
}

// Hands what it's given to another thread, like a channel
send :: fn(holder #escaping #crosses_threads : ptr[Holder]) {
}

// Reaches Count[true], which is #thread_bound, however late its body is made
forward :: fn() {
    holder :: runtime.new(Holder)
    send(holder)
}

main :: fn() {
}
