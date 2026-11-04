package crypto

import compiler from "base"
import intrinsics from "base"

/*
 * BLAKE2b (RFC 7693): a hash of 1 to 64 bytes, keyed or not, which Argon2 is built on. The size is
 * chosen at the start; the key, if there is one, is a secret of up to 64 bytes.
 *
 *     digest : u8[32]
 *     _ = crypto.blake2b(message, digest)
 *
 *     hasher := crypto.blake2b_start_keyed(32, key) or_return false
 *     crypto.blake2b_update(&hasher, message)
 *     crypto.blake2b_finish(&hasher, digest)
 *
 * Blocks are compressed four words at a time with AVX2, when the hasher's wide says so; a kernel without
 * vector state sets it to false after starting.
 */

/** How many bytes a BLAKE2b block has: what's hashed is compressed this many bytes at a time. */
BLAKE2B_BLOCK :: 128

/** The chaining words and the block being filled, which hold what was hashed and the key, so they're secrets. */
Blake2bState :: struct #secret {
    /** The eight 64-bit chaining words, h, which become the digest. */
    words: u64[8],
    /** The block being filled, compressed into the words once more comes after it. */
    block: u8[128],
}

/** A block's words, and the working words a compression mixes. */
Blake2bWords :: distinct alias u64[16] #secret
/** v's four rows, a vector of four words each, for compressing with AVX2. */
Blake2bRows :: distinct alias vector[u64, 4][4] #secret
/** The message words for four G at once, x then y. */
Blake2bMessageLanes :: distinct alias vector[u64, 4][2] #secret

/**
 * A BLAKE2b hash in progress, for what comes in parts: from blake2b_start or blake2b_start_keyed, fed with
 * blake2b_update, and ended with blake2b_finish.
 */
Blake2b :: struct {
    /** The chaining words and the block being filled, secret. */
    state: Blake2bState,
    /**
     * How many bytes of the block are filled, 0 to 128: a full block stays until more comes, since the last block is
     * compressed differently.
     */
    buffered: usize,
    /** How many bytes were compressed before the block, the low 64 bits of RFC 7693's counter t. */
    total: u64,
    /** The digest's size in bytes, 1 to 64, which is part of what's hashed. */
    size: usize,
    /**
     * Whether blocks are compressed with AVX2, as vectors_wide() says when it starts; a kernel without vector state
     * sets it to false.
     */
    wide: bool,
}

/** BLAKE2b's initialization vector (RFC 7693, section 2.6), the same as SHA-512's initial hash value. */
BLAKE2B_START :: u64.[
    0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
    0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
]

/**
 * Which of a block's words each round mixes, in order: ten permutations of 0 to 15 (RFC 7693, section 2.7), the
 * eleventh and twelfth rounds using the first two again.
 */
BLAKE2B_SIGMA :: usize.[
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3,
    11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4,
    7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8,
    9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13,
    2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9,
    12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11,
    13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10,
    6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5,
    10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0,
]

/**
 * Start an unkeyed BLAKE2b hash (RFC 7693).
 *
 * @param size The digest's size in bytes, 1 to 64. It's part of what's hashed, so a shorter digest isn't the start of
 *     a longer one.
 * @return The hasher, with wide set to whether AVX2 can be used, or None if size isn't 1 to 64.
 */
blake2b_start :: fn(size: usize) -> Blake2b? {
    return blake2b_start_keyed(size, as_secret(u8.[]))
}

/**
 * Start a keyed BLAKE2b hash (RFC 7693), which makes it a message authentication code.
 *
 * @param size The digest's size in bytes, 1 to 64. It's part of what's hashed, so a shorter digest isn't the start of
 *     a longer one.
 * @param key The key, up to 64 bytes; empty is the same as unkeyed. It's copied into the hasher's secret block, the
 *     first block hashed, padded with zeros.
 * @return The hasher, with wide set to whether AVX2 can be used, or None if size isn't 1 to 64 or the key is longer
 *     than 64 bytes.
 */
blake2b_start_keyed #constant_time :: fn(size: usize, key: SecretByte[]) -> Blake2b? {
    if size == 0 || size > 64 || key.count > 64 {
        return null
    }
    hasher := Blake2b.{size = size, wide = vectors_wide()}
    for i in 0..<8 {
        hasher.state.words[i] = BLAKE2B_START[i]
    }
    hasher.state.words[0] = hasher.state.words[0] ~ 0x0101_0000 ~ (cast[u64](key.count) << 8) ~ cast[u64](size)
    // The key is the first block, padded with zeros
    if key.count > 0 {
        for byte, i in key {
            hasher.state.block[i % BLAKE2B_BLOCK] = cast[u8](byte)
        }
        hasher.buffered = BLAKE2B_BLOCK
    }
    return hasher
}

/**
 * Mix four of the working words with two message words: BLAKE2b's G (RFC 7693, section 3.1).
 *
 * @param v The working words, four of which are mixed in place.
 * @param a The index in v, 0 to 15, of G's first word.
 * @param b The index in v of G's second word.
 * @param c The index in v of G's third word.
 * @param d The index in v of G's fourth word.
 * @param x The block's message words.
 * @param xi The index in x, 0 to 15, of the first message word, added in G's first half.
 * @param yi The index in x of the second message word, added in G's second half.
 */
blake2b_mix #constant_time :: fn(v: ptr[mut Blake2bWords], a: usize, b: usize, c: usize, d: usize, x: ptr[Blake2bWords],
    xi: usize, yi: usize) {

    v[a % 16] = v[a % 16] + v[b % 16] + x[xi % 16]
    v[d % 16] = intrinsics.rotate_right(v[d % 16] ~ v[a % 16], 32)
    v[c % 16] = v[c % 16] + v[d % 16]
    v[b % 16] = intrinsics.rotate_right(v[b % 16] ~ v[c % 16], 24)
    v[a % 16] = v[a % 16] + v[b % 16] + x[yi % 16]
    v[d % 16] = intrinsics.rotate_right(v[d % 16] ~ v[a % 16], 16)
    v[c % 16] = v[c % 16] + v[d % 16]
    v[b % 16] = intrinsics.rotate_right(v[b % 16] ~ v[c % 16], 63)
}

/**
 * Compress the state's block into its chaining words: BLAKE2b's F (RFC 7693, section 3.2).
 *
 * @param state The state; its block is read as 16 little-endian words, and its words updated.
 * @param total How many bytes have been hashed with this block included, its last block's padding not counted.
 * @param last Whether it's the last block, which is compressed differently.
 * @param wide Whether to use AVX2, which only an x86-64 CPU that has it may be told; on other targets it's ignored.
 */
blake2b_compress #constant_time :: fn(state: ptr[mut Blake2bState], total: u64, last: bool, wide: bool) {
    m : Blake2bWords
    for i in 0..<16 {
        word := compiler.secret(cast[u64](0))
        for j in 0..<8 {
            word = word | (cast[u64](state.block[8 * i + j]) << (8 * cast[u64](j)))
        }
        m[i] = word
    }
    blake2b_compress_words(state, &m, total, last, wide)
}

/**
 * Compress a block, already read as words, into the state's chaining words: with AVX2 when wide says so, otherwise in
 * software.
 *
 * @param state The state; only its words are used and updated.
 * @param m The block's 16 little-endian words.
 * @param total How many bytes have been hashed with this block included, its last block's padding not counted.
 * @param last Whether it's the last block, which is compressed differently.
 * @param wide Whether to use AVX2, which only an x86-64 CPU that has it may be told; on other targets it's ignored.
 */
blake2b_compress_words #constant_time :: fn(state: ptr[mut Blake2bState], m: ptr[Blake2bWords], total: u64, last: bool,
    wide: bool) {

    #if TARGET_ARCH == .x86_64 {
        if wide {
            blake2b_compress_wide(state, m, total, last)
            return void
        }
    }
    v : Blake2bWords
    for i in 0..<8 {
        v[i] = state.words[i]
        v[i + 8] = BLAKE2B_START[i]
    }
    v[12] = v[12] ~ total
    if last {
        v[14] = ~v[14]
    }
    for round in 0..<12 {
        s := (round % 10) * 16
        blake2b_mix(&v, 0, 4, 8, 12, m, BLAKE2B_SIGMA[s % 160], BLAKE2B_SIGMA[(s + 1) % 160])
        blake2b_mix(&v, 1, 5, 9, 13, m, BLAKE2B_SIGMA[(s + 2) % 160], BLAKE2B_SIGMA[(s + 3) % 160])
        blake2b_mix(&v, 2, 6, 10, 14, m, BLAKE2B_SIGMA[(s + 4) % 160], BLAKE2B_SIGMA[(s + 5) % 160])
        blake2b_mix(&v, 3, 7, 11, 15, m, BLAKE2B_SIGMA[(s + 6) % 160], BLAKE2B_SIGMA[(s + 7) % 160])
        blake2b_mix(&v, 0, 5, 10, 15, m, BLAKE2B_SIGMA[(s + 8) % 160], BLAKE2B_SIGMA[(s + 9) % 160])
        blake2b_mix(&v, 1, 6, 11, 12, m, BLAKE2B_SIGMA[(s + 10) % 160], BLAKE2B_SIGMA[(s + 11) % 160])
        blake2b_mix(&v, 2, 7, 8, 13, m, BLAKE2B_SIGMA[(s + 12) % 160], BLAKE2B_SIGMA[(s + 13) % 160])
        blake2b_mix(&v, 3, 4, 9, 14, m, BLAKE2B_SIGMA[(s + 14) % 160], BLAKE2B_SIGMA[(s + 15) % 160])
    }
    for i in 0..<8 {
        state.words[i] = state.words[i] ~ v[i] ~ v[i + 8]
    }
}

#if TARGET_ARCH == .x86_64 {
    /**
     * Gather the message words for four of a round's G at once.
     *
     * @param lanes Where they go: x, from sigma's k, k + 2, k + 4 and k + 6, then y, from the ones after those.
     * @param m The block's 16 message words.
     * @param s Where the round's permutation starts in BLAKE2B_SIGMA: 16 times the round, modulo 10.
     * @param k Which G of the round's eight start the four, times two: 0 for the columns, 8 for the diagonals.
     */
    blake2b_message_lanes #constant_time #target_features("avx2") :: fn(lanes: ptr[mut Blake2bMessageLanes], m: ptr[Blake2bWords],
        s: usize, k: usize) {

        for xy in cast[usize](0)..<2 {
            lanes[xy] = vector[u64, 4].{m[BLAKE2B_SIGMA[(s + k + xy) % 160] % 16], m[BLAKE2B_SIGMA[(s + k + xy + 2) % 160] % 16],
                m[BLAKE2B_SIGMA[(s + k + xy + 4) % 160] % 16], m[BLAKE2B_SIGMA[(s + k + xy + 6) % 160] % 16]}
        }
    }

    /**
     * Do G on each of the rows' four columns at once, with AVX2.
     *
     * @param r The working words as four rows of four, mixed in place.
     * @param m The block's 16 message words.
     * @param s Where the round's permutation starts in BLAKE2B_SIGMA: 16 times the round, modulo 10.
     * @param k Which G of the round's eight start the four, times two: 0 for the columns, 8 for the diagonals.
     */
    blake2b_mix_rows #constant_time #target_features("avx2") :: fn(r: ptr[mut Blake2bRows], m: ptr[Blake2bWords], s: usize, k: usize) {
        lanes : Blake2bMessageLanes
        blake2b_message_lanes(&lanes, m, s, k)
        r[0] = r[0] + r[1] + lanes[0]
        r[3] = intrinsics.rotate_right(r[3] ~ r[0], 32)
        r[2] = r[2] + r[3]
        r[1] = intrinsics.rotate_right(r[1] ~ r[2], 24)
        r[0] = r[0] + r[1] + lanes[1]
        r[3] = intrinsics.rotate_right(r[3] ~ r[0], 16)
        r[2] = r[2] + r[3]
        r[1] = intrinsics.rotate_right(r[1] ~ r[2], 63)
    }

    /**
     * Compress a block into the state's chaining words with AVX2: G on the rows' columns, then the rows turned so the
     * diagonals are columns, G again, and turned back.
     *
     * @param state The state; only its words are used and updated.
     * @param m The block's 16 little-endian words.
     * @param total How many bytes have been hashed with this block included, its last block's padding not counted.
     * @param last Whether it's the last block, which is compressed differently. The CPU has to have AVX2, as
     *     vectors_wide says.
     */
    blake2b_compress_wide #constant_time #target_features("avx2") :: fn(state: ptr[mut Blake2bState], m: ptr[Blake2bWords], total: u64,
        last: bool) {

        r : Blake2bRows
        r[0] = vector[u64, 4].{state.words[0], state.words[1], state.words[2], state.words[3]}
        r[1] = vector[u64, 4].{state.words[4], state.words[5], state.words[6], state.words[7]}
        r[2] = vector[u64, 4].{BLAKE2B_START[0], BLAKE2B_START[1], BLAKE2B_START[2], BLAKE2B_START[3]}
        final : u64 = 0
        if last {
            final = ~final
        }
        r[3] = vector[u64, 4].{BLAKE2B_START[4] ~ total, BLAKE2B_START[5], BLAKE2B_START[6] ~ final, BLAKE2B_START[7]}
        for round in cast[usize](0)..<12 {
            s := (round % 10) * 16
            blake2b_mix_rows(&r, m, s, 0)
            r[1] = intrinsics.rotate_lanes(r[1], 1)
            r[2] = intrinsics.rotate_lanes(r[2], 2)
            r[3] = intrinsics.rotate_lanes(r[3], 3)
            blake2b_mix_rows(&r, m, s, 8)
            r[1] = intrinsics.rotate_lanes(r[1], 3)
            r[2] = intrinsics.rotate_lanes(r[2], 2)
            r[3] = intrinsics.rotate_lanes(r[3], 1)
        }
        low := bit_cast[u64[4]](r[0] ~ r[2])
        high := bit_cast[u64[4]](r[1] ~ r[3])
        for i in 0..<4 {
            state.words[i] = state.words[i] ~ low[i]
            state.words[i + 4] = state.words[i + 4] ~ high[i]
        }
    }
}

/**
 * Add public bytes to what a BLAKE2b hasher hashes.
 *
 * @param hasher The hasher, not yet finished.
 * @param data The next bytes, of any number, none included; they're hashed, not kept.
 */
blake2b_update :: fn(hasher: ptr[mut Blake2b], data: u8[]) {
    blake2b_absorb(hasher, data)
}

/**
 * Add secret bytes to what a BLAKE2b hasher hashes, in constant time.
 *
 * @param hasher The hasher, not yet finished.
 * @param data The next bytes, of any number; how many isn't secret, what they are is.
 */
blake2b_update_secret #constant_time :: fn(hasher: ptr[mut Blake2b], data: SecretByte[]) {
    blake2b_absorb(hasher, data)
}

/**
 * Add bytes to what a BLAKE2b hasher hashes: into the block until it's full, then whole blocks straight from data
 * while more comes after them, since the last block is compressed differently, then the rest into the block.
 *
 * @tparam T The bytes' type: u8 or SecretByte.
 * @param hasher The hasher, not yet finished.
 * @param data The bytes, of any number.
 */
blake2b_absorb :: fn[T](hasher: ptr[mut Blake2b], data: T[]) {
    at : usize = 0
    loop {
        if hasher.buffered == BLAKE2B_BLOCK {
            hasher.total += BLAKE2B_BLOCK
            blake2b_compress(&hasher.state, hasher.total, false, hasher.wide)
            hasher.buffered = 0
            loop {
                m : Blake2bWords
                for i in cast[usize](0)..<16 {
                    word := compiler.secret(cast[u64](0))
                    for j in cast[usize](0)..<8 {
                        word = word | (cast[u64](cast[u8](data[at + 8 * i + j])) << (8 * cast[u64](j)))
                    }
                    m[i] = word
                }
                hasher.total += BLAKE2B_BLOCK
                blake2b_compress_words(&hasher.state, &m, hasher.total, false, hasher.wide)
                at += BLAKE2B_BLOCK
            }
            while at + BLAKE2B_BLOCK < data.count
        }
        hasher.state.block[hasher.buffered % BLAKE2B_BLOCK] = cast[u8](data[at])
        hasher.buffered += 1
        at += 1
    }
    while at < data.count
}

/**
 * Finish a BLAKE2b hash, keeping the digest a secret.
 *
 * @param hasher The hasher, after fewer than 2^64 bytes in all. It's spent afterwards: it can't be updated or
 *     finished again, and its state isn't wiped.
 * @param output Where the digest goes: its first size bytes, or as many as it has. Bytes past the size are left as
 *     they were.
 */
blake2b_finish_secret #constant_time :: fn(hasher: ptr[mut Blake2b], output: mut SecretByte[]) {
    hasher.total += cast[u64](hasher.buffered)
    for i in hasher.buffered..<BLAKE2B_BLOCK {
        hasher.state.block[i] = 0
    }
    blake2b_compress(&hasher.state, hasher.total, true, hasher.wide)
    for i in 0..<output.count {
        if i < hasher.size {
            output[i] = cast[SecretByte](hasher.state.words[(i / 8) % 8] >> (8 * cast[u64](i % 8)))
        }
    }
}

/**
 * Finish a BLAKE2b hash.
 *
 * @param hasher The hasher, after fewer than 2^64 bytes in all. It's spent afterwards: it can't be updated or
 *     finished again, and its state isn't wiped.
 * @param output Where the digest goes, which should have the size the hasher was started with: a shorter one gets
 *     the digest's first bytes, and a longer one zeros after it, however long it is.
 */
blake2b_finish :: fn(hasher: ptr[mut Blake2b], output: mut u8[]) {
    digest : SecretByte[64]
    blake2b_finish_secret(hasher, digest)
    for i in 0..<output.count {
        output[i] = if i < digest.count { compiler.declassify(digest[i]) } else { cast[u8](0) }
    }
}

/**
 * Hash bytes with unkeyed BLAKE2b (RFC 7693), when they're all at hand.
 *
 * @param data The bytes, of any number, none included.
 * @param output Where the digest goes; its count, 1 to 64, is the digest's size, which is part of what's hashed.
 * @return True with output filled, or false, with nothing written, if output's count isn't 1 to 64.
 */
blake2b :: fn(data: u8[], output: mut u8[]) -> bool {
    hasher := blake2b_start(output.count) or_return false
    blake2b_update(&hasher, data)
    blake2b_finish(&hasher, output)
    return true
}
