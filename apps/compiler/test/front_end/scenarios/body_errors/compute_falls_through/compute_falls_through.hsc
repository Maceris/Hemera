package compute_falls_through

// Every path through a compute block gives or leaves: this one can finish without either
main :: fn(flag: bool) -> int {
    return compute[int] {
        if flag {
            give 1
        }
    }
}
