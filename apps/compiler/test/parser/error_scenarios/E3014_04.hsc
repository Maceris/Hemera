package error_scenarios

main :: fn() {
    // push_context needs at least one override
    push_context x {
        println("pushed")
    }
}
