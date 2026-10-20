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
 */

BLAKE2B_BLOCK :: 128

Blake2bState :: struct #secret {
    words: u64[8],
    block: u8[128],
}

// A block's words, and the working words a compression mixes.
Blake2bWords :: distinct alias u64[16] #secret

Blake2b :: struct {
    state: Blake2bState,
    // How much of block is filled, how many bytes were compressed before it, and the digest's size
    buffered: usize,
    total: u64,
    size: usize,
}

BLAKE2B_START :: u64.[
    0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
    0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
]

// Which of a block's words each round mixes, in order.
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

// A hasher for a digest of size bytes, from 1 to 64, or null for another size.
blake2b_start :: fn(size: usize) -> Blake2b? {
    return blake2b_start_keyed(size, as_secret(u8.[]))
}

// A keyed hasher, for a key of up to 64 bytes, or null for a longer one or a size that isn't 1 to 64.
blake2b_start_keyed #constant_time :: fn(size: usize, key: SecretByte[]) -> Blake2b? {
    if size == 0 || size > 64 || key.count > 64 {
        return null
    }
    hasher := Blake2b.{size = size}
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

// The block into the words, with how many bytes there have been, and whether it's the last.
blake2b_compress #constant_time :: fn(state: ptr[mut Blake2bState], total: u64, last: bool) {
    m : Blake2bWords
    for i in 0..<16 {
        word := compiler.secret(cast[u64](0))
        for j in 0..<8 {
            word = word | (cast[u64](state.block[8 * i + j]) << (8 * cast[u64](j)))
        }
        m[i] = word
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
        blake2b_mix(&v, 0, 4, 8, 12, &m, BLAKE2B_SIGMA[s % 160], BLAKE2B_SIGMA[(s + 1) % 160])
        blake2b_mix(&v, 1, 5, 9, 13, &m, BLAKE2B_SIGMA[(s + 2) % 160], BLAKE2B_SIGMA[(s + 3) % 160])
        blake2b_mix(&v, 2, 6, 10, 14, &m, BLAKE2B_SIGMA[(s + 4) % 160], BLAKE2B_SIGMA[(s + 5) % 160])
        blake2b_mix(&v, 3, 7, 11, 15, &m, BLAKE2B_SIGMA[(s + 6) % 160], BLAKE2B_SIGMA[(s + 7) % 160])
        blake2b_mix(&v, 0, 5, 10, 15, &m, BLAKE2B_SIGMA[(s + 8) % 160], BLAKE2B_SIGMA[(s + 9) % 160])
        blake2b_mix(&v, 1, 6, 11, 12, &m, BLAKE2B_SIGMA[(s + 10) % 160], BLAKE2B_SIGMA[(s + 11) % 160])
        blake2b_mix(&v, 2, 7, 8, 13, &m, BLAKE2B_SIGMA[(s + 12) % 160], BLAKE2B_SIGMA[(s + 13) % 160])
        blake2b_mix(&v, 3, 4, 9, 14, &m, BLAKE2B_SIGMA[(s + 14) % 160], BLAKE2B_SIGMA[(s + 15) % 160])
    }
    for i in 0..<8 {
        state.words[i] = state.words[i] ~ v[i] ~ v[i + 8]
    }
}

// A full block is only compressed once more comes, since the last one is compressed differently.
blake2b_byte :: fn(hasher: ptr[mut Blake2b], byte: u8) {
    if hasher.buffered == BLAKE2B_BLOCK {
        hasher.total += BLAKE2B_BLOCK
        blake2b_compress(&hasher.state, hasher.total, false)
        hasher.buffered = 0
    }
    hasher.state.block[hasher.buffered % BLAKE2B_BLOCK] = byte
    hasher.buffered += 1
}

blake2b_update :: fn(hasher: ptr[mut Blake2b], data: u8[]) {
    for byte in data {
        blake2b_byte(hasher, byte)
    }
}

blake2b_update_secret #constant_time :: fn(hasher: ptr[mut Blake2b], data: SecretByte[]) {
    for byte in data {
        if hasher.buffered == BLAKE2B_BLOCK {
            hasher.total += BLAKE2B_BLOCK
            blake2b_compress(&hasher.state, hasher.total, false)
            hasher.buffered = 0
        }
        hasher.state.block[hasher.buffered % BLAKE2B_BLOCK] = cast[u8](byte)
        hasher.buffered += 1
    }
}

// The digest, its size's worth of output's bytes, or as many as fit.
blake2b_finish_secret #constant_time :: fn(hasher: ptr[mut Blake2b], output: mut SecretByte[]) {
    hasher.total += cast[u64](hasher.buffered)
    for i in hasher.buffered..<BLAKE2B_BLOCK {
        hasher.state.block[i] = 0
    }
    blake2b_compress(&hasher.state, hasher.total, true)
    for i in 0..<output.count {
        if i < hasher.size {
            output[i] = cast[SecretByte](hasher.state.words[(i / 8) % 8] >> (8 * cast[u64](i % 8)))
        }
    }
}

blake2b_finish :: fn(hasher: ptr[mut Blake2b], output: mut u8[]) {
    digest : SecretByte[64]
    blake2b_finish_secret(hasher, digest)
    for i in 0..<output.count {
        output[i] = compiler.declassify(digest[i % 64])
    }
}

// A digest of output's size, from 1 to 64 bytes, or false for another size.
blake2b :: fn(data: u8[], output: mut u8[]) -> bool {
    hasher := blake2b_start(output.count) or_return false
    blake2b_update(&hasher, data)
    blake2b_finish(&hasher, output)
    return true
}
