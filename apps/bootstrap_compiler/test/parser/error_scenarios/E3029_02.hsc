package error_scenarios

main :: fn() {
    x : int
    match x {
        4..=< => println("foo")
        _ => println("bar") 
    }
}
