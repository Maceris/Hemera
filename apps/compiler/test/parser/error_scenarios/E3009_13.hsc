package error_scenarios

main :: fn() {
    // A member access after a cast needs a name
    x :: cast[ptr[Foo]](data).
}
