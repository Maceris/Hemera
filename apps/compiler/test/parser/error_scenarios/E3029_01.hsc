package error_scenarios

main :: fn() {
    x : int
    match x {
        1..< => println("foo")
        _ => println("bar") 
    }
}
