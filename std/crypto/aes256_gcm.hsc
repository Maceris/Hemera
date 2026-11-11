package crypto

import compiler from "base"
import intrinsics from "base"

/*
 * AES (FIPS 197) and GCM (NIST SP 800-38D), and AES-256-GCM: encryption with a 32-byte key and a 12-byte
 * nonce, which must never be used twice with one key, and a 16-byte tag, like ChaCha20-Poly1305's (see
 * chacha20_poly1305.hsc, whose Key256, Nonce96 and Tag128 it shares). AES-128-GCM (aes128_gcm.hsc) and
 * AES-SIV (aes_siv.hsc) use the same AES, through AesKey.
 *
 * On an x86-64 CPU with AES-NI and PCLMULQDQ it uses them; otherwise AES and GHASH are worked out in
 * software, in constant time: AES bitsliced, four blocks at once, and GHASH with integer multiplies that
 * can't carry into what's kept. A kernel built without vector state passes hardware = false to the _with
 * functions, unless it saves the vector registers around the call.
 */

/**
 * AES's round constants, Rcon (FIPS 197, section 5.2), by the round key word they're for divided by 8: entries 1 to
 * 7 are used, and entry 0 isn't.
 */
AES_ROUND_CONSTANTS :: u8.[0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40]

/**
 * An AES key's round keys, each 16 bytes in the order AES uses them: AES-128's 11 in the first 176 bytes, the rest
 * zero, or AES-256's 15. Secret, as they're the key expanded.
 */
AesSchedule :: distinct alias u8[240] #secret
/** One 16-byte AES block, secret: a block of plaintext, keystream or a counter being encrypted. */
AesBlock :: distinct alias u8[16] #secret

/** A GHASH value, an element of GF(2^128) as GCM orders its bits, held as two big-endian halves. */
Ghash :: struct #secret {
    /** The value's first 8 bytes, big-endian. */
    high: u64,
    /** The value's last 8 bytes, big-endian. */
    low: u64,
}

/**
 * An AES key ready to encrypt with: its round keys, laid out for AES-NI or for bitsliced software. Secret
 * throughout; nothing wipes it when it's done with.
 */
AesKey :: struct {
    /** The round keys, from aes128_expand or aes256_expand. */
    schedule: AesSchedule,
    /** The round keys as bit planes, for software; only made, and only used, when hardware is false. */
    sliced: AesSlicedSchedule,
    /** How many rounds: 10 for AES-128, 14 for AES-256. */
    rounds: usize,
    /** Whether AES-NI is used; if not, AES is worked out in software. */
    hardware: bool,
}

/** AES-GCM's state for one key: the AES key, and GHASH's key and its powers. Secret throughout. */
AesGcm :: struct {
    /** The AES key, AES-128's or AES-256's. */
    aes: AesKey,
    /** GHASH's key, H: a block of zeros encrypted. */
    hash_key: Ghash,
    /** H, H^2, H^3 and H^4, so GHASH can take four blocks with one reduction. */
    hash_powers: Ghash[4],
    /** Whether PCLMULQDQ is used for GHASH; if not, GHASH is worked out in software. The AES key says for AES. */
    hardware: bool,
}

/** Eight bit planes, plane k holding bit k of each of the up to 64 bytes the planes are carrying. */
AesPlanes :: distinct alias u64[8] #secret

/**
 * Put every byte the planes carry through AES's S-box at once.
 *
 * It's Boyar and Peralta's circuit (the one BearSSL uses): the field inverse and the affine map as about 115 ands
 * and xors, with no table, so nothing depends on the bytes but the bytes.
 *
 * @param q The planes, changed in place.
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

/**
 * Put one byte through AES's S-box, in constant time, as one bit of each plane.
 *
 * @param x The byte to substitute, any of the 256 values; secret, and nothing branches on it or indexes with it.
 * @return Its substitution, secret.
 */
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

/**
 * Multiply by 2 in AES's field, GF(2^8) modulo x^8 + x^4 + x^3 + x + 1 (FIPS 197's xtime), without a branch.
 *
 * @param a Any byte, read as a polynomial over GF(2), bit k the coefficient of x^k; secret.
 * @return The product, a times 2, secret.
 */
aes_double #constant_time :: fn(a: SecretByte) -> SecretByte {
    value := cast[u8](a)
    return cast[SecretByte]((value << 1) ~ (0x1b & (cast[u8](0) - (value >> 7))))
}

/**
 * Expand an AES-256 key into its round keys (FIPS 197, section 5.2), in constant time.
 *
 * @param key The 32-byte key.
 * @return The 15 round keys, secret; the first two are the key itself.
 */
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

/** Four blocks, one after another: what bitsliced AES works on at once. */
AesBlocks4 :: distinct alias u8[64] #secret
/** The round keys as bit planes, each byte repeated for the four blocks: up to 15 rounds of 8 planes. */
AesSlicedSchedule :: distinct alias u64[120] #secret

/*
 * Bitsliced AES (like BearSSL's, laid out its own way): four blocks' 64 bytes as eight 64-bit planes, plane k
 * holding bit k of every byte. Byte position p (row r + 4 * column c, as AES numbers a block's bytes) of block b
 * is bit 4 * p + b, so each column is 16 bits of a plane, and each row a nibble of each column. Every step is
 * ands, xors, shifts and rotations of whole planes: no table, nothing that depends on the bytes but the bytes.
 */

/**
 * Transpose an 8 by 8 bit matrix (Hacker's Delight, 7-3).
 *
 * @param word The matrix, a byte a row, row 0 the least significant byte.
 * @return The matrix turned, so that byte k holds bit k of each row; doing it twice gives word back.
 */
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

/**
 * Spread a byte's bits out four apart: bit j to bit 4 * j.
 *
 * @param word The byte, in the low 8 bits, the rest 0.
 * @return The spread bits, in the low 32; aes_gather undoes it.
 */
aes_spread #constant_time :: fn(word: SecretWord) -> SecretWord {
    x := cast[u64](word)
    y := (x ~ (x << 12)) & 0x000f_000f
    y = (y ~ (y << 6)) & 0x0303_0303
    return cast[SecretWord]((y ~ (y << 3)) & 0x1111_1111)
}

/**
 * Gather bits four apart back into a byte: bit 4 * j to bit j, aes_spread the other way.
 *
 * @param word The bits; only bits 4 * j, for j from 0 to 7, are read.
 * @return The byte, in the low 8 bits.
 */
aes_gather #constant_time :: fn(word: SecretWord) -> SecretWord {
    x := cast[u64](word)
    y := x & 0x1111_1111
    y = (y ~ (y >> 3)) & 0x0303_0303
    y = (y ~ (y >> 6)) & 0x000f_000f
    return cast[SecretWord]((y ~ (y >> 12)) & 0xff)
}

/**
 * Pack four blocks into bit planes, as bitsliced AES lays them out: byte position p of block b is bit 4 * p + b.
 *
 * @param blocks The 64 bytes to pack, block b at bytes 16 * b to 16 * b + 15; read, not changed.
 * @param q Where the planes go, all eight overwritten.
 */
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

/**
 * Unpack bit planes into four blocks: aes_pack the other way.
 *
 * @param q The planes to unpack, laid out as aes_pack lays them out; read, not changed.
 * @param blocks Where the four blocks go, all 64 bytes overwritten.
 */
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

/**
 * Do AES's ShiftRows on the planes' four blocks: row r of each column moves left by r columns, so in a plane, row
 * r's nibbles rotate by 16 * r bits.
 *
 * @param q The planes, changed in place.
 */
aes_shift_rows #constant_time :: fn(q: ptr[mut AesPlanes]) {
    for k in 0..<8 {
        x := q[k]
        q[k] = (x & 0x000f_000f_000f_000f) | intrinsics.rotate_right(x & 0x00f0_00f0_00f0_00f0, 16)
            | intrinsics.rotate_right(x & 0x0f00_0f00_0f00_0f00, 32) | intrinsics.rotate_right(x & 0xf000_f000_f000_f000, 48)
    }
}

/**
 * Move each column's rows up by 1, wrapping: row r + 1's nibble into row r's, within the column's 16 bits.
 *
 * @param word A plane: four 16-bit columns, each holding four 4-bit rows, row 0 in its lowest nibble.
 * @return The plane with each column's row r holding what row r + 1 held, and row 3 what row 0 held.
 */
aes_rows_up1 #constant_time :: fn(word: SecretWord) -> SecretWord {
    x := cast[u64](word)
    return cast[SecretWord](((x >> 4) & 0x0fff_0fff_0fff_0fff) | ((x << 12) & 0xf000_f000_f000_f000))
}

/**
 * Move each column's rows up by 2, wrapping: row r + 2's nibble into row r's, within the column's 16 bits.
 *
 * @param word A plane: four 16-bit columns, each holding four 4-bit rows, row 0 in its lowest nibble.
 * @return The plane with each column's row r holding what row r + 2 held, and rows 2 and 3 what rows 0 and 1 held.
 */
aes_rows_up2 #constant_time :: fn(word: SecretWord) -> SecretWord {
    x := cast[u64](word)
    return cast[SecretWord](((x >> 8) & 0x00ff_00ff_00ff_00ff) | ((x << 8) & 0xff00_ff00_ff00_ff00))
}

/**
 * Move each column's rows up by 3, wrapping: row r + 3's nibble into row r's, within the column's 16 bits.
 *
 * @param word A plane: four 16-bit columns, each holding four 4-bit rows, row 0 in its lowest nibble.
 * @return The plane with each column's row r holding what row r + 3 held, and rows 1 to 3 what rows 0 to 2 held.
 */
aes_rows_up3 #constant_time :: fn(word: SecretWord) -> SecretWord {
    x := cast[u64](word)
    return cast[SecretWord](((x >> 12) & 0x000f_000f_000f_000f) | ((x << 4) & 0xfff0_fff0_fff0_fff0))
}

/**
 * Do AES's MixColumns on the planes' four blocks.
 *
 * Each column's b_r = 2 * a_r ~ 3 * a_(r+1) ~ a_(r+2) ~ a_(r+3), as 2 * (a_r ~ a_(r+1)) ~ a_(r+1) ~ a_(r+2) ~
 * a_(r+3): doubling moves each plane up one, the top one back in where x^8 = x^4 + x^3 + x + 1 says.
 *
 * @param q The planes, changed in place.
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

/**
 * Lay the round keys out as bit planes, for bitsliced AES.
 *
 * @param schedule The round keys, from aes128_expand or aes256_expand.
 * @param rounds How many rounds the key has, 10 or 14, so rounds + 1 round keys are laid out; the rest stay zero.
 * @return The round keys as planes, each byte in all four blocks' bits for it; secret.
 */
aes_slice_schedule #constant_time :: fn(schedule: ptr[AesSchedule], rounds: usize) -> AesSlicedSchedule {
    sliced : AesSlicedSchedule
    for round in cast[usize](0)..<(rounds % 15) + 1 {
        for p in cast[usize](0)..<16 {
            byte := cast[u64](schedule[16 * round + p])
            for k in cast[usize](0)..<8 {
                bit := (byte >> cast[u64](k)) & 1
                sliced[8 * round + k] = sliced[8 * round + k] | ((cast[u64](0) - bit) & (cast[u64](0xf) << (4 * cast[u64](p))))
            }
        }
    }
    return sliced
}

/**
 * Encrypt four blocks at once with AES (FIPS 197, section 5.1), bitsliced, in constant time.
 *
 * @param sliced The round keys as planes, from aes_slice_schedule.
 * @param rounds How many rounds: 10 for AES-128, 14 for AES-256; public.
 * @param blocks The four blocks, encrypted in place.
 */
aes_encrypt4_software #constant_time :: fn(sliced: ptr[AesSlicedSchedule], rounds: usize, blocks: ptr[mut AesBlocks4]) {
    q : AesPlanes
    aes_pack(blocks, &q)
    for k in 0..<8 {
        q[k] = q[k] ~ sliced[k]
    }
    last := rounds % 15
    for round in cast[usize](1)..<last + 1 {
        aes_sbox_planes(&q)
        aes_shift_rows(&q)
        if round < last {
            aes_mix_columns(&q)
        }
        for k in cast[usize](0)..<8 {
            q[k] = q[k] ~ sliced[(8 * round + k) % 120]
        }
    }
    aes_unpack(&q, blocks)
}

/**
 * Reverse a word's bits.
 *
 * @param word Any 64-bit value, all of it read; secret, and nothing branches on it.
 * @return Its 64 bits in the other order: bit 0 becomes bit 63.
 */
ghash_reverse #constant_time :: fn(word: SecretWord) -> SecretWord {
    x := cast[u64](word)
    y := ((x >> 1) & 0x5555_5555_5555_5555) | ((x & 0x5555_5555_5555_5555) << 1)
    y = ((y >> 2) & 0x3333_3333_3333_3333) | ((y & 0x3333_3333_3333_3333) << 2)
    y = ((y >> 4) & 0x0f0f_0f0f_0f0f_0f0f) | ((y & 0x0f0f_0f0f_0f0f_0f0f) << 4)
    return cast[SecretWord](intrinsics.byte_swap(y))
}

/**
 * Multiply two words carry-lessly with integer multiplies, in constant time (BearSSL's ghash_ctmul64).
 *
 * Each operand is split into every fourth bit, so the carries a multiply makes land in bits the masks throw away.
 *
 * @param a One factor, any 64-bit value, read as a polynomial over GF(2), bit k the coefficient of x^k; secret.
 * @param b The other factor, read the same way; the product doesn't depend on which is which.
 * @return The low 64 bits of their carry-less product.
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

/**
 * Multiply in GHASH's field in software, in constant time.
 *
 * Three 64-bit products for the low halves and three for the high ones, the latter from the bits reversed
 * (Karatsuba), then shifted and reduced by x^128 + x^7 + x^2 + x + 1.
 *
 * @param x One factor, any GHASH value, as GCM orders its bits: high's top bit is x^0's coefficient.
 * @param y The other factor, any GHASH value; GCM passes H or one of its powers here, though the product doesn't depend
 *     on which is which.
 * @return Their product, as NIST SP 800-38D defines it.
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

/**
 * Multiply in GHASH's field: with PCLMULQDQ when hardware says so, otherwise in software.
 *
 * @param x One factor, any GHASH value, as GCM orders its bits: high's top bit is x^0's coefficient.
 * @param y The other factor, any GHASH value; GCM passes H or one of its powers here, though the product doesn't depend
 *     on which is which.
 * @param hardware Whether to use PCLMULQDQ, which only an x86-64 CPU that has it may be told; on other targets it's
 *     ignored.
 * @return Their product, as NIST SP 800-38D defines it; the same whether worked out with PCLMULQDQ or in software.
 */
ghash_multiply #constant_time :: fn(x: Ghash, y: Ghash, hardware: bool) -> Ghash {
    #if TARGET_ARCH == .x86_64 {
        if hardware {
            return ghash_multiply_hardware(x, y)
        }
    }
    return ghash_multiply_software(x, y)
}

/**
 * Make an AES key ready to encrypt with, from its round keys.
 *
 * @param schedule The round keys, from aes128_expand or aes256_expand; copied.
 * @param rounds How many rounds: 10 for AES-128's schedule, 14 for AES-256's.
 * @param hardware Whether AES-NI is used, which only a CPU that has it, as aes_hardware says, may be told; if not,
 *     the round keys are laid out as bit planes for software.
 * @return The key, secret throughout; nothing wipes it when it's done with.
 */
aes_key #constant_time :: fn(schedule: AesSchedule, rounds: usize, hardware: bool) -> AesKey {
    aes := AesKey.{schedule = schedule, rounds = rounds, hardware = hardware}
    if !hardware {
        aes.sliced = aes_slice_schedule(&aes.schedule, rounds)
    }
    return aes
}

/**
 * Encrypt one block with AES: with AES-NI when the key says so, or in software as the first of four.
 *
 * @param aes The key, from aes_key.
 * @param block The block, encrypted in place.
 */
aes_encrypt_block #constant_time :: fn(aes: ptr[AesKey], block: ptr[mut AesBlock]) {
    #if TARGET_ARCH == .x86_64 {
        if aes.hardware {
            aes_encrypt_hardware(&aes.schedule, aes.rounds, block)
            return void
        }
    }
    blocks : AesBlocks4
    for i in 0..<16 {
        blocks[i] = block[i]
    }
    aes_encrypt4_software(&aes.sliced, aes.rounds, &blocks)
    for i in 0..<16 {
        block[i] = blocks[i]
    }
}

/**
 * Encrypt four blocks at once with AES: with AES-NI when the key says so, or bitsliced in software.
 *
 * @param aes The key, from aes_key.
 * @param blocks The four blocks, one after another, encrypted in place, each on its own (as ECB would).
 */
aes_encrypt4 #constant_time :: fn(aes: ptr[AesKey], blocks: ptr[mut AesBlocks4]) {
    #if TARGET_ARCH == .x86_64 {
        if aes.hardware {
            aes_encrypt4_hardware(&aes.schedule, aes.rounds, blocks)
            return void
        }
    }
    aes_encrypt4_software(&aes.sliced, aes.rounds, blocks)
}

/**
 * Make four blocks of GCM's keystream: the counter blocks for count to count + 3, encrypted.
 *
 * @param gcm The state, whose round keys are used.
 * @param nonce The 12-byte nonce the message is sealed with: the first 12 bytes of every counter block; read, not
 *     changed.
 * @param count The first block's counter: 2 for the message's first block, as 1 is the tag's. It wraps past
 *     2^32 - 1, which AES_GCM_MOST keeps a message from reaching.
 * @param stream Where the 64 bytes of keystream go.
 */
gcm_keystream #constant_time :: fn(gcm: ptr[AesGcm], nonce: ptr[Nonce96], count: u32, stream: ptr[mut AesBlocks4]) {
    for b in 0..<4 {
        counter := gcm_counter(nonce, count + cast[u32](b))
        for i in 0..<16 {
            stream[16 * b + i] = counter[i]
        }
    }
    aes_encrypt4(&gcm.aes, stream)
}

/**
 * Check whether AES-NI and PCLMULQDQ are there to use.
 *
 * @return Whether the CPU is x86-64 and has both (cpuid leaf 1, ecx bits 25 and 1); false on other targets. They
 *     use the vector registers, which a kernel without vector state can't, so it passes false to the _with functions
 *     instead of asking.
 */
aes_hardware :: fn() -> bool {
    #if TARGET_ARCH == .x86_64 {
        features := x86_64.cpuid(1)
        return (features.ecx & (1 << 25)) != 0 && (features.ecx & (1 << 1)) != 0
    }
    #else {
        return false
    }
}

/**
 * Read a block as a GHASH value.
 *
 * @param block Any 16 bytes: bytes 0 to 7 become the high half, 8 to 15 the low; read, not changed.
 * @return The value, its halves read big-endian.
 */
ghash_of #constant_time :: fn(block: ptr[AesBlock]) -> Ghash {
    value := Ghash.{high = 0, low = 0}
    for i in 0..<8 {
        value.high = (value.high << 8) | cast[u64](block[i])
        value.low = (value.low << 8) | cast[u64](block[8 + i])
    }
    return value
}

/**
 * Set up AES-GCM's state for a key: the AES key, and GHASH's key H and its powers.
 *
 * @param aes The AES key, AES-128's or AES-256's, from aes_key; copied into the state.
 * @param hardware Whether PCLMULQDQ is used, which only a CPU that has it, as aes_hardware says, may be told; the
 *     AES key says for itself whether AES-NI is.
 * @return The state, secret throughout; nothing wipes it when it's done with.
 */
aes_gcm_start #constant_time :: fn(aes: AesKey, hardware: bool) -> AesGcm {
    gcm := AesGcm.{aes = aes, hardware = hardware}
    zero : AesBlock
    aes_encrypt_block(&gcm.aes, &zero)
    gcm.hash_key = ghash_of(&zero)
    gcm.hash_powers[0] = gcm.hash_key
    for i in 1..<4 {
        gcm.hash_powers[i] = ghash_multiply(gcm.hash_powers[i - 1], gcm.hash_key, hardware)
    }
    return gcm
}

/**
 * Add public bytes to GHASH's running value: whole blocks straight from data, then the rest padded with zeros.
 *
 * @param gcm The state, whose hash key is used.
 * @param value The running value, updated in place.
 * @param data The bytes, of any number; a partial last block is padded with zeros, as GCM pads the associated data
 *     and the ciphertext.
 */
ghash_update #constant_time :: fn(gcm: ptr[AesGcm], value: ptr[mut Ghash], data: u8[]) {
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

/**
 * Make a GCM counter block: the nonce, then a 32-bit big-endian count.
 *
 * @param nonce The 12-byte nonce, copied into the block's first 12 bytes.
 * @param count The count: 1 for the block that masks the tag (J0), and 2 on for the message's blocks.
 * @return The counter block, to be encrypted.
 */
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

/**
 * Compute GCM's tag (NIST SP 800-38D, section 7.1): GHASH of the associated data and the ciphertext, each padded to
 * 16 bytes, then their lengths in bits, encrypted by XOR with the first counter block's encryption.
 *
 * @param gcm The state for the key.
 * @param nonce The nonce the ciphertext was sealed with.
 * @param associated The associated data, of any length, empty for none; hashed first, padded with zeros to whole
 *     blocks, and its length in bits goes into the last block.
 * @param ciphertext The ciphertext, up to AES_GCM_MOST bytes, empty allowed; hashed after the associated data,
 *     padded the same way, its length in bits beside the other's.
 * @return The 16-byte tag, a secret until it's compared or sent.
 */
gcm_tag #constant_time :: fn(gcm: ptr[AesGcm], nonce: ptr[Nonce96], associated: u8[], ciphertext: u8[]) -> SecretByte[16] {
    value := Ghash.{high = 0, low = 0}
    ghash_update(gcm, &value, associated)
    ghash_update(gcm, &value, ciphertext)
    value.high = value.high ~ (cast[u64](associated.count) * 8)
    value.low = value.low ~ (cast[u64](ciphertext.count) * 8)
    value = ghash_multiply(value, gcm.hash_key, gcm.hardware)
    first := gcm_counter(nonce, 1)
    aes_encrypt_block(&gcm.aes, &first)
    tag : SecretByte[16]
    for i in 0..<8 {
        shift := 56 - 8 * cast[u64](i)
        tag[i] = cast[SecretByte](cast[u8](value.high >> shift) ~ first[i])
        tag[8 + i] = cast[SecretByte](cast[u8](value.low >> shift) ~ first[8 + i])
    }
    return tag
}

/**
 * The most bytes an AES-GCM message can have: 2^32 - 2 blocks of 16 bytes, just under 64 GiB, as NIST SP 800-38D
 * limits a plaintext to 2^39 - 256 bits.
 */
AES_GCM_MOST :: 68_719_476_704
/** The most bytes an AES-256-GCM message can have: AES_GCM_MOST. */
AES256_GCM_MOST :: AES_GCM_MOST

/**
 * Encrypt and authenticate a message with AES-256-GCM (FIPS 197, NIST SP 800-38D).
 *
 * AES-NI and PCLMULQDQ are used when aes_hardware says the CPU has them; otherwise AES and GHASH are worked out in
 * software, in constant time. A kernel without vector state calls aes256_gcm_seal_with instead.
 *
 * @param key The 32-byte secret key, which whoever opens the message has too; read, not changed. Its expanded copy on
 *     the stack isn't wiped.
 * @param nonce The nonce, which must never have been used with this key before: a repeat gives away the XOR of the
 *     two plaintexts and GHASH's key, which lets tags be forged. A counter, or 12 random bytes, will do.
 * @param plaintext The message, up to AES256_GCM_MOST bytes; empty is allowed.
 * @param associated Data authenticated with the message but not encrypted, like a header sent in the clear, of any
 *     length; empty for none.
 * @param ciphertext Where the encrypted message goes, which has to have plaintext's count. It's public.
 * @param tag Where the tag goes, to be sent with the ciphertext.
 * @return True with ciphertext and tag written, or false, with nothing written, when the counts differ or the message
 *     is longer than AES256_GCM_MOST.
 */
aes256_gcm_seal #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], plaintext: SecretByte[], associated: u8[],
    ciphertext: mut u8[], tag: ptr[mut Tag128]) -> bool {

    return aes256_gcm_seal_with(key, nonce, plaintext, associated, ciphertext, tag, aes_hardware())
}

/**
 * Check and decrypt a message sealed with AES-256-GCM (FIPS 197, NIST SP 800-38D).
 *
 * The tag is checked first, in constant time, and the plaintext is only written once the ciphertext and the
 * associated data are found to be what was sealed. AES-NI and PCLMULQDQ are used when aes_hardware says the CPU has
 * them.
 *
 * @param key The key it was sealed with.
 * @param nonce The nonce it was sealed with.
 * @param ciphertext The encrypted message as sealing wrote it, up to AES256_GCM_MOST bytes; empty is allowed.
 * @param associated The associated data it was sealed with, which has to be the same bytes.
 * @param tag The tag that came with it.
 * @param plaintext Where the message goes, which has to have ciphertext's count.
 * @return True with plaintext written, or false, with nothing written, when the tag doesn't match (the ciphertext,
 *     the associated data, the nonce, the key or the tag is wrong: forged or damaged), the counts differ, or the
 *     ciphertext is longer than AES256_GCM_MOST.
 */
aes256_gcm_open #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], ciphertext: u8[], associated: u8[],
    tag: ptr[Tag128], plaintext: mut SecretByte[]) -> bool {

    return aes256_gcm_open_with(key, nonce, ciphertext, associated, tag, plaintext, aes_hardware())
}

/**
 * Encrypt and authenticate a message with AES-256-GCM, choosing whether AES-NI and PCLMULQDQ may be used.
 *
 * @param key The 32-byte secret key, which whoever opens the message has too; read, not changed. Its expanded copy on
 *     the stack isn't wiped.
 * @param nonce The nonce, which must never have been used with this key before: a repeat gives away the XOR of the
 *     two plaintexts and GHASH's key, which lets tags be forged.
 * @param plaintext The message, up to AES256_GCM_MOST bytes; empty is allowed.
 * @param associated Data authenticated with the message but not encrypted, of any length; empty for none.
 * @param ciphertext Where the encrypted message goes, which has to have plaintext's count. It's public.
 * @param tag Where the tag goes, to be sent with the ciphertext.
 * @param hardware Whether to use AES-NI and PCLMULQDQ, which only works on a CPU that has them, as aes_hardware says;
 *     a kernel without vector state gives false, unless it saves the vector registers around the call. The result is
 *     the same either way.
 * @return True with ciphertext and tag written, or false, with nothing written, when the counts differ or the message
 *     is longer than AES256_GCM_MOST.
 */
aes256_gcm_seal_with #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], plaintext: SecretByte[], associated: u8[],
    ciphertext: mut u8[], tag: ptr[mut Tag128], hardware: bool) -> bool {

    if plaintext.count != ciphertext.count || cast[u64](plaintext.count) > AES_GCM_MOST {
        return false
    }
    gcm := aes_gcm_start(aes_key(aes256_expand(key), 14, hardware), hardware)
    return aes_gcm_seal(&gcm, nonce, plaintext, associated, ciphertext, tag)
}

/**
 * Check and decrypt a message sealed with AES-256-GCM, choosing whether AES-NI and PCLMULQDQ may be used.
 *
 * The tag is checked first, in constant time, and the plaintext is only written once it matches.
 *
 * @param key The key it was sealed with.
 * @param nonce The nonce it was sealed with.
 * @param ciphertext The encrypted message as sealing wrote it, up to AES256_GCM_MOST bytes; empty is allowed.
 * @param associated The associated data it was sealed with, which has to be the same bytes.
 * @param tag The tag that came with it.
 * @param plaintext Where the message goes, which has to have ciphertext's count.
 * @param hardware Whether to use AES-NI and PCLMULQDQ, which only works on a CPU that has them; see
 *     aes256_gcm_seal_with.
 * @return True with plaintext written, or false, with nothing written, when the tag doesn't match (forged or
 *     damaged), the counts differ, or the ciphertext is longer than AES256_GCM_MOST.
 */
aes256_gcm_open_with #constant_time :: fn(key: ptr[Key256], nonce: ptr[Nonce96], ciphertext: u8[], associated: u8[],
    tag: ptr[Tag128], plaintext: mut SecretByte[], hardware: bool) -> bool {

    if plaintext.count != ciphertext.count || cast[u64](ciphertext.count) > AES_GCM_MOST {
        return false
    }
    gcm := aes_gcm_start(aes_key(aes256_expand(key), 14, hardware), hardware)
    return aes_gcm_open(&gcm, nonce, ciphertext, associated, tag, plaintext)
}

/**
 * Encrypt and authenticate a message with AES-GCM's state for a key, AES-128's or AES-256's.
 *
 * @param gcm The state, from aes_gcm_start.
 * @param nonce The nonce, never used with this key before.
 * @param plaintext The message, up to AES_GCM_MOST bytes; empty is allowed.
 * @param associated Data authenticated with the message but not encrypted, of any length; empty for none.
 * @param ciphertext Where the encrypted message goes, which has to have plaintext's count. It's public.
 * @param tag Where the tag goes.
 * @return True with ciphertext and tag written, or false, with nothing written, when the counts differ or the message
 *     is longer than AES_GCM_MOST.
 */
aes_gcm_seal #constant_time :: fn(gcm: ptr[AesGcm], nonce: ptr[Nonce96], plaintext: SecretByte[], associated: u8[],
    ciphertext: mut u8[], tag: ptr[mut Tag128]) -> bool {

    if plaintext.count != ciphertext.count || cast[u64](plaintext.count) > AES_GCM_MOST {
        return false
    }
    stream : AesBlocks4
    at : usize = 0
    // Four blocks at a time, so the loop over their bytes can be vectorized
    loop {
        gcm_keystream(gcm, nonce, cast[u32](at / 16 + 2), &stream)
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
    computed := gcm_tag(gcm, nonce, associated, ciphertext)
    for i in 0..<16 {
        tag[i] = compiler.declassify(cast[u8](computed[i]))
    }
    return true
}

/**
 * Check and decrypt a message with AES-GCM's state for a key, AES-128's or AES-256's: the tag first, in constant
 * time, and the plaintext only written once it matches.
 *
 * @param gcm The state, from aes_gcm_start.
 * @param nonce The nonce it was sealed with.
 * @param ciphertext The encrypted message, up to AES_GCM_MOST bytes; empty is allowed.
 * @param associated The associated data it was sealed with.
 * @param tag The tag that came with it.
 * @param plaintext Where the message goes, which has to have ciphertext's count.
 * @return True with plaintext written, or false, with nothing written, when the tag doesn't match, the counts differ,
 *     or the ciphertext is longer than AES_GCM_MOST.
 */
aes_gcm_open #constant_time :: fn(gcm: ptr[AesGcm], nonce: ptr[Nonce96], ciphertext: u8[], associated: u8[], tag: ptr[Tag128],
    plaintext: mut SecretByte[]) -> bool {

    if plaintext.count != ciphertext.count || cast[u64](ciphertext.count) > AES_GCM_MOST {
        return false
    }
    computed := gcm_tag(gcm, nonce, associated, ciphertext)
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
        gcm_keystream(gcm, nonce, cast[u32](at / 16 + 2), &stream)
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

    /** The schedule's round keys as AES-NI takes them, one 128-bit register each. */
    AesRoundKeys :: distinct alias v128[15] #secret

    /**
     * Encrypt one block with AES using AES-NI.
     *
     * @param schedule The round keys, from aes128_expand or aes256_expand.
     * @param rounds How many rounds: 10 for AES-128, 14 for AES-256.
     * @param block The block, encrypted in place. The CPU has to have AES-NI, as aes_hardware says.
     */
    aes_encrypt_hardware #constant_time #target_features("aes") :: fn(schedule: ptr[AesSchedule], rounds: usize, block: ptr[mut AesBlock]) {
        keys := bit_cast[AesRoundKeys](schedule^)
        last := rounds % 15
        state := bit_cast[v128](block^) ~ keys[0]
        for round in cast[usize](1)..<last {
            state = x86_64.aes_encrypt_round(state, keys[round])
        }
        state = x86_64.aes_encrypt_last(state, keys[last])
        block^ = bit_cast[AesBlock](state)
    }

    /** Four blocks in 128-bit registers, one each, for encrypting them together with AES-NI. */
    AesLanes4 :: distinct alias v128[4] #secret

    /**
     * Encrypt four blocks at once with AES using AES-NI, each round on all four before the next, so the CPU works on
     * them together rather than waiting for each round's result.
     *
     * @param schedule The round keys, from aes128_expand or aes256_expand.
     * @param rounds How many rounds: 10 for AES-128, 14 for AES-256.
     * @param blocks The four blocks, encrypted in place. The CPU has to have AES-NI, as aes_hardware says.
     */
    aes_encrypt4_hardware #constant_time #target_features("aes") :: fn(schedule: ptr[AesSchedule], rounds: usize, blocks: ptr[mut AesBlocks4]) {
        keys := bit_cast[AesRoundKeys](schedule^)
        last := rounds % 15
        state := bit_cast[AesLanes4](blocks^)
        for b in 0..<4 {
            state[b] = state[b] ~ keys[0]
        }
        for round in cast[usize](1)..<last {
            for b in 0..<4 {
                state[b] = x86_64.aes_encrypt_round(state[b], keys[round])
            }
        }
        for b in 0..<4 {
            state[b] = x86_64.aes_encrypt_last(state[b], keys[last])
        }
        blocks^ = bit_cast[AesBlocks4](state)
    }

    /** A 256-bit carry-less product, its low half then its high half, before it's reduced. */
    GhashWide :: distinct alias vector[u64, 2][2] #secret

    /**
     * Multiply in GHASH's field with PCLMULQDQ (Intel's carry-less multiplication white paper), on values held as one
     * 128-bit big-endian integer, its low half in lane 0: the product, then reduced.
     *
     * @param x One factor, any GHASH value.
     * @param y The other factor, any GHASH value; the product doesn't depend on which is which. The CPU has to have
     *     PCLMULQDQ, as aes_hardware says.
     * @return Their product, reduced: the same value ghash_multiply_software gives.
     */
    ghash_multiply_hardware #constant_time #target_features("pclmul") :: fn(x: Ghash, y: Ghash) -> Ghash {
        return ghash_reduce_hardware(ghash_product_hardware(x, y))
    }

    /**
     * Multiply two GHASH values carry-lessly with PCLMULQDQ, without reducing the product.
     *
     * @param x One factor, any GHASH value; for GHASH, a block of data, the first with the running value added.
     * @param y The other factor, any GHASH value; for GHASH, H or one of its powers. The CPU has to have PCLMULQDQ.
     * @return Their 256-bit carry-less product, for ghash_reduce_hardware; products can be XORed together before one
     *     reduction, as reducing is linear.
     */
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

    /**
     * Reduce a carry-less product modulo x^128 + x^7 + x^2 + x + 1, as GHASH's bit order has it.
     *
     * @param wide The product, from ghash_product_hardware, or several XORed together.
     * @return The product reduced modulo x^128 + x^7 + x^2 + x + 1, a GHASH value; for several products XORed together,
     *     the XOR of their reductions.
     */
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

    /**
     * Add data to GHASH's running value four blocks at a time, while there are four, with PCLMULQDQ.
     *
     * Each group is (value ~ x0) * H^4 ~ x1 * H^3 ~ x2 * H^2 ~ x3 * H, the products added before one reduction, since
     * reducing is linear. The products don't wait on each other.
     *
     * @param gcm The state, whose hash powers are used.
     * @param value The running value, updated in place.
     * @param data The bytes; only whole groups of 64 from its start are taken.
     * @return How many bytes were taken, a multiple of 64; the caller adds the rest.
     */
    ghash_blocks4_hardware #constant_time #target_features("pclmul") :: fn(gcm: ptr[AesGcm], value: ptr[mut Ghash], data: u8[]) -> usize {
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
                    high = (high << 8) | cast[u64](group[16 * b + j])
                    low = (low << 8) | cast[u64](group[16 * b + 8 + j])
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
