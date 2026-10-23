package stated_type_defaults

// A function that states its type can't change the type's defaults (docs/functions.md, Defaults in Function Types)

FooFn :: alias fn(a: int, b: int = 1) -> int
PlainFn :: alias fn(a: int, b: int) -> int

// The type's default, written the same: allowed
same : FooFn : fn(a: int, b: int = 1) -> int {
    return a + b
}

// Inherits it: allowed
inherits : FooFn : fn(a: int, b: int) -> int {
    return a + b
}

different : FooFn : fn(a: int, b: int = 2) -> int {
    return a + b
}

extra : PlainFn : fn(a: int, b: int = 2) -> int {
    return a + b
}

written_out : fn(a: int, b: int = 1) -> int : fn(a: int, b: int = 2) -> int {
    return a + b
}
