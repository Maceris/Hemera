package error_scenarios

main :: fn() {
    x : int
    switch x {
        case ..=5: println("foo")
        case _: println("bar") 
    }
}
