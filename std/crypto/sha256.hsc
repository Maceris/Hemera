package crypto

import compiler from "base"
import intrinsics from "base"

/*
 * SHA-256 (FIPS 180-4). One call for what's all at hand, or a hasher for what comes in parts:
 *
 *     digest :: crypto.sha256(message)
 *
 *     hasher := crypto.sha256_start()
 *     crypto.sha256_update(&hasher, header)
 *     crypto.sha256_update(&hasher, body)
 *     digest :: crypto.sha256_finish(&hasher)
 *
 * What's hashed can be a secret, given with sha256_update_secret, and the digest kept one with
 * sha256_finish_secret, as HMAC and HKDF do. How many bytes there are is never a secret.
 */

SHA256_SIZE :: 32
SHA256_BLOCK :: 64

// The words and the block being filled, which hold what was hashed, so they're secrets.
Sha256State :: struct #secret {
    words: u32[8],
    block: u8[64],
}

// Sha256State's schedule, worked out from a block.
Sha256Schedule :: distinct alias u32[64] #secret

Sha256 :: struct {
    state: Sha256State,
    // How much of block is filled, and how many bytes there have been in all
    buffered: usize,
    total: u64,
}

SHA256_ROUND :: u32.[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]

SHA256_START :: u32.[0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]

sha256_start :: fn() -> Sha256 {
    hasher := Sha256.{}
    for i in 0..<8 {
        hasher.state.words[i] = SHA256_START[i]
    }
    return hasher
}

// One block into the words.
sha256_compress #constant_time :: fn(state: ptr[mut Sha256State]) {
    w : Sha256Schedule
    for i in 0..<16 {
        w[i] = (cast[u32](state.block[4 * i]) << 24) | (cast[u32](state.block[4 * i + 1]) << 16)
            | (cast[u32](state.block[4 * i + 2]) << 8) | cast[u32](state.block[4 * i + 3])
    }
    for i in 16..<64 {
        s0 := intrinsics.rotate_right(w[i - 15], 7) ~ intrinsics.rotate_right(w[i - 15], 18) ~ (w[i - 15] >> 3)
        s1 := intrinsics.rotate_right(w[i - 2], 17) ~ intrinsics.rotate_right(w[i - 2], 19) ~ (w[i - 2] >> 10)
        w[i] = w[i - 16] + s0 + w[i - 7] + s1
    }
    a := state.words[0]
    b := state.words[1]
    c := state.words[2]
    d := state.words[3]
    e := state.words[4]
    f := state.words[5]
    g := state.words[6]
    h := state.words[7]
    for i in 0..<64 {
        s1 := intrinsics.rotate_right(e, 6) ~ intrinsics.rotate_right(e, 11) ~ intrinsics.rotate_right(e, 25)
        choose := (e & f) ~ (~e & g)
        t1 := h + s1 + choose + SHA256_ROUND[i] + w[i]
        s0 := intrinsics.rotate_right(a, 2) ~ intrinsics.rotate_right(a, 13) ~ intrinsics.rotate_right(a, 22)
        majority := (a & b) ~ (a & c) ~ (b & c)
        t2 := s0 + majority
        h = g
        g = f
        f = e
        e = d + t1
        d = c
        c = b
        b = a
        a = t1 + t2
    }
    state.words[0] += a
    state.words[1] += b
    state.words[2] += c
    state.words[3] += d
    state.words[4] += e
    state.words[5] += f
    state.words[6] += g
    state.words[7] += h
}

// One byte into the block, compressing it once it's full. total doesn't count it: the caller adds it.
sha256_byte :: fn(hasher: ptr[mut Sha256], byte: u8) {
    hasher.state.block[hasher.buffered % SHA256_BLOCK] = byte
    hasher.buffered += 1
    if hasher.buffered == SHA256_BLOCK {
        sha256_compress(&hasher.state)
        hasher.buffered = 0
    }
}

sha256_update :: fn(hasher: ptr[mut Sha256], data: u8[]) {
    for byte in data {
        sha256_byte(hasher, byte)
    }
    hasher.total += cast[u64](data.count)
}

sha256_update_secret #constant_time :: fn(hasher: ptr[mut Sha256], data: SecretByte[]) {
    for byte in data {
        hasher.state.block[hasher.buffered % SHA256_BLOCK] = cast[u8](byte)
        hasher.buffered += 1
        if hasher.buffered == SHA256_BLOCK {
            sha256_compress(&hasher.state)
            hasher.buffered = 0
        }
    }
    hasher.total += cast[u64](data.count)
}

// The padding and length, then the words, as a secret.
sha256_finish_secret #constant_time :: fn(hasher: ptr[mut Sha256]) -> SecretByte[32] {
    bits := hasher.total * 8
    sha256_byte(hasher, 0x80)
    loop {
        sha256_byte(hasher, 0)
    }
    while hasher.buffered != 56
    for i in 0..<8 {
        sha256_byte(hasher, cast[u8](bits >> (56 - 8 * cast[u64](i))))
    }
    digest : SecretByte[32]
    for i in 0..<8 {
        word := hasher.state.words[i]
        digest[4 * i] = cast[SecretByte](word >> 24)
        digest[4 * i + 1] = cast[SecretByte](word >> 16)
        digest[4 * i + 2] = cast[SecretByte](word >> 8)
        digest[4 * i + 3] = cast[SecretByte](word)
    }
    return digest
}

sha256_finish :: fn(hasher: ptr[mut Sha256]) -> u8[32] {
    secret := sha256_finish_secret(hasher)
    digest : u8[32]
    for i in 0..<32 {
        digest[i] = compiler.declassify(secret[i])
    }
    return digest
}

sha256 :: fn(data: u8[]) -> u8[32] {
    hasher := sha256_start()
    sha256_update(&hasher, data)
    return sha256_finish(&hasher)
}
