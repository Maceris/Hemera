package equality_of_view

// A struct holding a view can't be compared with ==, as a view can't (docs/types.md, Equality)
Holder :: struct {
    bytes : u8[],
}

main :: fn() -> bool {
    a := Holder.{}
    b := Holder.{}
    return a == b
}
