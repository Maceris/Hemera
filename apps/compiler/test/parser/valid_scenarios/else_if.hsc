package valid_scenarios

else_if :: fn(x: int) -> int {
    if x > 4 {
        return 1
    }
    else if x < 2 && x != 0 {
        return 2
    }
    else if is_even(x) {
        return 3
    }
    else {
        return 4
    }
}

else_if_value :: fn(x: int) -> int {
    return if x > 0 { 1 } else if x < 0 { -1 } else { 0 }
}
