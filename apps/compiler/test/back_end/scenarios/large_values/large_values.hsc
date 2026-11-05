/*
 * Values too large for registers (docs/calling_convention.md, Large Values): results written through a pointer
 * the caller passes, and parameters passed as a pointer to the caller's copy, called by name, through function
 * values, with named and default arguments, through |>, recursively and with several results, and the original
 * never changed by what the callee does with its copy.
 */
package large_values_test

import testing from "std"

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

returns_and_passes_large_values #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    big := big_of(2)
    testing.expect_eq(t, big.tag, 2, "the result was written whole through the caller's pointer")
    testing.expect_eq(t, big.words[0], 2000, "the first word of the result")
    testing.expect_eq(t, big.words[511], 2511, "the last word of the result")
    expected : u64 = 0
    for i in 0..<512 {
        expected += 2000 + cast[u64](i)
    }
    testing.expect_eq(t, sum(big), expected + 2, "the parameter is the caller's whole value, every word and the tag")
    return .Ok
}

leaves_the_callers_copy_unchanged #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    big := big_of(2)
    other := changed(big)
    testing.expect_eq(t, big.words[0], 2000, "the callee changed its own copy, not the caller's")
    testing.expect_eq(t, big.tag, 2, "nor the caller's tag")
    testing.expect_eq(t, other.words[0], 7, "the callee's change is in its result")
    testing.expect_eq(t, other.tag, 9, "with its tag")
    testing.expect_eq(t, other.words[5], 2005, "and what it didn't change is the caller's")
    deep := countdown(big, 20)
    testing.expect_eq(t, deep.words[1], 2021, "each of 20 levels of recursion added 1 to its own copy")
    testing.expect_eq(t, big.words[1], 2001, "and none of them changed the caller's")
    return .Ok
}

gives_several_large_results #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    big := big_of(2)
    first, rest, last := split(big)
    testing.expect_eq(t, first, 2000, "the first result, in a register")
    testing.expect_eq(t, rest.words[511], 2511, "the second, a Big, whole")
    testing.expect_eq(t, last.a, 2001, "the third, a Small, its first field")
    testing.expect_eq(t, last.b, 2511, "its second field")
    testing.expect_eq(t, last.c, 2, "its last field, past two registers")
    s := add_small(small_of(1), small_of(2))
    testing.expect_eq(t, s.a, 3, "Smalls passed and returned through pointers add up, first field")
    testing.expect_eq(t, s.b, 6, "second field")
    testing.expect_eq(t, s.c, 2, "third field")
    return .Ok
}

gives_large_optionals #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    nothing :: maybe(0)
    testing.expect(t, nothing == null, "seed 0 gives no Big")
    given :: maybe(4)
    found :: testing.require_some(t, given, "seed 4 gives a Big")?
    testing.expect_eq(t, found.words[3], 4003, "the optional holds the whole Big")
    return .Ok
}

calls_with_large_values_every_way #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    big := big_of(2)
    // Through a function value
    make : fn(seed: u64) -> Big = big_of
    total : fn(big: Big) -> u64 = sum
    testing.expect_eq(t, total(make(1)), sum(big_of(1)), "function values pass and return large values as names do")
    testing.expect_eq(t, with_default(1), 4, "the default Big's tag is 3, and its words 0")
    testing.expect_eq(t, with_default(1, big = big), 2003, "a large argument given by name")
    testing.expect_eq(t, with_default(count = 2, big = big_of(1)), 1003, "both by name, the large one a call's result")
    testing.expect_eq(t, big_of(3) |> sum(), sum(big_of(3)), "|> passes a large result on as the first argument")
    // A result used straight away, its fields read where the callee wrote it
    testing.expect_eq(t, big_of(5).words[10], 5010, "a field of a result never stored in a local")
    testing.expect_eq(t, changed(big_of(5)).tag, 9, "a result passed straight to another call")
    return .Ok
}
