package error_scenarios

main :: fn() {
    switch suit {
        case Clubs: println("club")
        case _: println("Computer says no...")
    }
}
