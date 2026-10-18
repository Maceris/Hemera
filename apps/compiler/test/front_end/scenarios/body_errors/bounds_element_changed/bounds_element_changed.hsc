package bounds_element_changed

// Storing into an element forgets what was known about its fields
main :: fn() -> char {
    names : string[2]
    names[0] = "alpha"
    if names[0].count > 0 {
        names[0] = ""
        return names[0][0]
    }
    return ' '
}
