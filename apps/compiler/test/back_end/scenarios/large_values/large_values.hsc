/*
 * Values too large for registers (docs/calling_convention.md, Large Values): results written through a pointer
 * the caller passes, and parameters passed as a pointer to the caller's copy, called by name, through function
 * values, with named and default arguments, through |>, recursively and with several results, and the original
 * never changed by what the callee does with its copy. main returns 42 if each worked, or the number of the first
 * check that didn't.
 */
package large_values_test

// 4 KiB: far too large for registers
Big :: struct {
    words: u64[512],
    tag: u8,
}

// Just over two registers
Small :: struct {
    a: u64,
    b: u64,
    c: u8,
}

big_of :: fn(seed: u64) -> Big {
    big := Big.{tag = cast[u8](seed)}
    for i in 0..<512 {
        big.words[i] = seed * 1000 + cast[u64](i)
    }
    return big
}

sum :: fn(big: Big) -> u64 {
    total : u64 = 0
    for word in big.words {
        total += word
    }
    return total + cast[u64](big.tag)
}

// Its copy changed, which the caller's original mustn't see
changed :: fn(big: Big) -> Big {
    copy := big
    copy.words[0] = 7
    copy.tag = 9
    return copy
}

// Several results, together too large for registers
split :: fn(big: Big) -> (first: u64, rest: Big, last: Small) {
    return big.words[0], big, Small.{a = big.words[1], b = big.words[511], c = big.tag}
}

maybe :: fn(seed: u64) -> Big? {
    if seed == 0 {
        return null
    }
    return big_of(seed)
}

// A default and a name for a large parameter
with_default :: fn(count: int, big := Big.{tag = 3}) -> u64 {
    return cast[u64](count) + cast[u64](big.tag) + big.words[0]
}

// Recursion, each level with its own copy and result
countdown :: fn(big: Big, depth: int) -> Big {
    if depth == 0 {
        return big
    }
    next := big
    next.words[1] += 1
    return countdown(next, depth - 1)
}

small_of :: fn(a: u64) -> Small {
    return Small.{a = a, b = a * 2, c = 1}
}

add_small :: fn(x: Small, y: Small) -> Small {
    return Small.{a = x.a + y.a, b = x.b + y.b, c = x.c + y.c}
}

main :: fn() -> int {
    big := big_of(2)
    if big.tag != 2 || big.words[0] != 2000 || big.words[511] != 2511 {
        return 1
    }
    expected : u64 = 0
    for i in 0..<512 {
        expected += 2000 + cast[u64](i)
    }
    if sum(big) != expected + 2 {
        return 2
    }
    other := changed(big)
    if big.words[0] != 2000 || big.tag != 2 || other.words[0] != 7 || other.tag != 9 || other.words[5] != 2005 {
        return 3
    }
    first, rest, last := split(big)
    if first != 2000 || rest.words[511] != 2511 || last.a != 2001 || last.b != 2511 || last.c != 2 {
        return 4
    }
    if maybe(0) != null {
        return 5
    }
    found := maybe(4) or_return 6
    if found.words[3] != 4003 {
        return 7
    }
    // Through a function value
    make : fn(seed: u64) -> Big = big_of
    total : fn(big: Big) -> u64 = sum
    if total(make(1)) != sum(big_of(1)) {
        return 8
    }
    if with_default(1) != 4 || with_default(1, big = big) != 2003 || with_default(count = 2, big = big_of(1)) != 1003 {
        return 9
    }
    if (big_of(3) |> sum()) != sum(big_of(3)) {
        return 10
    }
    deep := countdown(big, 20)
    if deep.words[1] != 2021 || big.words[1] != 2001 {
        return 11
    }
    s := add_small(small_of(1), small_of(2))
    if s.a != 3 || s.b != 6 || s.c != 2 {
        return 12
    }
    // A result used straight away, its fields read where the callee wrote it
    if big_of(5).words[10] != 5010 || changed(big_of(5)).tag != 9 {
        return 13
    }
    return 42
}
