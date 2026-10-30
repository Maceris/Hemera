package cast_pointer_to_float

// An address isn't a float
main :: fn() {
    value : u64 = 7
    number :: cast[f64](&value)
}
