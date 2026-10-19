package alias_argument_count

Pair :: struct[A, B] {
    first : A,
    second : B,
}

// A generic alias takes its own parameters, not those of what it names
Named :: alias[V] Pair[string, V]

main :: fn() {
    named : Named[int, int]
}
