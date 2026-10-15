package builtin_shadow

// A package can declare a builtin's name; unqualified, its own is used
Result :: struct {
    code : int,
}

char :: struct {
    code : u32,
}

// base. reaches the builtin
convert :: fn(mine: Result) -> base.Result[int, string] {
    todo()
}

WIDTH :: base.size_of(Result)
