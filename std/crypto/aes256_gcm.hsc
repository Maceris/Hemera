package crypto

import compiler from "base"
import intrinsics from "base"

/*
 * AES-256-GCM (FIPS 197, NIST SP 800-38D): encryption with a 32-byte key and a 12-byte nonce, which
 * must never be used twice with one key, and a 16-byte tag, like ChaCha20-Poly1305's (see
 * chacha20_poly1305.hsc, whose Key256, Nonce96 and Tag128 it shares).
 *
 * On an x86-64 CPU with AES-NI and PCLMULQDQ it uses them; otherwise AES and GHASH are worked out in
 * software, in constant time, which is far slower: each S-box lookup looks at the whole table. A
 * kernel built without vector state passes hardware = false to the _with functions, unless it saves
 * the vector registers around the call.
 */

AES_SBOX :: u8.[
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16,
]

AES_ROUND_CONSTANTS :: u8.[0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40]

// The 15 round keys, each 16 bytes in the order AES uses them
AesSchedule :: distinct alias u8[240] #secret
AesBlock :: distinct alias u8[16] #secret

// GHASH's values, as two big-endian halves: high is the first 8 bytes
Ghash :: struct #secret {
    high: u64,
    low: u64,
}

Aes256Gcm :: struct {
    schedule: AesSchedule,
    hash_key: Ghash,
    hardware: bool,
}

// One byte through the S-box, looking at every entry so how long it takes says nothing of the byte.
aes_sbox #constant_time :: fn(x: SecretByte) -> SecretByte {
    result := compiler.secret(cast[u8](0))
    for i in 0..<256 {
        result = intrinsics.select(cast[u8](x) == cast[u8](i), AES_SBOX[i], result)
    }
    return cast[SecretByte](result)
}

// Multiplying by 2 in AES's field.
aes_double #constant_time :: fn(a: SecretByte) -> SecretByte {
    value := cast[u8](a)
    return cast[SecretByte]((value << 1) ~ (0x1b & (cast[u8](0) - (value >> 7))))
}

aes256_expand #constant_time :: fn(key: ptr[Key256]) -> AesSchedule {
    schedule : AesSchedule
    for i in 0..<32 {
        schedule[i] = key[i]
    }
    // Word i + 8 from words i + 7 and i
    for i in 0..<52 {
        word := i + 8
        t0 := cast[SecretByte](schedule[4 * i + 28])
        t1 := cast[SecretByte](schedule[4 * i + 29])
        t2 := cast[SecretByte](schedule[4 * i + 30])
        t3 := cast[SecretByte](schedule[4 * i + 31])
        if word % 8 == 0 {
            rotated := t0
            t0 = aes_sbox(t1)
            t1 = aes_sbox(t2)
            t2 = aes_sbox(t3)
            t3 = aes_sbox(rotated)
            t0 = cast[SecretByte](cast[u8](t0) ~ AES_ROUND_CONSTANTS[(word / 8) % 8])
        }
        else if word % 8 == 4 {
            t0 = aes_sbox(t0)
            t1 = aes_sbox(t1)
            t2 = aes_sbox(t2)
            t3 = aes_sbox(t3)
        }
        schedule[4 * i + 32] = schedule[4 * i] ~ cast[u8](t0)
        schedule[4 * i + 33] = schedule[4 * i + 1] ~ cast[u8](t1)
        schedule[4 * i + 34] = schedule[4 * i + 2] ~ cast[u8](t2)
        schedule[4 * i + 35] = schedule[4 * i + 3] ~ cast[u8](t3)
    }
    return schedule
}

aes256_encrypt_software #constant_time :: fn(schedule: ptr[AesSchedule], block: ptr[mut AesBlock]) {
    for i in 0..<16 {
        block[i] = block[i] ~ schedule[i]
    }
    for round in 1..<15 {
        for i in 0..<16 {
            block[i] = cast[u8](aes_sbox(cast[SecretByte](block[i])))
        }
        // Row r moves left by r
        shifted : AesBlock
        for column in 0..<4 {
            for row in 0..<4 {
                shifted[row + 4 * column] = block[row + 4 * ((column + row) % 4)]
            }
        }
        block^ = shifted
        if round < 14 {
            for column in 0..<4 {
                a0 := cast[SecretByte](block[4 * column])
                a1 := cast[SecretByte](block[4 * column + 1])
                a2 := cast[SecretByte](block[4 * column + 2])
                a3 := cast[SecretByte](block[4 * column + 3])
                d0 := aes_double(a0)
                d1 := aes_double(a1)
                d2 := aes_double(a2)
                d3 := aes_double(a3)
                block[4 * column] = cast[u8](d0) ~ cast[u8](d1) ~ cast[u8](a1) ~ cast[u8](a2) ~ cast[u8](a3)
                block[4 * column + 1] = cast[u8](a0) ~ cast[u8](d1) ~ cast[u8](d2) ~ cast[u8](a2) ~ cast[u8](a3)
                block[4 * column + 2] = cast[u8](a0) ~ cast[u8](a1) ~ cast[u8](d2) ~ cast[u8](d3) ~ cast[u8](a3)
                block[4 * column + 3] = cast[u8](d0) ~ cast[u8](a0) ~ cast[u8](a1) ~ cast[u8](a2) ~ cast[u8](d3)
            }
        }
        for i in 0..<16 {
            block[i] = block[i] ~ schedule[16 * round + i]
        }
    }
}

// x times y in GHASH's field, a bit at a time, with masks rather than branches.
ghash_multiply_software #constant_time :: fn(x: Ghash, y: Ghash) -> Ghash {
    z := Ghash.{high = 0, low = 0}
    v := y
    for i in 0..<128 {
        word := x.high
        if i >= 64 {
            word = x.low
        }
        bit := (word >> (63 - cast[u64](i % 64))) & 1
        mask := cast[u64](0) - bit
        z.high = z.high ~ (v.high & mask)
        z.low = z.low ~ (v.low & mask)
        carry := v.low & 1
        v.low = (v.low >> 1) | (v.high << 63)
        v.high = (v.high >> 1) ~ (0xe100_0000_0000_0000 & (cast[u64](0) - carry))
    }
    return z
}

ghash_multiply #constant_time :: fn(x: Ghash, y: Ghash, hardware: bool) -> Ghash {
    #if TARGET_ARCH == .x86_64 {
        if hardware {
            return ghash_multiply_hardware(x, y)
        }
    }
    return ghash_multiply_software(x, y)
}

aes256_encrypt #constant_time :: fn(schedule: ptr[AesSchedule], block: ptr[mut AesBlock], hardware: bool) {
    #if TARGET_ARCH == .x86_64 {
        if hardware {
            aes256_encrypt_hardware(schedule, block)
            return void
        }
    }
    aes256_encrypt_software(schedule, block)
}

// Whether AES-NI and PCLMULQDQ are there to use.
aes_hardware :: fn() -> bool {
    #if TARGET_ARCH == .x86_64 {
        features := x86_64.cpuid(1)
        return (features.ecx & (1 << 25)) != 0 && (features.ecx & (1 << 1)) != 0
    }
    #else {
        return false
    }
}

// 16 bytes as GHASH's value
ghash_of #constant_time :: fn(block: ptr[AesBlock]) -> Ghash {
    value := Ghash.{high = 0, low = 0}
    for i in 0..<8 {
        value.high = (value.high << 8) | cast[u64](block[i])
        value.low = (value.low << 8) | cast[u64](block[8 + i])
    }
    return value
}

aes256_gcm_start #constant_time :: fn(key: ptr[Key256], hardware: bool) -> Aes256Gcm {
    gcm := Aes256Gcm.{schedule = aes256_expand(key), hardware = hardware}
    zero : AesBlock
    aes256_encrypt(&gcm.schedule, &zero, hardware)
    gcm.hash_key = ghash_of(&zero)
    return gcm
}

// GHASH's running value, given public bytes, a block at a time, zero padded at the end.
ghash_update #constant_time :: fn(gcm: ptr[Aes256Gcm], value: ptr[mut Ghash], data: u8[]) {
    block : AesBlock
    for i in 0..<data.count {
        block[i % 16] = data[i]
        if i % 16 == 15 || i + 1 == data.count {
            for j in i % 16 + 1..<16 {
                block[j] = 0
            }
            addend := ghash_of(&block)
            value.high = value.high ~ addend.high
            value.low = value.low ~ addend.low
            value^ = ghash_multiply(value^, gcm.hash_key, gcm.hardware)
        }
    }
}

// The counter block for a block of the message, the nonce then a 32-bit big-endian count from 2.
gcm_counter #constant_time :: fn(nonce: ptr[Nonce96], count: u32) -> AesBlock {
    block : AesBlock
    for i in 0..<12 {
        block[i] = nonce[i]
    }
    for j in 0..<4 {
        block[12 + j] = cast[u8](count >> (24 - 8 * cast[u32](j)))
    }
    return block
}

gcm_tag #constant_time :: fn(gcm: ptr[Aes256Gcm], nonce: ptr[Nonce96], associated: u8[], ciphertext: u8[]) -> SecretByte[16] {
    value := Ghash.{high = 0, low = 0}
    ghash_update(gcm, &value, associated)
    ghash_update(gcm, &value, ciphertext)
    value.high = value.high ~ (cast[u64](associated.count) * 8)
    value.low = value.low ~ (cast[u64](ciphertext.count) * 8)
    value = ghash_multiply(value, gcm.hash_key, gcm.hardware)
    first := gcm_counter(nonce, 1)
    aes256_encrypt(&gcm.schedule, &first, gcm.hardware)
    tag : SecretByte[16]
    for i in 0..<8 {
        shift := 56 - 8 * cast[u64](i)
        tag[i] = cast[SecretByte](cast[u8](value.high >> shift) ~ first[i])
        tag[8 + i] = cast[SecretByte](cast[u8](value.low >> shift) ~ first[8 + i])
    }
    return tag
}

// The most a message can be: 2^32 - 2 blocks of 16 bytes
AES256_GCM_MOST :: 68_719_476_704

aes256_gcm_seal #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], plaintext: SecretByte[], associated: u8[],
    ciphertext: mut u8[], tag: ptr[mut Tag128]) -> bool {

    return aes256_gcm_seal_with(key, nonce, plaintext, associated, ciphertext, tag, aes_hardware())
}

aes256_gcm_open #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], ciphertext: u8[], associated: u8[],
    tag: ptr[Tag128], plaintext: mut SecretByte[]) -> bool {

    return aes256_gcm_open_with(key, nonce, ciphertext, associated, tag, plaintext, aes_hardware())
}

/*
 * Like aes256_gcm_seal, with AES-NI and PCLMULQDQ only when hardware says to, which only works on a CPU
 * that has them.
 */
aes256_gcm_seal_with #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], plaintext: SecretByte[], associated: u8[],
    ciphertext: mut u8[], tag: ptr[mut Tag128], hardware: bool) -> bool {

    if plaintext.count != ciphertext.count || cast[u64](plaintext.count) > AES256_GCM_MOST {
        return false
    }
    gcm := aes256_gcm_start(key, hardware)
    stream : AesBlock
    for i in 0..<plaintext.count {
        if i % 16 == 0 {
            stream = gcm_counter(nonce, cast[u32](i / 16 + 2))
            aes256_encrypt(&gcm.schedule, &stream, hardware)
        }
        ciphertext[i] = compiler.declassify(cast[u8](plaintext[i]) ~ stream[i % 16])
    }
    computed := gcm_tag(&gcm, nonce, associated, ciphertext)
    for i in 0..<16 {
        tag[i] = compiler.declassify(cast[u8](computed[i]))
    }
    return true
}

aes256_gcm_open_with #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], ciphertext: u8[], associated: u8[],
    tag: ptr[Tag128], plaintext: mut SecretByte[], hardware: bool) -> bool {

    if plaintext.count != ciphertext.count || cast[u64](ciphertext.count) > AES256_GCM_MOST {
        return false
    }
    gcm := aes256_gcm_start(key, hardware)
    computed := gcm_tag(&gcm, nonce, associated, ciphertext)
    given : u8[16]
    for i in 0..<16 {
        given[i] = tag[i]
    }
    if !equal(computed, given) {
        return false
    }
    stream : AesBlock
    for i in 0..<ciphertext.count {
        if i % 16 == 0 {
            stream = gcm_counter(nonce, cast[u32](i / 16 + 2))
            aes256_encrypt(&gcm.schedule, &stream, hardware)
        }
        plaintext[i] = cast[SecretByte](ciphertext[i] ~ stream[i % 16])
    }
    return true
}

#if TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"

    // The schedule's round keys as AES-NI takes them
    AesRoundKeys :: distinct alias v128[15] #secret

    aes256_encrypt_hardware #constant_time #target_features("aes") :: fn(schedule: ptr[AesSchedule], block: ptr[mut AesBlock]) {
        keys := bit_cast[AesRoundKeys](schedule^)
        state := bit_cast[v128](block^) ~ keys[0]
        for round in 1..<14 {
            state = x86_64.aes_encrypt_round(state, keys[round])
        }
        state = x86_64.aes_encrypt_last(state, keys[14])
        block^ = bit_cast[AesBlock](state)
    }

    // GHASH's multiply with PCLMULQDQ (Intel's carry-less multiplication white paper), on values held
    // as one 128-bit big-endian integer, its low half in lane 0
    ghash_multiply_hardware #constant_time #target_features("pclmul") :: fn(x: Ghash, y: Ghash) -> Ghash {
        a := bit_cast[v128](vector[u64, 2].{x.low, x.high})
        b := bit_cast[v128](vector[u64, 2].{y.low, y.high})
        t3 := bit_cast[vector[u64, 2]](x86_64.carryless_multiply(a, b, 0x00))
        t4 := bit_cast[vector[u64, 2]](x86_64.carryless_multiply(a, b, 0x10))
        t5 := bit_cast[vector[u64, 2]](x86_64.carryless_multiply(a, b, 0x01))
        t6 := bit_cast[vector[u64, 2]](x86_64.carryless_multiply(a, b, 0x11))
        t4 = t4 ~ t5
        t3 = t3 ~ vector[u64, 2].{0, t4[0]}
        t6 = t6 ~ vector[u64, 2].{t4[1], 0}
        // The 256-bit product shifted left by one
        w3 := bit_cast[vector[u32, 4]](t3)
        w6 := bit_cast[vector[u32, 4]](t6)
        c3 := w3 >> 31
        c6 := w6 >> 31
        w3 = (w3 << 1) | vector[u32, 4].{0, c3[0], c3[1], c3[2]}
        w6 = (w6 << 1) | vector[u32, 4].{c3[3], c6[0], c6[1], c6[2]}
        // Reduced by x^128 + x^7 + x^2 + x + 1
        r7 := (w3 << 31) ~ (w3 << 30) ~ (w3 << 25)
        r8 := vector[u32, 4].{r7[1], r7[2], r7[3], 0}
        w3 = w3 ~ vector[u32, 4].{0, 0, 0, r7[0]}
        r2 := (w3 >> 1) ~ (w3 >> 2) ~ (w3 >> 7) ~ r8
        w3 = w3 ~ r2
        w6 = w6 ~ w3
        result := bit_cast[vector[u64, 2]](w6)
        return Ghash.{high = result[1], low = result[0]}
    }
}
