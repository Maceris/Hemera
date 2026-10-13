package error_scenarios

main :: fn() {
    x : int
    match x {
        case 1..< => println("foo")
        case _ => println("bar") 
    }
}
