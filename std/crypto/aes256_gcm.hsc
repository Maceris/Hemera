package crypto

import compiler from "base"
import intrinsics from "base"

/*
 * AES-256-GCM (FIPS 197, NIST SP 800-38D): encryption with a 32-byte key and a 12-byte nonce, which
 * must never be used twice with one key, and a 16-byte tag, like ChaCha20-Poly1305's (see
 * chacha20_poly1305.hsc, whose Key256, Nonce96 and Tag128 it shares).
 *
 * On an x86-64 CPU with AES-NI and PCLMULQDQ it uses them; otherwise AES and GHASH are worked out in
 * software, in constant time: AES bitsliced, four blocks at once, and GHASH with integer multiplies that
 * can't carry into what's kept. A kernel built without vector state passes hardware = false to the _with
 * functions, unless it saves the vector registers around the call.
 */

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
    // For software: the round keys as bit planes
    sliced: AesSlicedSchedule,
    hash_key: Ghash,
    // H, H^2, H^3 and H^4, so GHASH can take four blocks with one reduction
    hash_powers: Ghash[4],
    hardware: bool,
}

// Eight bit planes, plane k holding bit k of each byte the planes are carrying
AesPlanes :: distinct alias u64[8] #secret

/*
 * The S-box on every byte the planes carry at once: Boyar and Peralta's circuit (the one BearSSL uses), the
 * field inverse and the affine map as about 115 ands and xors, with no table.
 */
aes_sbox_planes #constant_time :: fn(q: ptr[mut AesPlanes]) {
    x0 := q[7]
    x1 := q[6]
    x2 := q[5]
    x3 := q[4]
    x4 := q[3]
    x5 := q[2]
    x6 := q[1]
    x7 := q[0]

    // The top linear transformation
    y14 := x3 ~ x5
    y13 := x0 ~ x6
    y9 := x0 ~ x3
    y8 := x0 ~ x5
    t0 := x1 ~ x2
    y1 := t0 ~ x7
    y4 := y1 ~ x3
    y12 := y13 ~ y14
    y2 := y1 ~ x0
    y5 := y1 ~ x6
    y3 := y5 ~ y8
    t1 := x4 ~ y12
    y15 := t1 ~ x5
    y20 := t1 ~ x1
    y6 := y15 ~ x7
    y10 := y15 ~ t0
    y11 := y20 ~ y9
    y7 := x7 ~ y11
    y17 := y10 ~ y11
    y19 := y10 ~ y8
    y16 := t0 ~ y11
    y21 := y13 ~ y16
    y18 := x0 ~ y16

    // The non-linear middle
    t2 := y12 & y15
    t3 := y3 & y6
    t4 := t3 ~ t2
    t5 := y4 & x7
    t6 := t5 ~ t2
    t7 := y13 & y16
    t8 := y5 & y1
    t9 := t8 ~ t7
    t10 := y2 & y7
    t11 := t10 ~ t7
    t12 := y9 & y11
    t13 := y14 & y17
    t14 := t13 ~ t12
    t15 := y8 & y10
    t16 := t15 ~ t12
    t17 := t4 ~ t14
    t18 := t6 ~ t16
    t19 := t9 ~ t14
    t20 := t11 ~ t16
    t21 := t17 ~ y20
    t22 := t18 ~ y19
    t23 := t19 ~ y21
    t24 := t20 ~ y18

    t25 := t21 ~ t22
    t26 := t21 & t23
    t27 := t24 ~ t26
    t28 := t25 & t27
    t29 := t28 ~ t22
    t30 := t23 ~ t24
    t31 := t22 ~ t26
    t32 := t31 & t30
    t33 := t32 ~ t24
    t34 := t23 ~ t33
    t35 := t27 ~ t33
    t36 := t24 & t35
    t37 := t36 ~ t34
    t38 := t27 ~ t36
    t39 := t29 & t38
    t40 := t25 ~ t39

    t41 := t40 ~ t37
    t42 := t29 ~ t33
    t43 := t29 ~ t40
    t44 := t33 ~ t37
    t45 := t42 ~ t41
    z0 := t44 & y15
    z1 := t37 & y6
    z2 := t33 & x7
    z3 := t43 & y16
    z4 := t40 & y1
    z5 := t29 & y7
    z6 := t42 & y11
    z7 := t45 & y17
    z8 := t41 & y10
    z9 := t44 & y12
    z10 := t37 & y3
    z11 := t33 & y4
    z12 := t43 & y13
    z13 := t40 & y5
    z14 := t29 & y2
    z15 := t42 & y9
    z16 := t45 & y14
    z17 := t41 & y8

    // The bottom linear transformation
    t46 := z15 ~ z16
    t47 := z10 ~ z11
    t48 := z5 ~ z13
    t49 := z9 ~ z10
    t50 := z2 ~ z12
    t51 := z2 ~ z5
    t52 := z7 ~ z8
    t53 := z0 ~ z3
    t54 := z6 ~ z7
    t55 := z16 ~ z17
    t56 := z12 ~ t48
    t57 := t50 ~ t53
    t58 := z4 ~ t46
    t59 := z3 ~ t54
    t60 := t46 ~ t57
    t61 := z14 ~ t57
    t62 := t52 ~ t58
    t63 := t49 ~ t58
    t64 := z4 ~ t59
    t65 := t61 ~ t62
    t66 := z1 ~ t63
    s0 := t59 ~ t63
    s6 := t56 ~ (~t62)
    s7 := t48 ~ (~t60)
    t67 := t64 ~ t65
    s3 := t53 ~ t66
    s4 := t51 ~ t66
    s5 := t47 ~ t65
    s1 := t64 ~ (~s3)
    s2 := t55 ~ (~t67)

    q[7] = s0
    q[6] = s1
    q[5] = s2
    q[4] = s3
    q[3] = s4
    q[2] = s5
    q[1] = s6
    q[0] = s7
}

// One byte through the S-box, as one bit of each plane.
aes_sbox #constant_time :: fn(x: SecretByte) -> SecretByte {
    q : AesPlanes
    for k in 0..<8 {
        q[k] = cast[u64](cast[u8](x) >> cast[u8](k)) & 1
    }
    aes_sbox_planes(&q)
    result := compiler.secret(cast[u8](0))
    for k in 0..<8 {
        result = result | (cast[u8](q[k] & 1) << cast[u8](k))
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

// Four blocks, one after another: what bitsliced AES works on at once
AesBlocks4 :: distinct alias u8[64] #secret
// The round keys as bit planes, each byte repeated for the four blocks: 15 rounds of 8 planes
AesSlicedSchedule :: distinct alias u64[120] #secret

/*
 * Bitsliced AES (like BearSSL's, laid out its own way): four blocks' 64 bytes as eight 64-bit planes, plane k
 * holding bit k of every byte. Byte position p (row r + 4 * column c, as AES numbers a block's bytes) of block b
 * is bit 4 * p + b, so each column is 16 bits of a plane, and each row a nibble of each column. Every step is
 * ands, xors, shifts and rotations of whole planes: no table, nothing that depends on the bytes but the bytes.
 */

// An 8 by 8 bit matrix, a byte a row, turned so that byte k holds bit k of each row (Hacker's Delight, 7-3).
aes_transpose8 #constant_time :: fn(word: SecretWord) -> SecretWord {
    x := cast[u64](word)
    y := x
    t := (y ~ (y >> 7)) & 0x00aa_00aa_00aa_00aa
    y = y ~ t ~ (t << 7)
    t = (y ~ (y >> 14)) & 0x0000_cccc_0000_cccc
    y = y ~ t ~ (t << 14)
    t = (y ~ (y >> 28)) & 0x0000_0000_f0f0_f0f0
    y = y ~ t ~ (t << 28)
    return cast[SecretWord](y)
}

// Bit j of a byte moved to bit 4 * j, and back.
aes_spread #constant_time :: fn(word: SecretWord) -> SecretWord {
    x := cast[u64](word)
    y := (x ~ (x << 12)) & 0x000f_000f
    y = (y ~ (y << 6)) & 0x0303_0303
    return cast[SecretWord]((y ~ (y << 3)) & 0x1111_1111)
}

aes_gather #constant_time :: fn(word: SecretWord) -> SecretWord {
    x := cast[u64](word)
    y := x & 0x1111_1111
    y = (y ~ (y >> 3)) & 0x0303_0303
    y = (y ~ (y >> 6)) & 0x000f_000f
    return cast[SecretWord]((y ~ (y >> 12)) & 0xff)
}

aes_pack #constant_time :: fn(blocks: ptr[AesBlocks4], q: ptr[mut AesPlanes]) {
    for k in 0..<8 {
        q[k] = 0
    }
    for half in 0..<8 {
        // Bytes 8 * half to 8 * half + 7 of the 64: block half / 2, positions 8 * (half % 2) on
        word := compiler.secret(cast[u64](0))
        for j in 0..<8 {
            word = word | (cast[u64](blocks[8 * half + j]) << (8 * cast[u64](j)))
        }
        turned := cast[u64](aes_transpose8(cast[SecretWord](word)))
        shift := 32 * cast[u64](half % 2) + cast[u64](half / 2)
        for k in 0..<8 {
            q[k] = q[k] | (cast[u64](aes_spread(cast[SecretWord]((turned >> (8 * cast[u64](k))) & 0xff))) << shift)
        }
    }
}

aes_unpack #constant_time :: fn(q: ptr[AesPlanes], blocks: ptr[mut AesBlocks4]) {
    for half in 0..<8 {
        shift := 32 * cast[u64](half % 2) + cast[u64](half / 2)
        turned := compiler.secret(cast[u64](0))
        for k in 0..<8 {
            turned = turned | (cast[u64](aes_gather(cast[SecretWord](q[k] >> shift))) << (8 * cast[u64](k)))
        }
        word := cast[u64](aes_transpose8(cast[SecretWord](turned)))
        for j in 0..<8 {
            blocks[8 * half + j] = cast[u8](word >> (8 * cast[u64](j)))
        }
    }
}

// Row r of each column moves left by r columns: in a plane, row r's nibbles rotate by 16 * r bits.
aes_shift_rows #constant_time :: fn(q: ptr[mut AesPlanes]) {
    for k in 0..<8 {
        x := q[k]
        q[k] = (x & 0x000f_000f_000f_000f) | intrinsics.rotate_right(x & 0x00f0_00f0_00f0_00f0, 16)
            | intrinsics.rotate_right(x & 0x0f00_0f00_0f00_0f00, 32) | intrinsics.rotate_right(x & 0xf000_f000_f000_f000, 48)
    }
}

// Each column's rows moved up by 1, 2 or 3: row r + n's nibble into row r's, within the column's 16 bits.
aes_rows_up1 #constant_time :: fn(word: SecretWord) -> SecretWord {
    x := cast[u64](word)
    return cast[SecretWord](((x >> 4) & 0x0fff_0fff_0fff_0fff) | ((x << 12) & 0xf000_f000_f000_f000))
}

aes_rows_up2 #constant_time :: fn(word: SecretWord) -> SecretWord {
    x := cast[u64](word)
    return cast[SecretWord](((x >> 8) & 0x00ff_00ff_00ff_00ff) | ((x << 8) & 0xff00_ff00_ff00_ff00))
}

aes_rows_up3 #constant_time :: fn(word: SecretWord) -> SecretWord {
    x := cast[u64](word)
    return cast[SecretWord](((x >> 12) & 0x000f_000f_000f_000f) | ((x << 4) & 0xfff0_fff0_fff0_fff0))
}

/*
 * Each column's b_r = 2 * a_r ~ 3 * a_(r+1) ~ a_(r+2) ~ a_(r+3), as 2 * (a_r ~ a_(r+1)) ~ a_(r+1) ~ a_(r+2) ~ a_(r+3):
 * doubling moves each plane up one, the top one back in where x^8 = x^4 + x^3 + x + 1 says.
 */
aes_mix_columns #constant_time :: fn(q: ptr[mut AesPlanes]) {
    sum : AesPlanes
    rest : AesPlanes
    for k in 0..<8 {
        a := cast[SecretWord](q[k])
        up1 := cast[u64](aes_rows_up1(a))
        sum[k] = q[k] ~ up1
        rest[k] = up1 ~ cast[u64](aes_rows_up2(a)) ~ cast[u64](aes_rows_up3(a))
    }
    top := sum[7]
    q[0] = top ~ rest[0]
    q[1] = sum[0] ~ top ~ rest[1]
    q[2] = sum[1] ~ rest[2]
    q[3] = sum[2] ~ top ~ rest[3]
    q[4] = sum[3] ~ top ~ rest[4]
    q[5] = sum[4] ~ rest[5]
    q[6] = sum[5] ~ rest[6]
    q[7] = sum[6] ~ rest[7]
}

// The schedule's round keys as planes, each byte in all four blocks' bits for it.
aes256_slice_schedule #constant_time :: fn(schedule: ptr[AesSchedule]) -> AesSlicedSchedule {
    sliced : AesSlicedSchedule
    for round in 0..<15 {
        for p in 0..<16 {
            byte := cast[u64](schedule[16 * round + p])
            for k in 0..<8 {
                bit := (byte >> cast[u64](k)) & 1
                sliced[8 * round + k] = sliced[8 * round + k] | ((cast[u64](0) - bit) & (cast[u64](0xf) << (4 * cast[u64](p))))
            }
        }
    }
    return sliced
}

// Four blocks encrypted at once (FIPS 197, 5.1), in place.
aes256_encrypt4_software #constant_time :: fn(sliced: ptr[AesSlicedSchedule], blocks: ptr[mut AesBlocks4]) {
    q : AesPlanes
    aes_pack(blocks, &q)
    for k in 0..<8 {
        q[k] = q[k] ~ sliced[k]
    }
    for round in 1..<15 {
        aes_sbox_planes(&q)
        aes_shift_rows(&q)
        if round < 14 {
            aes_mix_columns(&q)
        }
        for k in 0..<8 {
            q[k] = q[k] ~ sliced[8 * round + k]
        }
    }
    aes_unpack(&q, blocks)
}

// x's bits in the other order.
ghash_reverse #constant_time :: fn(word: SecretWord) -> SecretWord {
    x := cast[u64](word)
    y := ((x >> 1) & 0x5555_5555_5555_5555) | ((x & 0x5555_5555_5555_5555) << 1)
    y = ((y >> 2) & 0x3333_3333_3333_3333) | ((y & 0x3333_3333_3333_3333) << 2)
    y = ((y >> 4) & 0x0f0f_0f0f_0f0f_0f0f) | ((y & 0x0f0f_0f0f_0f0f_0f0f) << 4)
    return cast[SecretWord](intrinsics.byte_swap(y))
}

/*
 * The low 64 bits of x and y's carry-less product, with integer multiplies (BearSSL's ghash_ctmul64): each
 * operand split into every fourth bit, so the carries a multiply makes land in bits the masks throw away.
 */
ghash_bmul64 #constant_time :: fn(a: SecretWord, b: SecretWord) -> SecretWord {
    x := cast[u64](a)
    y := cast[u64](b)
    x0 := x & 0x1111_1111_1111_1111
    x1 := x & 0x2222_2222_2222_2222
    x2 := x & 0x4444_4444_4444_4444
    x3 := x & 0x8888_8888_8888_8888
    y0 := y & 0x1111_1111_1111_1111
    y1 := y & 0x2222_2222_2222_2222
    y2 := y & 0x4444_4444_4444_4444
    y3 := y & 0x8888_8888_8888_8888
    z0 := (x0 * y0) ~ (x1 * y3) ~ (x2 * y2) ~ (x3 * y1)
    z1 := (x0 * y1) ~ (x1 * y0) ~ (x2 * y3) ~ (x3 * y2)
    z2 := (x0 * y2) ~ (x1 * y1) ~ (x2 * y0) ~ (x3 * y3)
    z3 := (x0 * y3) ~ (x1 * y2) ~ (x2 * y1) ~ (x3 * y0)
    return cast[SecretWord]((z0 & 0x1111_1111_1111_1111) | (z1 & 0x2222_2222_2222_2222) | (z2 & 0x4444_4444_4444_4444)
        | (z3 & 0x8888_8888_8888_8888))
}

/*
 * x times y in GHASH's field, in constant time: three 64-bit products for the low halves and three for the
 * high ones, the latter from the bits reversed (Karatsuba), then shifted and reduced by x^128 + x^7 + x^2 + x + 1.
 */
ghash_multiply_software #constant_time :: fn(x: Ghash, y: Ghash) -> Ghash {
    h0 := cast[SecretWord](y.low)
    h1 := cast[SecretWord](y.high)
    h2 := cast[SecretWord](y.low ~ y.high)
    h0r := ghash_reverse(h0)
    h1r := ghash_reverse(h1)
    h2r := cast[SecretWord](cast[u64](h0r) ~ cast[u64](h1r))
    x0 := cast[SecretWord](x.low)
    x1 := cast[SecretWord](x.high)
    x2 := cast[SecretWord](x.low ~ x.high)
    x0r := ghash_reverse(x0)
    x1r := ghash_reverse(x1)
    x2r := cast[SecretWord](cast[u64](x0r) ~ cast[u64](x1r))
    z0 := cast[u64](ghash_bmul64(x0, h0))
    z1 := cast[u64](ghash_bmul64(x1, h1))
    z2 := cast[u64](ghash_bmul64(x2, h2))
    z0h := cast[u64](ghash_bmul64(x0r, h0r))
    z1h := cast[u64](ghash_bmul64(x1r, h1r))
    z2h := cast[u64](ghash_bmul64(x2r, h2r))
    z2 = z2 ~ z0 ~ z1
    z2h = z2h ~ z0h ~ z1h
    z0h = cast[u64](ghash_reverse(cast[SecretWord](z0h))) >> 1
    z1h = cast[u64](ghash_reverse(cast[SecretWord](z1h))) >> 1
    z2h = cast[u64](ghash_reverse(cast[SecretWord](z2h))) >> 1
    v0 := z0
    v1 := z0h ~ z2
    v2 := z1 ~ z2h
    v3 := z1h
    v3 = (v3 << 1) | (v2 >> 63)
    v2 = (v2 << 1) | (v1 >> 63)
    v1 = (v1 << 1) | (v0 >> 63)
    v0 = v0 << 1
    v2 = v2 ~ v0 ~ (v0 >> 1) ~ (v0 >> 2) ~ (v0 >> 7)
    v1 = v1 ~ (v0 << 63) ~ (v0 << 62) ~ (v0 << 57)
    v3 = v3 ~ v1 ~ (v1 >> 1) ~ (v1 >> 2) ~ (v1 >> 7)
    v2 = v2 ~ (v1 << 63) ~ (v1 << 62) ~ (v1 << 57)
    return Ghash.{high = v3, low = v2}
}

ghash_multiply #constant_time :: fn(x: Ghash, y: Ghash, hardware: bool) -> Ghash {
    #if TARGET_ARCH == .x86_64 {
        if hardware {
            return ghash_multiply_hardware(x, y)
        }
    }
    return ghash_multiply_software(x, y)
}

// One block encrypted in place: with AES-NI, or in software as the first of four.
aes256_encrypt_block #constant_time :: fn(gcm: ptr[Aes256Gcm], block: ptr[mut AesBlock]) {
    #if TARGET_ARCH == .x86_64 {
        if gcm.hardware {
            aes256_encrypt_hardware(&gcm.schedule, block)
            return void
        }
    }
    blocks : AesBlocks4
    for i in 0..<16 {
        blocks[i] = block[i]
    }
    aes256_encrypt4_software(&gcm.sliced, &blocks)
    for i in 0..<16 {
        block[i] = blocks[i]
    }
}

// Four blocks of keystream: the counter blocks for count to count + 3, encrypted.
gcm_keystream #constant_time :: fn(gcm: ptr[Aes256Gcm], nonce: ptr[Nonce96], count: u32, stream: ptr[mut AesBlocks4]) {
    for b in 0..<4 {
        counter := gcm_counter(nonce, count + cast[u32](b))
        for i in 0..<16 {
            stream[16 * b + i] = counter[i]
        }
    }
    #if TARGET_ARCH == .x86_64 {
        if gcm.hardware {
            aes256_encrypt4_hardware(&gcm.schedule, stream)
            return void
        }
    }
    aes256_encrypt4_software(&gcm.sliced, stream)
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
    if !hardware {
        gcm.sliced = aes256_slice_schedule(&gcm.schedule)
    }
    zero : AesBlock
    aes256_encrypt_block(&gcm, &zero)
    gcm.hash_key = ghash_of(&zero)
    gcm.hash_powers[0] = gcm.hash_key
    for i in 1..<4 {
        gcm.hash_powers[i] = ghash_multiply(gcm.hash_powers[i - 1], gcm.hash_key, hardware)
    }
    return gcm
}

// GHASH's running value, given public bytes: whole blocks straight from data, then the rest zero padded.
ghash_update #constant_time :: fn(gcm: ptr[Aes256Gcm], value: ptr[mut Ghash], data: u8[]) {
    at : usize = 0
    #if TARGET_ARCH == .x86_64 {
        if gcm.hardware {
            at = ghash_blocks4_hardware(gcm, value, data)
        }
    }
    // Never more than the count, which it already isn't, so adding a block to it can't wrap
    if at > data.count {
        at = data.count
    }
    loop {
        high : u64 = 0
        low : u64 = 0
        for j in cast[usize](0)..<8 {
            high = (high << 8) | cast[u64](data[at + j])
            low = (low << 8) | cast[u64](data[at + 8 + j])
        }
        value.high = value.high ~ high
        value.low = value.low ~ low
        value^ = ghash_multiply(value^, gcm.hash_key, gcm.hardware)
        at += 16
    }
    while at + 16 <= data.count
    if at < data.count {
        block : AesBlock
        for i in at..<data.count {
            block[(i - at) % 16] = data[i]
        }
        addend := ghash_of(&block)
        value.high = value.high ~ addend.high
        value.low = value.low ~ addend.low
        value^ = ghash_multiply(value^, gcm.hash_key, gcm.hardware)
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
    aes256_encrypt_block(gcm, &first)
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
    stream : AesBlocks4
    at : usize = 0
    // Four blocks at a time, so the loop over their bytes can be vectorized
    loop {
        gcm_keystream(&gcm, nonce, cast[u32](at / 16 + 2), &stream)
        chunk := plaintext[at..<plaintext.count]
        out := ciphertext[at..<ciphertext.count]
        for i in cast[usize](0)..<64 {
            if i < chunk.count && i < out.count {
                out[i] = compiler.declassify(cast[u8](chunk[i]) ~ stream[i])
            }
        }
        at += 64
    }
    while at < plaintext.count
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
    stream : AesBlocks4
    at : usize = 0
    loop {
        gcm_keystream(&gcm, nonce, cast[u32](at / 16 + 2), &stream)
        chunk := ciphertext[at..<ciphertext.count]
        out := plaintext[at..<plaintext.count]
        for i in cast[usize](0)..<64 {
            if i < chunk.count && i < out.count {
                out[i] = cast[SecretByte](chunk[i] ~ stream[i])
            }
        }
        at += 64
    }
    while at < ciphertext.count
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

    AesLanes4 :: distinct alias v128[4] #secret

    /*
     * Four blocks encrypted at once, each round on all four before the next, so the CPU works on them
     * together rather than waiting for each round's result.
     */
    aes256_encrypt4_hardware #constant_time #target_features("aes") :: fn(schedule: ptr[AesSchedule], blocks: ptr[mut AesBlocks4]) {
        keys := bit_cast[AesRoundKeys](schedule^)
        state := bit_cast[AesLanes4](blocks^)
        for b in 0..<4 {
            state[b] = state[b] ~ keys[0]
        }
        for round in 1..<14 {
            for b in 0..<4 {
                state[b] = x86_64.aes_encrypt_round(state[b], keys[round])
            }
        }
        for b in 0..<4 {
            state[b] = x86_64.aes_encrypt_last(state[b], keys[14])
        }
        blocks^ = bit_cast[AesBlocks4](state)
    }

    // A 256-bit carry-less product, its low half then its high half, before it's reduced
    GhashWide :: distinct alias vector[u64, 2][2] #secret

    // GHASH's multiply with PCLMULQDQ (Intel's carry-less multiplication white paper), on values held
    // as one 128-bit big-endian integer, its low half in lane 0: the product, then reduced.
    ghash_multiply_hardware #constant_time #target_features("pclmul") :: fn(x: Ghash, y: Ghash) -> Ghash {
        return ghash_reduce_hardware(ghash_product_hardware(x, y))
    }

    ghash_product_hardware #constant_time #target_features("pclmul") :: fn(x: Ghash, y: Ghash) -> GhashWide {
        a := bit_cast[v128](vector[u64, 2].{x.low, x.high})
        b := bit_cast[v128](vector[u64, 2].{y.low, y.high})
        t3 := bit_cast[vector[u64, 2]](x86_64.carryless_multiply(a, b, 0x00))
        t4 := bit_cast[vector[u64, 2]](x86_64.carryless_multiply(a, b, 0x10))
        t5 := bit_cast[vector[u64, 2]](x86_64.carryless_multiply(a, b, 0x01))
        t6 := bit_cast[vector[u64, 2]](x86_64.carryless_multiply(a, b, 0x11))
        t4 = t4 ~ t5
        wide : GhashWide
        wide[0] = t3 ~ vector[u64, 2].{0, t4[0]}
        wide[1] = t6 ~ vector[u64, 2].{t4[1], 0}
        return wide
    }

    // A product reduced mod x^128 + x^7 + x^2 + x + 1, as GHASH's bit order has it.
    ghash_reduce_hardware #constant_time #target_features("pclmul") :: fn(wide: GhashWide) -> Ghash {
        t3 := wide[0]
        t6 := wide[1]
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

    /*
     * Four blocks at a time from at, while there are four: (value ~ x0) * H^4 ~ x1 * H^3 ~ x2 * H^2 ~ x3 * H, the
     * products added before one reduction, since reducing is linear. The products don't wait on each other.
     */
    ghash_blocks4_hardware #constant_time #target_features("pclmul") :: fn(gcm: ptr[Aes256Gcm], value: ptr[mut Ghash], data: u8[]) -> usize {
        start : usize = 0
        loop {
            group : u8[64]
            for j in cast[usize](0)..<64 {
                group[j] = data[start + j]
            }
            sum : GhashWide
            for b in cast[usize](0)..<4 {
                high : u64 = 0
                low : u64 = 0
                for j in cast[usize](0)..<8 {
                    high = (high << 8) | cast[u64](group[(16 * b + j) % 64])
                    low = (low << 8) | cast[u64](group[(16 * b + 8 + j) % 64])
                }
                block := Ghash.{high = high, low = low}
                if b == 0 {
                    block.high = block.high ~ value.high
                    block.low = block.low ~ value.low
                }
                product := ghash_product_hardware(block, gcm.hash_powers[(3 - b) % 4])
                sum[0] = sum[0] ~ product[0]
                sum[1] = sum[1] ~ product[1]
            }
            value^ = ghash_reduce_hardware(sum)
            start += 64
        }
        while start + 64 <= data.count
        return start
    }
}
