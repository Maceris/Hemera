package cast_untyped_string_to_pointer

// A string isn't an address: its bytes are string_bytes(text)
main :: fn() {
    address :: cast[ptr[u8]]("hi")
}
