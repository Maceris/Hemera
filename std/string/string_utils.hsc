package string

char_is_number :: fn(value: char) -> bool {
    return value == '0' || value == '1'
        || value == '2' || value == '3'
        || value == '4' || value == '5'
        || value == '6' || value == '7'
        || value == '8' || value == '9'
}

char_to_int :: fn(value: char) -> (int, bool) {
    switch value {
        case '0': return 0, true
        case '1': return 1, true
        case '2': return 2, true
        case '3': return 3, true
        case '4': return 4, true
        case '5': return 5, true
        case '6': return 6, true
        case '7': return 7, true
        case '8': return 8, true
        case '9': return 9, true
        default: return 0, false
    }
}
