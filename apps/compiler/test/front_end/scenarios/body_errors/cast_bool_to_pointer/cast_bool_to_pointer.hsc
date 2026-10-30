package cast_bool_to_pointer

// A bool holds no address
main :: fn() {
    flag := true
    address :: cast[ptr[u8]](flag)
}
