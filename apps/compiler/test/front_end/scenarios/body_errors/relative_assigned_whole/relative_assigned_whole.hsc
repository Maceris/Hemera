package relative_assigned_whole

Node :: struct {
    value : int,
    next : relptr32[Node],
}

// Copying one node over another moves its offsets, not what they point to
main :: fn(a: ptr[mut Node], b: ptr[Node]) -> int {
    a^ = b^
    return 0
}
