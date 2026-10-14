package builtin_shadow

// A package can declare a builtin's name; unqualified, its own is used
Result :: struct {
    code : int,
}

// base. reaches the builtin
convert :: fn(mine: Result) -> base.Result[int, string] {
}

WIDTH :: base.size_of(Result)
