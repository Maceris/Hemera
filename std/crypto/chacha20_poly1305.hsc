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
 *
 * The keystream is made eight blocks at a time, with AVX2 when vectors_wide() says the CPU and the OS allow it,
 * otherwise four at a time in 128-bit vectors. A kernel without vector state calls the _with functions with
 * wide = false, and builds without SSE, so the 128-bit vectors are worked out in ordinary registers.
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

// The words a block starts from: the constants, the key, the block's counter and the nonce.
chacha_state #constant_time :: fn(key: ptr[Key256], counter: u32, nonce: ptr[Nonce96]) -> ChaChaWords {
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
    return state
}

// One 64-byte block of keystream, as words.
chacha20_block #constant_time :: fn(key: ptr[Key256], counter: u32, nonce: ptr[Nonce96]) -> ChaChaWords {
    state := chacha_state(key, counter, nonce)
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
 * Several blocks at once, in vectors: word i of every block in vector i, a block a lane. The quarter round is
 * the same for any width, so a template, made for four lanes and for eight; each width has its own rounds
 * calling it, so it's inlined into the AVX2 one and compiled with AVX2.
 */
ChaChaLanes4 :: distinct alias vector[u32, 4][16] #secret
ChaChaLanes8 :: distinct alias vector[u32, 8][16] #secret

// Keystream for eight blocks, made four or eight at a time, and as the words they're made as.
CHACHA_STREAM :: 512
ChaChaStream :: distinct alias u8[512] #secret
ChaChaStreamWords :: distinct alias u32[128] #secret

chacha_quarter_lanes :: fn[T](x: ptr[mut T], a: usize, b: usize, c: usize, d: usize) {
    x[a % 16] = x[a % 16] + x[b % 16]
    x[d % 16] = intrinsics.rotate_left(x[d % 16] ~ x[a % 16], 16)
    x[c % 16] = x[c % 16] + x[d % 16]
    x[b % 16] = intrinsics.rotate_left(x[b % 16] ~ x[c % 16], 12)
    x[a % 16] = x[a % 16] + x[b % 16]
    x[d % 16] = intrinsics.rotate_left(x[d % 16] ~ x[a % 16], 8)
    x[c % 16] = x[c % 16] + x[d % 16]
    x[b % 16] = intrinsics.rotate_left(x[b % 16] ~ x[c % 16], 7)
}

// Four blocks from state's counter on, into the keystream's 64 words from at.
chacha20_blocks4 #constant_time :: fn(state: ptr[ChaChaWords], words: ptr[mut ChaChaStreamWords], at: usize) {
    x : ChaChaLanes4
    for i in 0..<16 {
        x[i] = intrinsics.splat[vector[u32, 4]](state[i])
    }
    x[12] = x[12] + vector[u32, 4].{0, 1, 2, 3}
    start := x
    for round in 0..<10 {
        chacha_quarter_lanes(&x, 0, 4, 8, 12)
        chacha_quarter_lanes(&x, 1, 5, 9, 13)
        chacha_quarter_lanes(&x, 2, 6, 10, 14)
        chacha_quarter_lanes(&x, 3, 7, 11, 15)
        chacha_quarter_lanes(&x, 0, 5, 10, 15)
        chacha_quarter_lanes(&x, 1, 6, 11, 12)
        chacha_quarter_lanes(&x, 2, 7, 8, 13)
        chacha_quarter_lanes(&x, 3, 4, 9, 14)
    }
    for i in 0..<16 {
        lanes := bit_cast[u32[4]](x[i] + start[i])
        for b in 0..<4 {
            words[(at + 16 * cast[usize](b) + cast[usize](i)) % 128] = lanes[b]
        }
    }
}

/*
 * The keystream's eight blocks from state's counter on, as the stream's 512 bytes. They're made as words,
 * whose bytes are the keystream's in order on a little-endian CPU, as every one Hemera targets is.
 */
chacha20_keystream #constant_time :: fn(state: ptr[mut ChaChaWords], wide: bool, stream: ptr[mut ChaChaStream]) {
    words : ChaChaStreamWords
    made := false
    #if TARGET_ARCH == .x86_64 {
        if wide {
            chacha20_blocks8(state, &words)
            made = true
        }
    }
    if !made {
        chacha20_blocks4(state, &words, 0)
        state[12] = state[12] + 4
        chacha20_blocks4(state, &words, 64)
    }
    stream^ = bit_cast[ChaChaStream](words)
}

#if TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"

    // Whether AVX2 can be used: the CPU has it, and the OS saves the YMM registers it uses (XCR0's bits 1 and 2).
    vectors_wide :: fn() -> bool {
        if (x86_64.cpuid(1).ecx & (1 << 27)) == 0 {
            return false
        }
        if (x86_64.xgetbv(0) & 6) != 6 {
            return false
        }
        return (x86_64.cpuid(7).ebx & (1 << 5)) != 0
    }

    // Eight blocks from state's counter on, with AVX2's 256-bit vectors.
    chacha20_blocks8 #constant_time #target_features("avx2") :: fn(state: ptr[ChaChaWords], words: ptr[mut ChaChaStreamWords]) {
        x : ChaChaLanes8
        for i in 0..<16 {
            x[i] = intrinsics.splat[vector[u32, 8]](state[i])
        }
        x[12] = x[12] + vector[u32, 8].{0, 1, 2, 3, 4, 5, 6, 7}
        start := x
        for round in 0..<10 {
            chacha_quarter_lanes(&x, 0, 4, 8, 12)
            chacha_quarter_lanes(&x, 1, 5, 9, 13)
            chacha_quarter_lanes(&x, 2, 6, 10, 14)
            chacha_quarter_lanes(&x, 3, 7, 11, 15)
            chacha_quarter_lanes(&x, 0, 5, 10, 15)
            chacha_quarter_lanes(&x, 1, 6, 11, 12)
            chacha_quarter_lanes(&x, 2, 7, 8, 13)
            chacha_quarter_lanes(&x, 3, 4, 9, 14)
        }
        for i in 0..<16 {
            lanes := bit_cast[u32[8]](x[i] + start[i])
            for b in 0..<8 {
                words[(16 * cast[usize](b) + cast[usize](i)) % 128] = lanes[b]
            }
        }
    }
}
#else {
    vectors_wide :: fn() -> bool {
        return false
    }
}

/*
 * Poly1305 (RFC 8439, 2.5), with 64-bit limbs like poly1305-donna-64: the key's r, clamped, and the sum in
 * three limbs of 44, 44 and 42 bits, whose products fit a u128; its s; and the bytes of a block being filled.
 */
Poly1305State :: struct #secret {
    r: u64[3],
    s: u64[2],
    h: u64[3],
    block: u8[16],
}

Poly1305 :: struct {
    state: Poly1305State,
    buffered: usize,
}

Poly1305Key :: distinct alias u8[32] #secret

POLY_MASK44 :: 0xfff_ffff_ffff
POLY_MASK42 :: 0x3ff_ffff_ffff

// Eight of a secret key's bytes, from at, as a little-endian word that's still a secret.
poly_key_word #constant_time :: fn(key: ptr[Poly1305Key], at: usize) -> SecretWord {
    word := compiler.secret(cast[u64](0))
    for j in 0..<8 {
        word = word | (cast[u64](key[(at + cast[usize](j)) % 32]) << (8 * cast[u64](j)))
    }
    return cast[SecretWord](word)
}

poly1305_start #constant_time :: fn(key: ptr[Poly1305Key]) -> Poly1305 {
    poly := Poly1305.{}
    t0 := cast[u64](poly_key_word(key, 0))
    t1 := cast[u64](poly_key_word(key, 8))
    // r with the bits RFC 8439 clamps cleared
    poly.state.r[0] = t0 & 0xffc_0fff_ffff
    poly.state.r[1] = ((t0 >> 44) | (t1 << 20)) & 0xfff_ffc0_ffff
    poly.state.r[2] = (t1 >> 24) & 0x00f_ffff_fc0f
    poly.state.s[0] = cast[u64](poly_key_word(key, 16))
    poly.state.s[1] = cast[u64](poly_key_word(key, 24))
    return poly
}

// A block, as two little-endian words, into the sum: h = (h + block) * r, mod 2^130 - 5. high is 2^128's bit, 1 << 40.
poly1305_add_block #constant_time :: fn(state: ptr[mut Poly1305State], t0: SecretWord, t1: SecretWord, high: u64) {
    m0 := cast[u64](t0)
    m1 := cast[u64](t1)
    h0 := state.h[0] + (m0 & POLY_MASK44)
    h1 := state.h[1] + (((m0 >> 44) | (m1 << 20)) & POLY_MASK44)
    h2 := state.h[2] + (((m1 >> 24) & POLY_MASK42) | high)
    r0 := cast[u128](state.r[0])
    r1 := cast[u128](state.r[1])
    r2 := cast[u128](state.r[2])
    // 2^130 is 5 mod p, and limb 3's weight is 2^132: times 4 * 5
    s1 := r1 * 20
    s2 := r2 * 20
    d0 := cast[u128](h0) * r0 + cast[u128](h1) * s2 + cast[u128](h2) * s1
    d1 := cast[u128](h0) * r1 + cast[u128](h1) * r0 + cast[u128](h2) * s2
    d2 := cast[u128](h0) * r2 + cast[u128](h1) * r1 + cast[u128](h2) * r0
    c := d0 >> 44
    state.h[0] = cast[u64](d0) & POLY_MASK44
    d1 = d1 + c
    c = d1 >> 44
    state.h[1] = cast[u64](d1) & POLY_MASK44
    d2 = d2 + c
    c = d2 >> 42
    state.h[2] = cast[u64](d2) & POLY_MASK42
    h0 = state.h[0] + cast[u64](c) * 5
    state.h[0] = h0 & POLY_MASK44
    state.h[1] = state.h[1] + (h0 >> 44)
}

// The buffered block into the sum.
poly1305_blocks #constant_time :: fn(state: ptr[mut Poly1305State], high: u64) {
    t0 := compiler.secret(cast[u64](0))
    t1 := compiler.secret(cast[u64](0))
    for j in 0..<8 {
        t0 = t0 | (cast[u64](state.block[j]) << (8 * cast[u64](j)))
        t1 = t1 | (cast[u64](state.block[8 + j]) << (8 * cast[u64](j)))
    }
    poly1305_add_block(state, cast[SecretWord](t0), cast[SecretWord](t1), high)
}

poly1305_update :: fn(poly: ptr[mut Poly1305], data: u8[]) {
    at : usize = 0
    // Filling a block already started, a byte at a time
    loop {
        poly.state.block[poly.buffered % 16] = data[at]
        poly.buffered += 1
        at += 1
        if poly.buffered == 16 {
            poly1305_blocks(&poly.state, 1 << 40)
            poly.buffered = 0
        }
    }
    while poly.buffered != 0 && at < data.count
    // Whole blocks straight from data, as two little-endian words
    loop {
        t0 : u64 = 0
        t1 : u64 = 0
        for j in cast[usize](0)..<8 {
            t0 = t0 | (cast[u64](data[at + j]) << (8 * cast[u64](j)))
            t1 = t1 | (cast[u64](data[at + 8 + j]) << (8 * cast[u64](j)))
        }
        poly1305_add_block(&poly.state, cast[SecretWord](t0), cast[SecretWord](t1), 1 << 40)
        at += 16
    }
    while at + 16 <= data.count
    // What's left, buffered
    loop {
        poly.state.block[poly.buffered % 16] = data[at]
        poly.buffered += 1
        at += 1
    }
    while at < data.count
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
    // Fully carried
    c := h1 >> 44
    h1 = h1 & POLY_MASK44
    h2 = h2 + c
    c = h2 >> 42
    h2 = h2 & POLY_MASK42
    h0 = h0 + c * 5
    c = h0 >> 44
    h0 = h0 & POLY_MASK44
    h1 = h1 + c
    c = h1 >> 44
    h1 = h1 & POLY_MASK44
    h2 = h2 + c
    c = h2 >> 42
    h2 = h2 & POLY_MASK42
    h0 = h0 + c * 5
    c = h0 >> 44
    h0 = h0 & POLY_MASK44
    h1 = h1 + c
    // h - p, chosen over h when it isn't negative, by a mask rather than a branch
    g0 := h0 + 5
    c = g0 >> 44
    g0 = g0 & POLY_MASK44
    g1 := h1 + c
    c = g1 >> 44
    g1 = g1 & POLY_MASK44
    g2 := h2 + c - (cast[u64](1) << 42)
    mask := (g2 >> 63) - 1
    h0 = (h0 & ~mask) | (g0 & mask)
    h1 = (h1 & ~mask) | (g1 & mask)
    h2 = (h2 & ~mask) | (g2 & mask)
    // Plus s, mod 2^128
    s0 := poly.state.s[0]
    s1 := poly.state.s[1]
    h0 = h0 + (s0 & POLY_MASK44)
    c = h0 >> 44
    h0 = h0 & POLY_MASK44
    h1 = h1 + (((s0 >> 44) | (s1 << 20)) & POLY_MASK44) + c
    c = h1 >> 44
    h1 = h1 & POLY_MASK44
    h2 = (h2 + ((s1 >> 24) & POLY_MASK42) + c) & POLY_MASK42
    w0 := h0 | (h1 << 44)
    w1 := (h1 >> 20) | (h2 << 24)
    tag : SecretByte[16]
    for j in 0..<8 {
        shift := 8 * cast[u64](j)
        tag[j] = cast[SecretByte](w0 >> shift)
        tag[8 + j] = cast[SecretByte](w1 >> shift)
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

    return chacha20_poly1305_seal_with(key, nonce, plaintext, associated, ciphertext, tag, vectors_wide())
}

/*
 * ciphertext decrypted into plaintext, of the same count, once its tag and the associated data are
 * found to be what was sealed. False, with nothing written, when they aren't, or the counts differ.
 */
chacha20_poly1305_open #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], ciphertext: u8[], associated: u8[],
    tag: ptr[Tag128], plaintext: mut SecretByte[]) -> bool {

    return chacha20_poly1305_open_with(key, nonce, ciphertext, associated, tag, plaintext, vectors_wide())
}

/*
 * Like chacha20_poly1305_seal, with AVX2 only when wide says to, which only works where vectors_wide() is true.
 * Without, it uses 128-bit vectors, which a target without them, like a kernel built without vector state,
 * works out with ordinary registers.
 */
chacha20_poly1305_seal_with #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], plaintext: SecretByte[], associated: u8[],
    ciphertext: mut u8[], tag: ptr[mut Tag128], wide: bool) -> bool {

    if plaintext.count != ciphertext.count || cast[u64](plaintext.count) > CHACHA20_POLY1305_MOST {
        return false
    }
    stream : ChaChaStream
    at : usize = 0
    // A chunk of eight blocks at a time, so the loop over its bytes can be vectorized
    loop {
        state := chacha_state(key, cast[u32](at / 64 + 1), nonce)
        chacha20_keystream(&state, wide, &stream)
        chunk := plaintext[at..<plaintext.count]
        out := ciphertext[at..<ciphertext.count]
        for i in cast[usize](0)..<CHACHA_STREAM {
            if i < chunk.count && i < out.count {
                // The ciphertext is public by design
                out[i] = compiler.declassify(cast[u8](chunk[i]) ~ stream[i])
            }
        }
        at += CHACHA_STREAM
    }
    while at < plaintext.count
    computed := chacha20_poly1305_tag(key, nonce, associated, ciphertext)
    for i in 0..<16 {
        tag[i] = compiler.declassify(cast[u8](computed[i]))
    }
    return true
}

// Like chacha20_poly1305_open, with AVX2 only when wide says to (see chacha20_poly1305_seal_with).
chacha20_poly1305_open_with #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], ciphertext: u8[], associated: u8[],
    tag: ptr[Tag128], plaintext: mut SecretByte[], wide: bool) -> bool {

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
    stream : ChaChaStream
    at : usize = 0
    loop {
        state := chacha_state(key, cast[u32](at / 64 + 1), nonce)
        chacha20_keystream(&state, wide, &stream)
        chunk := ciphertext[at..<ciphertext.count]
        out := plaintext[at..<plaintext.count]
        for i in cast[usize](0)..<CHACHA_STREAM {
            if i < chunk.count && i < out.count {
                out[i] = cast[SecretByte](chunk[i] ~ stream[i])
            }
        }
        at += CHACHA_STREAM
    }
    while at < ciphertext.count
    return true
}
