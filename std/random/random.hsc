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

/**
 * Fill bytes with random bytes from context.random.
 *
 * They're as unpredictable as context.random is: the system's generator in a hosted program, fit for keys.
 *
 * @param bytes Where they go, every byte of it; an empty view asks for nothing.
 */
fill :: fn(bytes: mut u8[]) {
    context.random.fill(context.random.data, bytes)
}

/**
 * Draw a random 64-bit number.
 *
 * @return Any u64, each as likely as the others.
 */
next_u64 :: fn() -> u64 {
    bytes : u8[8]
    fill(bytes)
    return bit_cast[u64](bytes)
}

/**
 * Draw a number from 0 up to a limit, not including it, each as likely as the others.
 *
 * Draws that would make the low numbers likelier are drawn again, so there's no bias, at the cost of an occasional
 * extra draw.
 *
 * @param limit One more than the largest number wanted. 0 gives 0, drawing nothing.
 * @return A number from 0 to limit - 1; 0 for a limit of 0.
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

/**
 * Draw a number from low to high, both included, each as likely as the others.
 *
 * @param low The smallest number wanted.
 * @param high The largest; the whole range of i64 is allowed.
 * @return A number from low to high; low, drawing nothing, if high isn't above it.
 */
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
