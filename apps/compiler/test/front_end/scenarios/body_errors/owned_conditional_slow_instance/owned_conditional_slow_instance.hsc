package owned_conditional_slow_instance

import compiler from "base:compiler"

// A body that's slow to make, which an #insert holds back
fields :: fn() -> compiler.Code {
    spin := 0
    for i in 0..<200000 {
        spin = (spin + i) % 7
    }
    return if spin >= 0 { #code fields { handle : int, } } else { #code fields {} }
}

// Owned only when it's real, which its body works out, after the #insert
Handle :: struct[real: bool] #owned(close, real) {
    #insert fields(),
}

close :: fn[real: bool](handle: Handle[real]) {
    compiler.forget(handle)
}

// Holds Handle[true]s, which are owned, so it has to say #owned, however late their body is
Holder :: struct {
    handles : Handle[true][..],
}

main :: fn() {
}
