package secret_field_in_any

import runtime from "base"

Key :: struct #secret {
    bytes : u8[32],
}

// Not secret itself, but it holds one, which an any would carry somewhere its type is lost
Holder :: struct {
    name : u32,
    key : Key,
}

main :: fn() -> int {
    holder := Holder.{name = 1}
    runtime.log_info("a holder %", holder)
    return 0
}
