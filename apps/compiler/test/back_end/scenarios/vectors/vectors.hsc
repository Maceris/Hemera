/*
 * Vectors (docs/types.md, Vectors): literals, lanes, operators lane by lane, vectors in structs and
 * arrays, bit_cast through v128, base/intrinsics' vector and bit functions, and on an x86-64 CPU with
 * AES-NI and PCLMULQDQ, x86_64's AES and carryless multiply in #target_features functions, against
 * FIPS-197's AES-128 example.
 */
package vectors_test

import intrinsics from "base"
import testing from "std"

/** Four u32 lanes, 16 bytes. */
Words :: vector[u32, 4]

/** A vector in a struct, after a byte, so it's aligned past it. */
Holder :: struct {
    /** Any value. */
    tag: u8,
    /** Any lanes. */
    lanes: Words,
}

/**
 * Add a vector's lanes, one by one.
 *
 * @param v Any lanes.
 * @return Their sum, wrapping.
 */
sum :: fn(v: Words) -> u32 {
    return v[0] + v[1] + v[2] + v[3]
}

works_lane_by_lane #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a := Words.{1, 2, 3, 4}
    b := Words.{10, 20, 30, 40}
    c := a + b
    testing.expect(t, c[0] == 11 && c[3] == 44, "+ adds lane to lane")
    d := c * 2 - 1
    testing.expect_eq(t, d[1], 43, "a number with a vector is used in every lane")
    e := a << 4
    testing.expect_eq(t, e[2], 48, "<< by a number shifts every lane")
    shifts := Words.{0, 1, 2, 3}
    f := b >> shifts
    testing.expect(t, f[0] == 10 && f[1] == 10 && f[2] == 7 && f[3] == 5, ">> by a vector shifts each lane by its own count")
    g := a ~ b
    testing.expect_eq(t, g[0], 11, "~ between two is exclusive or, lane to lane")
    h := ~a
    testing.expect_eq(t, h[0], 0xffff_fffe, "~ alone flips every bit of every lane")
    less := a < Words.{2, 2, 2, 2}
    testing.expect(t, less[0] && !less[1] && !less[2], "< compares lane to lane, giving a lane of bool each")
    flipped := ~less
    testing.expect(t, !flipped[0] && flipped[3], "~ flips a mask's lanes")
    both := less & flipped
    testing.expect(t, !both[0] && !both[1], "& of a mask and its flip is false in every lane")
    a[2] = 100
    testing.expect_eq(t, sum(a), 107, "a lane is set by index")
    zero := Words.{}
    testing.expect_eq(t, sum(zero), 0, "a literal of nothing is zeros")
    return .Ok
}

works_on_floats_and_signed_lanes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    floats := vector[f32, 4].{1.5, 2.5, 3.5, 4.5}
    halves := floats / 2
    testing.expect_eq(t, halves[0], 0.75, "/ by a number divides every float lane")
    negated := -floats
    testing.expect_eq(t, negated[3], -4.5, "- alone negates every float lane")
    signed := vector[i16, 8].{-1, 2, -3, 4, -5, 6, -7, 8}
    halved := signed >> 1
    testing.expect(t, halved[0] == -1 && halved[2] == -2, ">> on signed lanes keeps their sign")
    return .Ok
}

keeps_vectors_in_structs_arrays_and_v128 #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    bytes := vector[u8, 16].{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}
    bits := bit_cast[v128](bytes)
    masked := bits & bit_cast[v128](vector[u8, 16].{0xff, 0, 0xff, 0, 0xff, 0, 0xff, 0, 0xff, 0, 0xff, 0, 0xff, 0, 0xff, 0})
    back := bit_cast[vector[u8, 16]](masked)
    testing.expect(t, back[0] == 1 && back[1] == 0 && back[2] == 3 && back[15] == 0, "bit_cast through v128 keeps every byte in place")
    b := Words.{10, 20, 30, 40}
    holder := Holder.{tag = 7, lanes = b}
    testing.expect_eq(t, holder.lanes[3], 40, "a vector in a struct keeps its lanes")
    testing.expect_eq(t, size_of(Holder), 32, "it's aligned to 16 bytes, past the byte before it")
    a := Words.{1, 2, 100, 4}
    many : Words[3]
    many[1] = a
    testing.expect_eq(t, many[1][2], 100, "a vector in an array is indexed lane by lane")
    return .Ok
}

uses_vector_intrinsics #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    sevens := intrinsics.splat[Words](7)
    testing.expect(t, sevens[0] == 7 && sevens[3] == 7, "splat puts the number in every lane")
    a := Words.{1, 2, 3, 4}
    b := Words.{10, 20, 30, 40}
    picked := intrinsics.select(a > Words.{2, 2, 2, 2}, a, b)
    testing.expect(t, picked[0] == 10 && picked[1] == 20 && picked[2] == 3 && picked[3] == 4, "select takes the first where the mask is true, the second elsewhere")
    moved := intrinsics.rotate_lanes(a, 1)
    testing.expect(t, moved[0] == 2 && moved[3] == 1, "rotate_lanes moves each lane down one, the first round to the last")
    testing.expect_eq(t, intrinsics.reduce_add(a), 10, "reduce_add adds every lane")
    testing.expect_eq(t, intrinsics.reduce_xor(a), 4, "reduce_xor is the lanes' exclusive or")
    testing.expect_eq(t, intrinsics.reduce_or(a), 7, "reduce_or is the lanes' or")
    testing.expect_eq(t, intrinsics.reduce_and(b), 0, "reduce_and is the lanes' and, which shares no bit here")
    testing.expect(t, intrinsics.any_true(a > Words.{3, 3, 3, 3}), "any_true: one lane is above 3")
    testing.expect(t, !intrinsics.all_true(a > Words.{3, 3, 3, 3}), "all_true: not every lane is")
    return .Ok
}

uses_bit_intrinsics #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    word : u32 = 0x8000_0001
    testing.expect_eq(t, intrinsics.rotate_left(word, 1), 3, "rotate_left carries the top bit round to the bottom")
    testing.expect_eq(t, intrinsics.rotate_right(word, 1), 0xc000_0000, "rotate_right carries the bottom bit round to the top")
    testing.expect_eq(t, intrinsics.byte_swap(cast[u32](0x1122_3344)), 0x4433_2211, "byte_swap reverses a word's bytes")
    lanes := intrinsics.rotate_left(Words.{0x8000_0000, 1, 2, 0xffff_ffff}, 4)
    testing.expect(t, lanes[0] == 8 && lanes[1] == 16 && lanes[3] == 0xffff_ffff, "rotate_left on a vector rotates each lane")
    swapped := intrinsics.byte_swap(Words.{0x0102_0304, 0, 0, 0})
    testing.expect_eq(t, swapped[0], 0x0403_0201, "byte_swap on a vector reverses each lane's bytes")
    wide : u64 = 0x0123_4567_89ab_cdef
    testing.expect_eq(t, intrinsics.rotate_right(wide, 8), 0xef01_2345_6789_abcd, "rotate_right works on 64 bits")
    return .Ok
}

encrypts_with_aes_instructions #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    check_aes(t)
    return .Ok
}

// x86-64's instructions, on x86-64 only
#if TARGET_ARCH == .x86_64 {
    import x86_64 from "base/intrinsics"

    /**
     * Make the next AES-128 round key.
     *
     * @param key This round's key.
     * @param assist What aes_key_assist gave for it.
     * @return The next round's key.
     */
    next_key :: fn(key: v128, assist: v128) -> v128 {
        w := bit_cast[Words](key)
        t := bit_cast[Words](assist)[3]
        w[0] = w[0] ~ t
        w[1] = w[1] ~ w[0]
        w[2] = w[2] ~ w[1]
        w[3] = w[3] ~ w[2]
        return bit_cast[v128](w)
    }

    /**
     * Expand an AES-128 key into its round keys.
     *
     * @param keys Where the 11 round keys go.
     * @param key The key.
     */
    expand #target_features("aes") :: fn(keys: ptr[mut v128[11]], key: v128) {
        keys[0] = key
        keys[1] = next_key(keys[0], x86_64.aes_key_assist(keys[0], 0x01))
        keys[2] = next_key(keys[1], x86_64.aes_key_assist(keys[1], 0x02))
        keys[3] = next_key(keys[2], x86_64.aes_key_assist(keys[2], 0x04))
        keys[4] = next_key(keys[3], x86_64.aes_key_assist(keys[3], 0x08))
        keys[5] = next_key(keys[4], x86_64.aes_key_assist(keys[4], 0x10))
        keys[6] = next_key(keys[5], x86_64.aes_key_assist(keys[5], 0x20))
        keys[7] = next_key(keys[6], x86_64.aes_key_assist(keys[6], 0x40))
        keys[8] = next_key(keys[7], x86_64.aes_key_assist(keys[7], 0x80))
        keys[9] = next_key(keys[8], x86_64.aes_key_assist(keys[8], 0x1b))
        keys[10] = next_key(keys[9], x86_64.aes_key_assist(keys[9], 0x36))
    }

    /**
     * Encrypt one block with AES-128.
     *
     * @param keys The round keys, from expand.
     * @param block The plain block.
     * @return The cipher block.
     */
    encrypt #target_features("aes") :: fn(keys: ptr[v128[11]], block: v128) -> v128 {
        state := block ~ keys[0]
        for round in 1..<10 {
            state = x86_64.aes_encrypt_round(state, keys[round])
        }
        return x86_64.aes_encrypt_last(state, keys[10])
    }

    /**
     * Decrypt one block with AES-128, through the equivalent inverse cipher.
     *
     * @param keys The round keys, from expand.
     * @param block The cipher block.
     * @return The plain block.
     */
    decrypt #target_features("aes") :: fn(keys: ptr[v128[11]], block: v128) -> v128 {
        state := block ~ keys[10]
        for round in 1..<10 #reverse {
            state = x86_64.aes_decrypt_round(state, x86_64.aes_inverse_mix(keys[round]))
        }
        return x86_64.aes_decrypt_last(state, keys[0])
    }

    /**
     * Multiply two blocks' low halves without carries.
     *
     * @param a A block, whose low 64 bits are used.
     * @param b Another.
     * @return Their 128-bit carryless product.
     */
    multiply #target_features("pclmul") :: fn(a: v128, b: v128) -> v128 {
        return x86_64.carryless_multiply(a, b, 0x00)
    }

    /**
     * Tell whether a block has the bytes expected.
     *
     * @param a The block.
     * @param b The bytes, in memory order.
     * @return True if every byte matches.
     */
    same :: fn(a: v128, b: u8[16]) -> bool {
        bytes := bit_cast[u8[16]](a)
        for i in 0..<16 {
            if bytes[i] != b[i] {
                return false
            }
        }
        return true
    }

    /**
     * Check AES-128 against FIPS-197's example, and a carryless multiply, where the CPU has AES-NI and PCLMULQDQ.
     *
     * @param t The test's state, which failures are recorded in; on a CPU without them, nothing is checked.
     */
    check_aes :: fn(t: ptr[mut testing.T]) {
        features := x86_64.cpuid(1)
        if (features.ecx & (1 << 25)) == 0 || (features.ecx & (1 << 1)) == 0 {
            return void
        }
        keys : v128[11]
        expand(&keys, bit_cast[v128](u8.[0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f]))
        plain := u8.[0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]
        cipher := encrypt(&keys, bit_cast[v128](plain))
        testing.expect(t, same(cipher, u8.[0x69, 0xc4, 0xe0, 0xd8, 0x6a, 0x7b, 0x04, 0x30, 0xd8, 0xcd, 0xb7, 0x80, 0x70, 0xb4, 0xc5, 0x5a]),
            "FIPS-197's AES-128 example encrypts to its cipher text")
        testing.expect(t, same(decrypt(&keys, cipher), plain), "and decrypts back to its plain text")
        product := multiply(bit_cast[v128](vector[u64, 2].{0x8000_0000_0000_0001, 0}), bit_cast[v128](vector[u64, 2].{2, 0}))
        lanes := bit_cast[vector[u64, 2]](product)
        testing.expect(t, lanes[0] == 2 && lanes[1] == 1, "x^63 + 1 times x is x^64 + x, past the low 64 bits")
    }
}
#else {
    /**
     * Check nothing: AES-NI and PCLMULQDQ are x86-64's.
     *
     * @param t The test's state, left as it is.
     */
    check_aes :: fn(t: ptr[mut testing.T]) {}
}
