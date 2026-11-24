package at_most_default

// Its default is past its bound
Kept :: struct {
    name : u8[4],
    count #at_most(name.count) : usize = 5,
}

main :: fn() -> int {
    kept := Kept.{}
    return cast[int](kept.count)
}
