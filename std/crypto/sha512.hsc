package crypto

import compiler from "base"
import intrinsics from "base"

/*
 * SHA-512 (FIPS 180-4), like SHA-256 (see sha256.hsc) with 64-bit words, 128-byte blocks and 80 rounds.
 * Ed25519 is defined with it.
 */

/** How many bytes a SHA-512 digest has. */
SHA512_SIZE :: 64
/** How many bytes a SHA-512 block has: what's hashed is compressed this many bytes at a time. */
SHA512_BLOCK :: 128

/** The words and the block being filled, which hold what was hashed, so they're secrets. */
Sha512State :: struct #secret {
    /** The eight 64-bit chaining words, H0 to H7, which become the digest. */
    words: u64[8],
    /** The block being filled, compressed into the words once it's full. */
    block: u8[128],
}

/** A block's schedule of 80 words, each with its round's constant added. */
Sha512Schedule :: distinct alias u64[80] #secret

/** A compression's eight working words, a to h, then b ~ c, which the next round's majority uses. */
Sha512Working :: distinct alias u64[9] #secret

/**
 * A SHA-512 hash in progress, for what comes in parts: from sha512_start, fed with sha512_update, and ended with
 * sha512_finish.
 */
Sha512 :: struct {
    /** The chaining words and the block being filled, secret. */
    state: Sha512State,
    /** How many bytes of the block are filled, 0 to 127. */
    buffered: usize,
    /** How many bytes have been hashed in all, which the padding ends with, in bits. */
    total: u64,
}

/** SHA-512's 80 round constants, K0 to K79 (FIPS 180-4, section 4.2.3). */
SHA512_ROUND :: u64.[
    0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc, 0x3956c25bf348b538,
    0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118, 0xd807aa98a3030242, 0x12835b0145706fbe,
    0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2, 0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235,
    0xc19bf174cf692694, 0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
    0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5, 0x983e5152ee66dfab,
    0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4, 0xc6e00bf33da88fc2, 0xd5a79147930aa725,
    0x06ca6351e003826f, 0x142929670a0e6e70, 0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed,
    0x53380d139d95b3df, 0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
    0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30, 0xd192e819d6ef5218,
    0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8, 0x19a4c116b8d2d0c8, 0x1e376c085141ab53,
    0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8, 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373,
    0x682e6ff3d6b2b8a3, 0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
    0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b, 0xca273eceea26619c,
    0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178, 0x06f067aa72176fba, 0x0a637dc5a2c898a6,
    0x113f9804bef90dae, 0x1b710b35131c471b, 0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc,
    0x431d67c49c100d4c, 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
]

/** SHA-512's initial hash value, H0 to H7 (FIPS 180-4, section 5.3.5). */
SHA512_START :: u64.[
    0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
    0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
]

/**
 * Start a SHA-512 hash (FIPS 180-4).
 *
 * @return The hasher, with nothing hashed yet.
 */
sha512_start :: fn() -> Sha512 {
    hasher := Sha512.{}
    for i in 0..<8 {
        hasher.state.words[i] = SHA512_START[i]
    }
    return hasher
}

/**
 * Compress the state's block into its chaining words.
 *
 * @param state The state, its block full; its words are updated, and its block left as it was.
 */
sha512_compress #constant_time :: fn(state: ptr[mut Sha512State]) {
    w : Sha512Schedule
    for i in 0..<16 {
        word := compiler.secret(cast[u64](0))
        for j in 0..<8 {
            word = (word << 8) | cast[u64](state.block[8 * i + j])
        }
        w[i] = word
    }
    sha512_compress_words(state, &w)
}

/**
 * Compress a block, already read as words, into the state's chaining words (FIPS 180-4, section 6.4.2).
 *
 * @param state The state; only its words are used and updated.
 * @param w The block's 16 big-endian words in its first 16; the rest of the schedule is worked out in it, so it's
 *     overwritten.
 */
sha512_compress_words #constant_time :: fn(state: ptr[mut Sha512State], w: ptr[mut Sha512Schedule]) {
    sha512_schedule(w)
    v : Sha512Working
    for i in 0..<8 {
        v[i] = state.words[i]
    }
    v[8] = v[1] ~ v[2]
    // Eight rounds a time, each one's words a slot further round, so they're renamed rather than moved
    for i in cast[usize](0)..<10 {
        at := 8 * i
        sha512_round(&v, 0, w, at + 0)
        sha512_round(&v, 1, w, at + 1)
        sha512_round(&v, 2, w, at + 2)
        sha512_round(&v, 3, w, at + 3)
        sha512_round(&v, 4, w, at + 4)
        sha512_round(&v, 5, w, at + 5)
        sha512_round(&v, 6, w, at + 6)
        sha512_round(&v, 7, w, at + 7)
    }
    for i in 0..<8 {
        state.words[i] += v[i]
    }
}

/**
 * Do one round of SHA-512's compression, with the working words renamed rather than moved.
 *
 * a is v's word at (8 - r) % 8, b the one after, and so on, so the round only writes the two words it changes,
 * e = d + t1 into d's place and a = t1 + t2 into h's, and the next round reads one place back.
 *
 * @param v The working words, a to h in the rotation r says, then b ~ c in v[8], which this round's a ~ b becomes
 *     for the next.
 * @param r Which round of eight this is, 0 to 7, which says where a is in v.
 * @param w The block's schedule, each word with its round's constant added, as sha512_schedule leaves it.
 * @param i The round's number, 0 to 79, for its schedule word.
 */
sha512_round #constant_time :: fn(v: ptr[mut Sha512Working], r: usize, w: ptr[Sha512Schedule], i: usize) {
    a := v[(8 - r) % 8]
    b := v[(9 - r) % 8]
    e := v[(12 - r) % 8]
    f := v[(13 - r) % 8]
    g := v[(14 - r) % 8]
    h := v[(15 - r) % 8]
    s1 := intrinsics.rotate_right(e, 14) ~ intrinsics.rotate_right(e, 18) ~ intrinsics.rotate_right(e, 41)
    // e's bits choose f's, otherwise g's: and, and BMI2's andn, with nothing copied first
    choose := (e & f) ~ (~e & g)
    t1 := h + s1 + choose + w[i % 80]
    /*
     * a rotated by 28, 34 and 39, as one chain: 39 is 5 + 6 + 28 and 34 is 6 + 28. Written unlike s1, so the
     * optimizer doesn't pair the two into vectors, which can't rotate 64-bit lanes and are slower here.
     */
    s0 := intrinsics.rotate_right(a ~ intrinsics.rotate_right(a ~ intrinsics.rotate_right(a, 5), 6), 28)
    // Each bit as most of a's, b's and c's are: b's, unless a's and c's both differ from it
    a_b := a ~ b
    majority := b ~ (a_b & v[8])
    v[8] = a_b
    v[(11 - r) % 8] = v[(11 - r) % 8] + t1
    v[(15 - r) % 8] = t1 + s0 + majority
}

/**
 * Work out a block's schedule: w's other 64 words from its first 16, then each round's constant added to its word,
 * so a round reads one value rather than two.
 *
 * @param w The schedule, the block's 16 big-endian words in its first 16; all 80 are written.
 */
sha512_schedule #constant_time :: fn(w: ptr[mut Sha512Schedule]) {
    for i in 16..<80 {
        s0 := intrinsics.rotate_right(w[i - 15], 1) ~ intrinsics.rotate_right(w[i - 15], 8) ~ (w[i - 15] >> 7)
        s1 := intrinsics.rotate_right(w[i - 2], 19) ~ intrinsics.rotate_right(w[i - 2], 61) ~ (w[i - 2] >> 6)
        w[i] = w[i - 16] + s0 + w[i - 7] + s1
    }
    for i in 0..<80 {
        w[i] = w[i] + SHA512_ROUND[i]
    }
}

/**
 * Add one byte to the block, compressing it once it's full.
 *
 * @param hasher The hasher. Its total doesn't count the byte: the caller adds it, as padding isn't counted.
 * @param byte Any byte, message or padding, put in the block's next free position.
 */
sha512_byte :: fn(hasher: ptr[mut Sha512], byte: u8) {
    hasher.state.block[hasher.buffered % SHA512_BLOCK] = byte
    hasher.buffered += 1
    if hasher.buffered == SHA512_BLOCK {
        sha512_compress(&hasher.state)
        hasher.buffered = 0
    }
}

/**
 * Add public bytes to what a SHA-512 hasher hashes.
 *
 * @param hasher The hasher, not yet finished.
 * @param data The next bytes, of any number, none included; they're hashed, not kept.
 */
sha512_update :: fn(hasher: ptr[mut Sha512], data: u8[]) {
    sha512_absorb(hasher, as_secret(data))
}

/**
 * Add secret bytes to what a SHA-512 hasher hashes, in constant time.
 *
 * @param hasher The hasher, not yet finished.
 * @param data The next bytes, of any number; how many isn't secret, what they are is.
 */
sha512_update_secret #constant_time :: fn(hasher: ptr[mut Sha512], data: SecretByte[]) {
    sha512_absorb(hasher, data)
}

/**
 * Add bytes to what a SHA-512 hasher hashes: a block already started is filled a byte at a time, then whole blocks
 * are compressed straight from data, then the rest is buffered.
 *
 * @param hasher The hasher, not yet finished; its total grows by data's count.
 * @param data The bytes, of any number.
 */
sha512_absorb #constant_time :: fn(hasher: ptr[mut Sha512], data: SecretByte[]) {
    at : usize = 0
    loop {
        hasher.state.block[hasher.buffered % SHA512_BLOCK] = cast[u8](data[at])
        hasher.buffered += 1
        at += 1
        if hasher.buffered == SHA512_BLOCK {
            sha512_compress(&hasher.state)
            hasher.buffered = 0
        }
    }
    while hasher.buffered != 0 && at < data.count
    // Whole blocks' words straight from data
    loop {
        w : Sha512Schedule
        for i in cast[usize](0)..<16 {
            word := compiler.secret(cast[u64](0))
            for j in cast[usize](0)..<8 {
                word = (word << 8) | cast[u64](data[at + 8 * i + j])
            }
            w[i] = word
        }
        sha512_compress_words(&hasher.state, &w)
        at += SHA512_BLOCK
    }
    while at + SHA512_BLOCK <= data.count
    loop {
        hasher.state.block[hasher.buffered % SHA512_BLOCK] = cast[u8](data[at])
        hasher.buffered += 1
        at += 1
    }
    while at < data.count
    hasher.total += cast[u64](data.count)
}

/**
 * Finish a SHA-512 hash, keeping the digest a secret: the padding and the length in bits, as 128 bits of which the
 * high 64 are 0, are added, then the words are the digest.
 *
 * @param hasher The hasher, after fewer than 2^61 bytes in all. It's spent afterwards: it can't be updated or
 *     finished again, and its state isn't wiped.
 * @return The 64-byte digest, big-endian words, as a secret.
 */
sha512_finish_secret #constant_time :: fn(hasher: ptr[mut Sha512]) -> SecretByte[64] {
    bits := hasher.total * 8
    sha512_byte(hasher, 0x80)
    // Zeros up to the 16 bytes the length takes at the end of a block, a new one if they don't fit
    loop {
        sha512_byte(hasher, 0)
    }
    while hasher.buffered != 112
    for i in 0..<8 {
        sha512_byte(hasher, 0)
    }
    for i in 0..<8 {
        sha512_byte(hasher, cast[u8](bits >> (56 - 8 * cast[u64](i))))
    }
    digest : SecretByte[64]
    for i in 0..<8 {
        word := hasher.state.words[i]
        for j in 0..<8 {
            digest[8 * i + j] = cast[SecretByte](word >> (56 - 8 * cast[u64](j)))
        }
    }
    return digest
}

/**
 * Finish a SHA-512 hash.
 *
 * @param hasher The hasher, after fewer than 2^61 bytes in all. It's spent afterwards: it can't be updated or
 *     finished again.
 * @return The 64-byte digest, public.
 */
sha512_finish :: fn(hasher: ptr[mut Sha512]) -> u8[64] {
    secret := sha512_finish_secret(hasher)
    digest : u8[64]
    for i in 0..<64 {
        digest[i] = compiler.declassify(secret[i])
    }
    return digest
}

/**
 * Hash bytes with SHA-512 (FIPS 180-4), when they're all at hand.
 *
 * @param data The bytes, of any number, none included.
 * @return The 64-byte digest.
 */
sha512 :: fn(data: u8[]) -> u8[64] {
    hasher := sha512_start()
    sha512_update(&hasher, data)
    return sha512_finish(&hasher)
}
