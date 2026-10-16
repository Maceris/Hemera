package bounds_slice_backwards

// Both ends below the count, but not start <= end
main :: fn(values: int[], a: usize, b: usize) -> int[] {
    if a < values.count && b < values.count {
        return values[a..<b]
    }
    return values[0..<0]
}
