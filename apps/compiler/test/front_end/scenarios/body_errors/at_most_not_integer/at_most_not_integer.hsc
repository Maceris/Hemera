package at_most_not_integer

// #at_most is for integers
Named :: struct {
    name #at_most(4) : string,
}

main :: fn() -> int {
    named := Named.{}
    return cast[int](named.name.count)
}
