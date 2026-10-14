package duplicate_function

// Names are unique in a package, functions too: there is no overloading
add :: fn(item: ptr[mut Item], value: int) {
}

add :: fn(item: ptr[mut Item], value: string) {
}

Item :: struct {
    total : int,
}
