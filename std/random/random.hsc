package random

/*
 * Random numbers from context.random: the system's generator in a hosted program, and whatever a
 * kernel installs. Each call asks it for bytes, so these are as unpredictable as it is.
 *
 *     roll :: random.between(1, 6)
 *     key : u8[32]
 *     random.fill(key)
 *
 * MINIMAL_CONTEXT's generator stops the program instead, since predictable numbers would be worse.
 */

// bytes, filled with random bytes.
fill :: fn(bytes: mut u8[]) {
    context.random.fill(context.random.data, bytes)
}

next_u64 :: fn() -> u64 {
    bytes : u8[8]
    fill(bytes)
    return bit_cast[u64](bytes)
}

/*
 * A number from 0 up to limit, not including it, each as likely as the others: draws that would
 * make the low numbers likelier are drawn again. 0 for a limit of 0.
 */
below :: fn(limit: u64) -> u64 {
    if limit == 0 {
        return 0
    }
    // The draws at or above the last whole multiple of limit are the uneven ones
    uneven :: (0 - limit) % limit
    loop {
        draw :: next_u64()
        if draw >= uneven {
            return draw % limit
        }
    }
}

// A number from low to high, both included, each as likely. low if high is below it.
between :: fn(low: i64, high: i64) -> i64 {
    if high <= low {
        return low
    }
    span :: cast[u64](high) - cast[u64](low)
    if span == 0xffff_ffff_ffff_ffff {
        return cast[i64](next_u64())
    }
    return cast[i64](cast[u64](low) + below(span + 1))
}
