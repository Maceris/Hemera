package stack_return_variant_shorthand

// A variant named by itself, like .Ok(value), holds what it's given, here a pointer into this frame
local_ok :: fn() -> Result[ptr[int], int] {
    x := 5
    return .Ok(&x)
}

main :: fn() {
    _ = local_ok()
}
