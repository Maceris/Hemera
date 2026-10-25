package fall_through_last

// #fall_through goes on into the next case, so the last case has none to go to
main :: fn() -> int {
    result := 0
    switch result {
        case 0: result = 1
        case _: result = 2
        #fall_through
    }
    return result
}
