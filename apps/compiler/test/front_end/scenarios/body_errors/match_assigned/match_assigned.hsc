package match_assigned

f :: fn(x: int) -> int {
    result := 0
    // match gives a value to a definition, a return or an argument, not an assignment
    result = match x {
        case 1 => 2
        case _ => 3
    }
    return result
}
