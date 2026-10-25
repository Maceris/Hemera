package relative_copied

Node :: struct {
    value : int,
    next : relptr32[Node],
}

// A copy of a node in a variable: its next would be relative to the variable
main :: fn(node: ptr[Node]) -> int {
    copy := node^
    return copy.value
}
