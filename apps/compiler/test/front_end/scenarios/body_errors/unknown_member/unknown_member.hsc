package unknown_member

Point :: struct {
    x : int,
    y : int,
}

f :: fn(p: Point) -> int {
    return p.z
}
