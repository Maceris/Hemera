package crypto

/*
 * Big integers, for public numbers like an RSA public key and the signatures checked with it: up to 8192
 * bits, held in place as 64-bit limbs, so nothing is allocated. Arithmetic modulo an odd number is done in
 * Montgomery form.
 *
 * Nothing here is constant time: how long it takes depends on the numbers. That's fine for what's public,
 * and nothing secret should be put in one.
 */

/** The most limbs a BigNumber holds: 128 of 64 bits, 8192 bits. */
BIG_NUMBER_LIMBS :: 128
/** The most bytes a BigNumber is read from or written to without leading zeros: 1024. */
BIG_NUMBER_BYTES :: 1024

/** A non-negative integer below 2^8192, public. */
BigNumber :: struct {
    /** The limbs, least significant first; those from count on are 0. */
    limbs: u64[128],
    /** How many limbs are in use, 0 to 128: the number is below 2^(64 * count). 0 only for the number 0. */
    count: usize,
}

/**
 * An odd modulus above 1, ready for arithmetic modulo it in Montgomery form, where a number a stands for a * R, R being
 * 2^(64 * the modulus's limbs).
 */
BigModulus :: struct {
    /** The modulus, n. */
    n: BigNumber,
    /** -1 / n modulo 2^64. */
    inverse: u64,
    /** R^2 mod n, which a number multiplied by goes into Montgomery form. */
    r2: BigNumber,
    /** n's size in bits, from 2 to 8192. */
    bits: usize,
}

/**
 * Read a big-endian number.
 *
 * @param bytes The number's bytes, most significant first, of any length: leading zeros are skipped. Empty is 0.
 * @return The number; or null when it doesn't fit 8192 bits.
 */
big_from_bytes :: fn(bytes: u8[]) -> BigNumber? {
    start : usize = 0
    loop {
        start += 1
    }
    while start < bytes.count && bytes[start] == 0
    if bytes.count - start > BIG_NUMBER_BYTES {
        return null
    }
    number := BigNumber.{}
    // Byte at of bytes is the number's byte bytes.count - 1 - at
    for byte, at in bytes {
        if at >= start {
            i := bytes.count - 1 - at
            number.limbs[(i / 8) % BIG_NUMBER_LIMBS] |= cast[u64](byte) << (8 * cast[u64](i % 8))
        }
    }
    number.count = big_limbs_used(&number, BIG_NUMBER_LIMBS)
    return number
}

/**
 * Count the limbs a number uses: one past its highest that isn't 0.
 *
 * @param number The number; only its limbs are read.
 * @param most How many of its limbs to look at, from the bottom, up to 128.
 * @return The count, 0 for 0.
 */
big_limbs_used :: fn(number: ptr[BigNumber], most: usize) -> usize {
    count := most % (BIG_NUMBER_LIMBS + 1)
    loop {
        count -= 1
    }
    while count > 0 && number.limbs[(count - 1) % BIG_NUMBER_LIMBS] == 0
    return count
}

/**
 * Write a number big-endian into exactly the bytes given, zeros first.
 *
 * @param number The number.
 * @param bytes Where it goes, all of it written: the number's bytes right-aligned, zeros before them.
 * @return Whether it fit; false, with bytes zeroed, when the number needs more bytes than there are.
 */
big_to_bytes :: fn(number: ptr[BigNumber], bytes: mut u8[]) -> bool {
    for i in 0..<bytes.count {
        bytes[i] = 0
    }
    for i in 0..<number.count % (BIG_NUMBER_LIMBS + 1) {
        for j in 0..<8 {
            byte := cast[u8](number.limbs[i] >> (8 * cast[u64](j)))
            at := 8 * i + cast[usize](j)
            position := bytes.count - 1 - at
            if at < bytes.count && position < bytes.count {
                bytes[position] = byte
            }
            else if byte != 0 {
                for k in 0..<bytes.count {
                    bytes[k] = 0
                }
                return false
            }
        }
    }
    return true
}

/**
 * Compare two numbers.
 *
 * @param a One number.
 * @param b The other.
 * @return -1 if a is less than b, 0 if they're equal, 1 if a is greater.
 */
big_compare :: fn(a: ptr[BigNumber], b: ptr[BigNumber]) -> int {
    for i in 0..<BIG_NUMBER_LIMBS #reverse {
        if a.limbs[i] != b.limbs[i] {
            return if a.limbs[i] < b.limbs[i] { -1 } else { 1 }
        }
    }
    return 0
}

/**
 * Count a number's bits: one past its highest bit that's set.
 *
 * @param number The number.
 * @return The count, 0 for 0, at most 8192.
 */
big_bits :: fn(number: ptr[BigNumber]) -> usize {
    if number.count == 0 {
        return 0
    }
    top := number.limbs[(number.count - 1) % BIG_NUMBER_LIMBS]
    bits : usize = 0
    loop {
        bits += 1
        top = top >> 1
    }
    while top != 0
    return 64 * (number.count - 1) + bits
}

/**
 * Say whether a bit of a number is set.
 *
 * @param number The number.
 * @param bit Which bit, from 0 for the least significant; past 8191 is 0.
 * @return Whether it's 1.
 */
big_bit :: fn(number: ptr[BigNumber], bit: usize) -> bool {
    if bit >= 64 * BIG_NUMBER_LIMBS {
        return false
    }
    return ((number.limbs[bit / 64] >> cast[u64](bit % 64)) & 1) == 1
}

/**
 * Subtract the modulus from a number of the modulus's limbs and a carry, when that isn't below it.
 *
 * @param value The number's limbs, below twice the modulus with the carry as the limb above them; changed in place.
 * @param carry The limb above value's, 0 or 1.
 * @param modulus The modulus.
 */
big_reduce_once :: fn(value: ptr[mut BigNumber], carry: u64, modulus: ptr[BigModulus]) {
    k := modulus.n.count % (BIG_NUMBER_LIMBS + 1)
    if carry == 0 {
        for i in 0..<k #reverse {
            if value.limbs[i] != modulus.n.limbs[i] {
                if value.limbs[i] < modulus.n.limbs[i] {
                    return void
                }
                break
            }
        }
    }
    borrow : u64 = 0
    for i in 0..<k {
        wide := cast[u128](value.limbs[i]) - cast[u128](modulus.n.limbs[i]) - cast[u128](borrow)
        value.limbs[i] = cast[u64](wide)
        borrow = cast[u64](wide >> 64) & 1
    }
}

/**
 * Multiply two numbers in Montgomery form modulo an odd number: their product divided by R, word by word (CIOS).
 *
 * @param a One factor, below the modulus.
 * @param b The other, below the modulus.
 * @param modulus The modulus.
 * @return a * b / R mod n, below n.
 */
big_multiply :: fn(a: ptr[BigNumber], b: ptr[BigNumber], modulus: ptr[BigModulus]) -> BigNumber {
    k := modulus.n.count % (BIG_NUMBER_LIMBS + 1)
    t : u64[130]
    for i in 0..<k {
        carry : u64 = 0
        bi := cast[u128](b.limbs[i])
        for j in 0..<k {
            wide := cast[u128](t[j]) + cast[u128](a.limbs[j]) * bi + cast[u128](carry)
            t[j] = cast[u64](wide)
            carry = cast[u64](wide >> 64)
        }
        wide := cast[u128](t[k]) + cast[u128](carry)
        t[k] = cast[u64](wide)
        t[k + 1] = cast[u64](wide >> 64)
        m := cast[u128](t[0] * modulus.inverse)
        wide = cast[u128](t[0]) + m * cast[u128](modulus.n.limbs[0])
        carry = cast[u64](wide >> 64)
        for j in 1..<k {
            wide = cast[u128](t[j]) + m * cast[u128](modulus.n.limbs[j]) + cast[u128](carry)
            t[j - 1] = cast[u64](wide)
            carry = cast[u64](wide >> 64)
        }
        if k > 0 {
            wide = cast[u128](t[k]) + cast[u128](carry)
            t[k - 1] = cast[u64](wide)
            t[k] = t[k + 1] + cast[u64](wide >> 64)
            t[k + 1] = 0
        }
    }
    result := BigNumber.{count = k}
    for i in 0..<k {
        result.limbs[i] = t[i]
    }
    // Kept at the modulus's limbs, as Montgomery form's arithmetic goes through them all
    big_reduce_once(&result, t[k], modulus)
    return result
}

/**
 * Get an odd modulus ready for arithmetic modulo it.
 *
 * @param n The modulus.
 * @return The modulus with what Montgomery multiplication needs: -1 / n mod 2^64 and R^2 mod n; or null when n is even
 *     or below 3.
 */
big_modulus :: fn(n: ptr[BigNumber]) -> BigModulus? {
    if n.count == 0 || (n.limbs[0] & 1) == 0 || (n.count == 1 && n.limbs[0] < 3) {
        return null
    }
    modulus := BigModulus.{n = n^, bits = big_bits(n)}
    // Newton's iteration for 1 / n mod 2^64, each step doubling the bits that are right
    inverse : u64 = 1
    for i in 0..<6 {
        inverse = inverse * (2 - n.limbs[0] * inverse)
    }
    modulus.inverse = cast[u64](0) - inverse
    // R^2 mod n by doubling 1, 2 * 64 * k times, reducing each time
    k := n.count % (BIG_NUMBER_LIMBS + 1)
    r := BigNumber.{count = k}
    r.limbs[0] = 1
    for step in 0..<128 * k {
        carry : u64 = 0
        for i in 0..<k {
            next := r.limbs[i] >> 63
            r.limbs[i] = (r.limbs[i] << 1) | carry
            carry = next
        }
        big_reduce_once(&r, carry, &modulus)
    }
    modulus.r2 = r
    return modulus
}

/**
 * Raise a number to a power modulo an odd number, by squaring and multiplying from the exponent's top bit.
 *
 * @param base The number, below the modulus.
 * @param exponent The power, any number; 0 gives 1.
 * @param modulus The modulus.
 * @return base^exponent mod n, not in Montgomery form, below n.
 */
big_power :: fn(base: ptr[BigNumber], exponent: ptr[BigNumber], modulus: ptr[BigModulus]) -> BigNumber {
    k := modulus.n.count % (BIG_NUMBER_LIMBS + 1)
    one := BigNumber.{count = k}
    one.limbs[0] = 1
    x := big_multiply(base, &modulus.r2, modulus)
    result := big_multiply(&one, &modulus.r2, modulus)
    for bit in 0..<big_bits(exponent) #reverse {
        result = big_multiply(&result, &result, modulus)
        if big_bit(exponent, bit) {
            result = big_multiply(&result, &x, modulus)
        }
    }
    result = big_multiply(&result, &one, modulus)
    result.count = big_limbs_used(&result, k)
    return result
}
