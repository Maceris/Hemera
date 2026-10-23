package type_default_unfit

// A function type's default that doesn't fit its parameter, reported where it's written, once
BadFn :: alias fn(a: int, b: int = "text") -> int

first :: fn(f: BadFn) -> int {
    return f(1)
}

second :: fn(f: BadFn) -> int {
    return f(2)
}

// Reported though no call uses it
Unused :: fn(a: int, b: bool = 3)
