package error_scenarios

main :: fn() {
    x : int
    match x {
        ..=5 => println("foo")
        _ => println("bar") 
    }
}
