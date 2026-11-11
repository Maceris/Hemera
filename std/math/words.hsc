package math

/*
 * An f64's two 32-bit words, as fdlibm reads and writes them: the high word holds the sign, the exponent and the
 * fraction's top 20 bits, and the low word the rest of the fraction.
 */

/**
 * Give an f64's high word, signed, so a negative number's is negative, as fdlibm compares it.
 *
 * @param x The number.
 * @return Its top 32 bits.
 */
high_word :: fn(x: f64) -> i32 {
    return cast[i32](bit_cast[u64](x) >> 32)
}

/**
 * Give an f64's low word.
 *
 * @param x The number.
 * @return Its bottom 32 bits.
 */
low_word :: fn(x: f64) -> u32 {
    return cast[u32](bit_cast[u64](x))
}

/**
 * Make an f64 from its two words.
 *
 * @param high The top 32 bits, any i32, taken as its bits.
 * @param low The bottom 32 bits.
 * @return The f64 they make.
 */
from_words :: fn(high: i32, low: u32) -> f64 {
    return bit_cast[f64]((cast[u64](cast[u32](high)) << 32) | cast[u64](low))
}

/**
 * Give an f64 with its high word replaced.
 *
 * @param x The number whose low word is kept.
 * @param high The new high word, taken as its bits.
 * @return The f64 made.
 */
with_high_word :: fn(x: f64, high: i32) -> f64 {
    return from_words(high, low_word(x))
}

/**
 * Give an f64 with its low word replaced, like fdlibm's SET_LOW_WORD: with 0, x cut to its top 21 bits of fraction, so
 * its products with short numbers are exact.
 *
 * @param x The number whose high word is kept.
 * @param low The new low word.
 * @return The f64 made.
 */
with_low_word :: fn(x: f64, low: u32) -> f64 {
    return from_words(high_word(x), low)
}

/** Give positive infinity as an f64. */
infinity_64 :: fn() -> f64 {
    return from_words(0x7ff0_0000, 0)
}

/** Give a quiet NaN as an f64. */
nan_64 :: fn() -> f64 {
    return from_words(0x7ff8_0000, 0)
}
