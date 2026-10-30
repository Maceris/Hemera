package cast_pointer_to_bool

// Whether a pointer is null is a comparison, not a cast
main :: fn() {
    value : u64 = 7
    flag :: cast[bool](&value)
}
