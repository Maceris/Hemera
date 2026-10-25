package relative_parameter

Node :: struct {
    value : int,
    next : relptr32[Node],
}

// A node passed by value is a copy of it
main :: fn(node: Node) -> int {
    return node.value
}
