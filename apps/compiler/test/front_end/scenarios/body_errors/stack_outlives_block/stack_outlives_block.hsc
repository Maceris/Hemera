package stack_outlives_block

// p lives longer than y, which it would point to
main :: fn() {
    p : ptr[int]
    {
        y := 1
        p = &y
    }
}
