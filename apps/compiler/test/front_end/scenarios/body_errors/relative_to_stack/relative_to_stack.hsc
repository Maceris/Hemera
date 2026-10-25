package relative_to_stack

Counter :: struct {
    count : relptr32[int],
}

// A relative pointer is for shared or on-disk memory, never the stack
main :: fn(counter: ptr[mut Counter]) -> int {
    local := 0
    counter.count = &local
    return 0
}
