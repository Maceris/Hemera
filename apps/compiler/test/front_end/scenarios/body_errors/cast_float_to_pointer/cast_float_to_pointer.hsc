package cast_float_to_pointer

// A float holds no address (docs/operators.md, Casting operators)
main :: fn() {
    value : f64 = 4096.5
    address :: cast[ptr[u8]](value)
}
