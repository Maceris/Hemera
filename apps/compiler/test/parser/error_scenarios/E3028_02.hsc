package error_scenarios

main :: fn() {
    x : int
    match x {
        case ..=5 => println("foo")
        case _ => println("bar") 
    }
}
