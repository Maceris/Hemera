package error_scenarios

main :: fn() {
    x : Result[string, string]
    match x {
        case Success(_ => println("oops")
    }
}
