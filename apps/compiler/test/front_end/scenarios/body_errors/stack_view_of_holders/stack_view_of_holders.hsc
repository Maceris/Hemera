package stack_view_of_holders

// An array of views into the stack can't itself be viewed: a view isn't deep
count_them :: fn(names: string[]) -> usize {
    return names.count
}

main :: fn() {
    bytes : u8[8]
    names : string[2]
    names[0] = string_of(&bytes[0], 4)
    count_them(names)
}
