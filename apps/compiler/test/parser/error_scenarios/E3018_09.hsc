package error_scenarios

main :: fn() {
    x : int
    match x
        1 => println("1")
        _ => println("not 1")
    }
}
