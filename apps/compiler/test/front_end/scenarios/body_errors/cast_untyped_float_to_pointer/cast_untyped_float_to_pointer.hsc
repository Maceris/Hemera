package cast_untyped_float_to_pointer

// An untyped float is checked as one when it's cast to an address
main :: fn() {
    address :: cast[ptr[u8]](1.5)
}
