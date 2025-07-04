package error_scenarios

main :: fn() {
    x : Result[string, string]
    match x {
        Success(_ => println("oops")
    }
}
