package bounds_index_changed

// What was known about names[i].count is about the element i was, so changing i forgets it
first_letter :: fn(names: string[], start: usize) -> char {
    i := start
    if i < names.count && names[i].count > 0 {
        i += 1
        if i < names.count {
            return names[i][0]
        }
    }
    return ' '
}

main :: fn() {
    names : string[2]
    _ = first_letter(names, 0)
}
