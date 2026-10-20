package crypto

import compiler from "base"
import intrinsics from "base"

/*
 * ChaCha20-Poly1305 (RFC 8439): encryption with a 32-byte key and a 12-byte nonce, which must never
 * be used twice with one key, and a 16-byte tag that says the ciphertext and the associated data, like
 * a header sent in the clear, are what was sealed.
 *
 *     _ = crypto.chacha20_poly1305_seal(&key, nonce, plaintext, header, ciphertext, &tag)
 *     if !crypto.chacha20_poly1305_open(&key, nonce, ciphertext, header, &tag, plaintext) {
 *         // forged or damaged: nothing was written
 *     }
 */

// A 32-byte key, for ChaCha20-Poly1305 or AES-256-GCM.
Key256 :: distinct alias u8[32] #secret
// A 12-byte nonce, used once per key.
Nonce96 :: distinct alias u8[12]
// A 16-byte tag.
Tag128 :: distinct alias u8[16]

ChaChaWords :: distinct alias u32[16] #secret

CHACHA_CONSTANTS :: u32.[0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]

chacha_quarter #constant_time :: fn(x: ptr[mut ChaChaWords], a: usize, b: usize, c: usize, d: usize) {
    x[a % 16] = x[a % 16] + x[b % 16]
    x[d % 16] = intrinsics.rotate_left(x[d % 16] ~ x[a % 16], 16)
    x[c % 16] = x[c % 16] + x[d % 16]
    x[b % 16] = intrinsics.rotate_left(x[b % 16] ~ x[c % 16], 12)
    x[a % 16] = x[a % 16] + x[b % 16]
    x[d % 16] = intrinsics.rotate_left(x[d % 16] ~ x[a % 16], 8)
    x[c % 16] = x[c % 16] + x[d % 16]
    x[b % 16] = intrinsics.rotate_left(x[b % 16] ~ x[c % 16], 7)
}

// One 64-byte block of keystream, as words.
chacha20_block #constant_time :: fn(key: ptr[Key256], counter: u32, nonce: ptr[Nonce96]) -> ChaChaWords {
    state : ChaChaWords
    for i in 0..<4 {
        state[i] = CHACHA_CONSTANTS[i]
    }
    for i in 0..<8 {
        word := compiler.secret(cast[u32](0))
        for j in 0..<4 {
            word = word | (cast[u32](key[4 * i + j]) << (8 * cast[u32](j)))
        }
        state[4 + i] = word
    }
    state[12] = counter
    for i in 0..<3 {
        word : u32 = 0
        for j in 0..<4 {
            word = word | (cast[u32](nonce[4 * i + j]) << (8 * cast[u32](j)))
        }
        state[13 + i] = word
    }
    x := state
    for round in 0..<10 {
        chacha_quarter(&x, 0, 4, 8, 12)
        chacha_quarter(&x, 1, 5, 9, 13)
        chacha_quarter(&x, 2, 6, 10, 14)
        chacha_quarter(&x, 3, 7, 11, 15)
        chacha_quarter(&x, 0, 5, 10, 15)
        chacha_quarter(&x, 1, 6, 11, 12)
        chacha_quarter(&x, 2, 7, 8, 13)
        chacha_quarter(&x, 3, 4, 9, 14)
    }
    for i in 0..<16 {
        x[i] = x[i] + state[i]
    }
    return x
}

// A keystream block's byte.
chacha_byte #constant_time :: fn(block: ptr[ChaChaWords], at: usize) -> SecretByte {
    return cast[SecretByte](block[(at / 4) % 16] >> (8 * cast[u32](at % 4)))
}

/*
 * Poly1305's state: the key's r, clamped, in 26-bit limbs, its s, the sum, and the block being filled,
 * all secrets.
 */
Poly1305State :: struct #secret {
    r: u32[5],
    s: u32[4],
    h: u32[5],
    block: u8[16],
}

Poly1305 :: struct {
    state: Poly1305State,
    buffered: usize,
}

Poly1305Key :: distinct alias u8[32] #secret

poly1305_start #constant_time :: fn(key: ptr[Poly1305Key]) -> Poly1305 {
    poly := Poly1305.{}
    poly.state.r[0] = cast[u32](loaded(key, 0)) & 0x3ff_ffff
    poly.state.r[1] = (cast[u32](loaded(key, 3)) >> 2) & 0x3ff_ff03
    poly.state.r[2] = (cast[u32](loaded(key, 6)) >> 4) & 0x3ff_c0ff
    poly.state.r[3] = (cast[u32](loaded(key, 9)) >> 6) & 0x3f0_3fff
    poly.state.r[4] = (cast[u32](loaded(key, 12)) >> 8) & 0x00f_ffff
    for i in 0..<4 {
        poly.state.s[i] = cast[u32](loaded(key, cast[usize](16 + 4 * i)))
    }
    return poly
}

// Four of a secret key's bytes, from at, as a little-endian word that's still a secret.
loaded #constant_time :: fn(bytes: ptr[Poly1305Key], at: usize) -> PolyWord {
    word := compiler.secret(cast[u32](0))
    for j in 0..<4 {
        word = word | (cast[u32](bytes[(at + cast[usize](j)) % 32]) << (8 * cast[u32](j)))
    }
    return cast[PolyWord](word)
}

PolyWord :: distinct alias u32 #secret

// The block into the sum: h = (h + block) * r, mod 2^130 - 5. high is 1 << 24 for a whole block.
poly1305_blocks #constant_time :: fn(state: ptr[mut Poly1305State], high: u32) {
    m0 := compiler.secret(cast[u32](0))
    m1 := compiler.secret(cast[u32](0))
    m2 := compiler.secret(cast[u32](0))
    m3 := compiler.secret(cast[u32](0))
    for j in 0..<4 {
        shift := 8 * cast[u32](j)
        m0 = m0 | (cast[u32](state.block[j]) << shift)
        m1 = m1 | (cast[u32](state.block[4 + j]) << shift)
        m2 = m2 | (cast[u32](state.block[8 + j]) << shift)
        m3 = m3 | (cast[u32](state.block[12 + j]) << shift)
    }
    h0 := state.h[0] + (m0 & 0x3ff_ffff)
    h1 := state.h[1] + (((m0 >> 26) | (m1 << 6)) & 0x3ff_ffff)
    h2 := state.h[2] + (((m1 >> 20) | (m2 << 12)) & 0x3ff_ffff)
    h3 := state.h[3] + (((m2 >> 14) | (m3 << 18)) & 0x3ff_ffff)
    h4 := state.h[4] + ((m3 >> 8) | high)
    r0 := cast[u64](state.r[0])
    r1 := cast[u64](state.r[1])
    r2 := cast[u64](state.r[2])
    r3 := cast[u64](state.r[3])
    r4 := cast[u64](state.r[4])
    s1 := r1 * 5
    s2 := r2 * 5
    s3 := r3 * 5
    s4 := r4 * 5
    d0 := cast[u64](h0) * r0 + cast[u64](h1) * s4 + cast[u64](h2) * s3 + cast[u64](h3) * s2 + cast[u64](h4) * s1
    d1 := cast[u64](h0) * r1 + cast[u64](h1) * r0 + cast[u64](h2) * s4 + cast[u64](h3) * s3 + cast[u64](h4) * s2
    d2 := cast[u64](h0) * r2 + cast[u64](h1) * r1 + cast[u64](h2) * r0 + cast[u64](h3) * s4 + cast[u64](h4) * s3
    d3 := cast[u64](h0) * r3 + cast[u64](h1) * r2 + cast[u64](h2) * r1 + cast[u64](h3) * r0 + cast[u64](h4) * s4
    d4 := cast[u64](h0) * r4 + cast[u64](h1) * r3 + cast[u64](h2) * r2 + cast[u64](h3) * r1 + cast[u64](h4) * r0
    c := d0 >> 26
    state.h[0] = cast[u32](d0) & 0x3ff_ffff
    d1 += c
    c = d1 >> 26
    state.h[1] = cast[u32](d1) & 0x3ff_ffff
    d2 += c
    c = d2 >> 26
    state.h[2] = cast[u32](d2) & 0x3ff_ffff
    d3 += c
    c = d3 >> 26
    state.h[3] = cast[u32](d3) & 0x3ff_ffff
    d4 += c
    c = d4 >> 26
    state.h[4] = cast[u32](d4) & 0x3ff_ffff
    state.h[0] += cast[u32](c) * 5
    carry := state.h[0] >> 26
    state.h[0] = state.h[0] & 0x3ff_ffff
    state.h[1] += carry
}

poly1305_update :: fn(poly: ptr[mut Poly1305], data: u8[]) {
    for byte in data {
        poly.state.block[poly.buffered % 16] = byte
        poly.buffered += 1
        if poly.buffered == 16 {
            poly1305_blocks(&poly.state, 1 << 24)
            poly.buffered = 0
        }
    }
}

// Zeros up to the next 16 bytes, as ChaCha20-Poly1305 pads what it authenticates.
poly1305_pad :: fn(poly: ptr[mut Poly1305]) {
    loop {
        poly1305_update(poly, u8.[0])
    }
    while poly.buffered != 0
}

poly1305_finish #constant_time :: fn(poly: ptr[mut Poly1305]) -> SecretByte[16] {
    // A last, partial block: a 1 after it, then zeros, and no 2^128
    if poly.buffered > 0 {
        poly.state.block[poly.buffered % 16] = 1
        for i in poly.buffered + 1..<16 {
            poly.state.block[i] = 0
        }
        poly1305_blocks(&poly.state, 0)
    }
    h0 := poly.state.h[0]
    h1 := poly.state.h[1]
    h2 := poly.state.h[2]
    h3 := poly.state.h[3]
    h4 := poly.state.h[4]
    c := h1 >> 26
    h1 = h1 & 0x3ff_ffff
    h2 += c
    c = h2 >> 26
    h2 = h2 & 0x3ff_ffff
    h3 += c
    c = h3 >> 26
    h3 = h3 & 0x3ff_ffff
    h4 += c
    c = h4 >> 26
    h4 = h4 & 0x3ff_ffff
    h0 += c * 5
    c = h0 >> 26
    h0 = h0 & 0x3ff_ffff
    h1 += c
    // h - (2^130 - 5), chosen over h when it isn't negative, by a mask rather than a branch
    g0 := h0 + 5
    c = g0 >> 26
    g0 = g0 & 0x3ff_ffff
    g1 := h1 + c
    c = g1 >> 26
    g1 = g1 & 0x3ff_ffff
    g2 := h2 + c
    c = g2 >> 26
    g2 = g2 & 0x3ff_ffff
    g3 := h3 + c
    c = g3 >> 26
    g3 = g3 & 0x3ff_ffff
    g4 := h4 + c - (1 << 26)
    mask := (g4 >> 31) - 1
    h0 = (h0 & ~mask) | (g0 & mask)
    h1 = (h1 & ~mask) | (g1 & mask)
    h2 = (h2 & ~mask) | (g2 & mask)
    h3 = (h3 & ~mask) | (g3 & mask)
    h4 = (h4 & ~mask) | (g4 & mask)
    // To 128 bits, plus s
    w0 := h0 | (h1 << 26)
    w1 := (h1 >> 6) | (h2 << 20)
    w2 := (h2 >> 12) | (h3 << 14)
    w3 := (h3 >> 18) | (h4 << 8)
    f := cast[u64](w0) + cast[u64](poly.state.s[0])
    w0 = cast[u32](f)
    f = cast[u64](w1) + cast[u64](poly.state.s[1]) + (f >> 32)
    w1 = cast[u32](f)
    f = cast[u64](w2) + cast[u64](poly.state.s[2]) + (f >> 32)
    w2 = cast[u32](f)
    f = cast[u64](w3) + cast[u64](poly.state.s[3]) + (f >> 32)
    w3 = cast[u32](f)
    tag : SecretByte[16]
    for j in 0..<4 {
        shift := 8 * cast[u32](j)
        tag[j] = cast[SecretByte](w0 >> shift)
        tag[4 + j] = cast[SecretByte](w1 >> shift)
        tag[8 + j] = cast[SecretByte](w2 >> shift)
        tag[12 + j] = cast[SecretByte](w3 >> shift)
    }
    return tag
}

// Poly1305's key for a message: the first 32 bytes of the keystream's block 0.
chacha20_poly1305_tag #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], associated: u8[], ciphertext: u8[]) -> SecretByte[16] {
    block := chacha20_block(key, 0, nonce)
    one_time : Poly1305Key
    for i in cast[usize](0)..<32 {
        one_time[i] = cast[u8](chacha_byte(&block, i))
    }
    poly := poly1305_start(&one_time)
    poly1305_update(&poly, associated)
    poly1305_pad(&poly)
    poly1305_update(&poly, ciphertext)
    poly1305_pad(&poly)
    lengths : u8[16]
    for j in 0..<8 {
        lengths[j] = cast[u8](cast[u64](associated.count) >> (8 * cast[u64](j)))
        lengths[8 + j] = cast[u8](cast[u64](ciphertext.count) >> (8 * cast[u64](j)))
    }
    poly1305_update(&poly, lengths)
    return poly1305_finish(&poly)
}

// The most a message can be: 2^32 - 1 blocks of 64 bytes, the counter starting at 1.
CHACHA20_POLY1305_MOST :: 274_877_906_880

/*
 * plaintext encrypted into ciphertext, of the same count, and its tag. False, with nothing written, when
 * the counts differ or it's longer than 256 GiB.
 */
chacha20_poly1305_seal #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], plaintext: SecretByte[], associated: u8[],
    ciphertext: mut u8[], tag: ptr[mut Tag128]) -> bool {

    if plaintext.count != ciphertext.count || cast[u64](plaintext.count) > CHACHA20_POLY1305_MOST {
        return false
    }
    block : ChaChaWords
    for i in 0..<plaintext.count {
        if i % 64 == 0 {
            block = chacha20_block(key, cast[u32](i / 64 + 1), nonce)
        }
        // The ciphertext is public by design
        ciphertext[i] = compiler.declassify(cast[u8](plaintext[i]) ~ cast[u8](chacha_byte(&block, i % 64)))
    }
    computed := chacha20_poly1305_tag(key, nonce, associated, ciphertext)
    for i in 0..<16 {
        tag[i] = compiler.declassify(cast[u8](computed[i]))
    }
    return true
}

/*
 * ciphertext decrypted into plaintext, of the same count, once its tag and the associated data are
 * found to be what was sealed. False, with nothing written, when they aren't, or the counts differ.
 */
chacha20_poly1305_open #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], ciphertext: u8[], associated: u8[],
    tag: ptr[Tag128], plaintext: mut SecretByte[]) -> bool {

    if plaintext.count != ciphertext.count || cast[u64](ciphertext.count) > CHACHA20_POLY1305_MOST {
        return false
    }
    computed := chacha20_poly1305_tag(key, nonce, associated, ciphertext)
    given : u8[16]
    for i in 0..<16 {
        given[i] = tag[i]
    }
    if !equal(computed, given) {
        return false
    }
    block : ChaChaWords
    for i in 0..<ciphertext.count {
        if i % 64 == 0 {
            block = chacha20_block(key, cast[u32](i / 64 + 1), nonce)
        }
        plaintext[i] = cast[SecretByte](ciphertext[i] ~ cast[u8](chacha_byte(&block, i % 64)))
    }
    return true
}
