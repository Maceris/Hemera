package error_scenarios

main :: fn() {
    x : int
    match x {
        case 4..=< => println("foo")
        case _ => println("bar") 
    }
}
