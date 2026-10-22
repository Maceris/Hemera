package bounds_signed_modulus

// % is truncated, so a negative i gives a negative index; %% would be at least 0
main :: fn(i: int) -> int {
    ring : int[16]
    return ring[i % 16]
}
