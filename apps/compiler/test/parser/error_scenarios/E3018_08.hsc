package error_scenarios

main :: fn() {
    x : int
    switch x
        case 1: println("1")
        case _: println("not 1")
    }
}
