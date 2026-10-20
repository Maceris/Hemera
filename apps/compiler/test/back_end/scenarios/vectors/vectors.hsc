/*
 * Vectors (docs/types.md, Vectors): literals, lanes, operators lane by lane, vectors in structs and
 * arrays, bit_cast through v128, base/intrinsics' vector and bit functions, and on a CPU with AES-NI
 * and PCLMULQDQ, x86_64's AES and carryless multiply in #target_features functions, against FIPS-197's
 * AES-128 example. main returns 42 if they all worked.
 */
package vectors_test

import intrinsics from "base"
import x86_64 from "base/intrinsics"

Words :: vector[u32, 4]

Holder :: struct {
    tag: u8,
    lanes: Words,
}

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

sum :: fn(v: Words) -> u32 {
    return v[0] + v[1] + v[2] + v[3]
}

operators :: fn() -> int {
    errors := 0
    a := Words.{1, 2, 3, 4}
    b := Words.{10, 20, 30, 40}
    c := a + b
    errors += check(c[0] == 11 && c[3] == 44, 1)
    d := c * 2 - 1
    errors += check(d[1] == 43, 2)
    e := a << 4
    errors += check(e[2] == 48, 3)
    shifts := Words.{0, 1, 2, 3}
    f := b >> shifts
    errors += check(f[0] == 10 && f[1] == 10 && f[2] == 7 && f[3] == 5, 4)
    g := a ~ b
    errors += check(g[0] == 11, 5)
    h := ~a
    errors += check(h[0] == 0xffff_fffe, 6)
    less := a < Words.{2, 2, 2, 2}
    errors += check(less[0] && !less[1] && !less[2], 7)
    flipped := ~less
    errors += check(!flipped[0] && flipped[3], 8)
    both := less & flipped
    errors += check(!both[0] && !both[1], 9)
    a[2] = 100
    errors += check(sum(a) == 107, 10)
    zero := Words.{}
    errors += check(sum(zero) == 0, 11)
    floats := vector[f32, 4].{1.5, 2.5, 3.5, 4.5}
    halves := floats / 2
    errors += check(halves[0] == 0.75, 12)
    negated := -floats
    errors += check(negated[3] == -4.5, 13)
    bytes := vector[u8, 16].{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}
    bits := bit_cast[v128](bytes)
    masked := bits & bit_cast[v128](vector[u8, 16].{0xff, 0, 0xff, 0, 0xff, 0, 0xff, 0, 0xff, 0, 0xff, 0, 0xff, 0, 0xff, 0})
    back := bit_cast[vector[u8, 16]](masked)
    errors += check(back[0] == 1 && back[1] == 0 && back[2] == 3 && back[15] == 0, 14)
    holder := Holder.{tag = 7, lanes = b}
    errors += check(holder.lanes[3] == 40 && size_of(Holder) == 32, 15)
    many : Words[3]
    many[1] = a
    errors += check(many[1][2] == 100, 16)
    signed := vector[i16, 8].{-1, 2, -3, 4, -5, 6, -7, 8}
    halved := signed >> 1
    errors += check(halved[0] == -1 && halved[2] == -2, 17)
    return errors
}

vector_intrinsics :: fn() -> int {
    errors := 0
    sevens := intrinsics.splat[Words](7)
    errors += check(sevens[0] == 7 && sevens[3] == 7, 1)
    a := Words.{1, 2, 3, 4}
    b := Words.{10, 20, 30, 40}
    picked := intrinsics.select(a > Words.{2, 2, 2, 2}, a, b)
    errors += check(picked[0] == 10 && picked[1] == 20 && picked[2] == 3 && picked[3] == 4, 2)
    moved := intrinsics.rotate_lanes(a, 1)
    errors += check(moved[0] == 2 && moved[3] == 1, 3)
    errors += check(intrinsics.reduce_add(a) == 10, 4)
    errors += check(intrinsics.reduce_xor(a) == 4, 5)
    errors += check(intrinsics.reduce_or(a) == 7 && intrinsics.reduce_and(b) == 0, 6)
    errors += check(intrinsics.any_true(a > Words.{3, 3, 3, 3}) && !intrinsics.all_true(a > Words.{3, 3, 3, 3}), 7)
    word : u32 = 0x8000_0001
    errors += check(intrinsics.rotate_left(word, 1) == 3, 8)
    errors += check(intrinsics.rotate_right(word, 1) == 0xc000_0000, 9)
    errors += check(intrinsics.byte_swap(cast[u32](0x1122_3344)) == 0x4433_2211, 10)
    lanes := intrinsics.rotate_left(Words.{0x8000_0000, 1, 2, 0xffff_ffff}, 4)
    errors += check(lanes[0] == 8 && lanes[1] == 16 && lanes[3] == 0xffff_ffff, 11)
    swapped := intrinsics.byte_swap(Words.{0x0102_0304, 0, 0, 0})
    errors += check(swapped[0] == 0x0403_0201, 12)
    wide : u64 = 0x0123_4567_89ab_cdef
    errors += check(intrinsics.rotate_right(wide, 8) == 0xef01_2345_6789_abcd, 13)
    return errors
}

// The next AES-128 round key from this one and what aes_key_assist gave for it
next_key :: fn(key: v128, assist: v128) -> v128 {
    w := bit_cast[Words](key)
    t := bit_cast[Words](assist)[3]
    w[0] = w[0] ~ t
    w[1] = w[1] ~ w[0]
    w[2] = w[2] ~ w[1]
    w[3] = w[3] ~ w[2]
    return bit_cast[v128](w)
}

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

encrypt #target_features("aes") :: fn(keys: ptr[v128[11]], block: v128) -> v128 {
    state := block ~ keys[0]
    for round in 1..<10 {
        state = x86_64.aes_encrypt_round(state, keys[round])
    }
    return x86_64.aes_encrypt_last(state, keys[10])
}

decrypt #target_features("aes") :: fn(keys: ptr[v128[11]], block: v128) -> v128 {
    state := block ~ keys[10]
    state = x86_64.aes_decrypt_round(state, x86_64.aes_inverse_mix(keys[9]))
    state = x86_64.aes_decrypt_round(state, x86_64.aes_inverse_mix(keys[8]))
    state = x86_64.aes_decrypt_round(state, x86_64.aes_inverse_mix(keys[7]))
    state = x86_64.aes_decrypt_round(state, x86_64.aes_inverse_mix(keys[6]))
    state = x86_64.aes_decrypt_round(state, x86_64.aes_inverse_mix(keys[5]))
    state = x86_64.aes_decrypt_round(state, x86_64.aes_inverse_mix(keys[4]))
    state = x86_64.aes_decrypt_round(state, x86_64.aes_inverse_mix(keys[3]))
    state = x86_64.aes_decrypt_round(state, x86_64.aes_inverse_mix(keys[2]))
    state = x86_64.aes_decrypt_round(state, x86_64.aes_inverse_mix(keys[1]))
    return x86_64.aes_decrypt_last(state, keys[0])
}

multiply #target_features("pclmul") :: fn(a: v128, b: v128) -> v128 {
    return x86_64.carryless_multiply(a, b, 0x00)
}

same :: fn(a: v128, b: u8[16]) -> bool {
    bytes := bit_cast[u8[16]](a)
    for i in 0..<16 {
        if bytes[i] != b[i] {
            return false
        }
    }
    return true
}

aes :: fn() -> int {
    features := x86_64.cpuid(1)
    if (features.ecx & (1 << 25)) == 0 || (features.ecx & (1 << 1)) == 0 {
        return 0
    }
    keys : v128[11]
    expand(&keys, bit_cast[v128](u8.[0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f]))
    plain := u8.[0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]
    cipher := encrypt(&keys, bit_cast[v128](plain))
    if !same(cipher, u8.[0x69, 0xc4, 0xe0, 0xd8, 0x6a, 0x7b, 0x04, 0x30, 0xd8, 0xcd, 0xb7, 0x80, 0x70, 0xb4, 0xc5, 0x5a]) {
        return 1
    }
    if !same(decrypt(&keys, cipher), plain) {
        return 2
    }
    product := multiply(bit_cast[v128](vector[u64, 2].{0x8000_0000_0000_0001, 0}), bit_cast[v128](vector[u64, 2].{2, 0}))
    lanes := bit_cast[vector[u64, 2]](product)
    if lanes[0] != 2 || lanes[1] != 1 {
        return 3
    }
    return 0
}

main :: fn() -> int {
    if operators() != 0 {
        return 100 + operators()
    }
    if vector_intrinsics() != 0 {
        return 120 + vector_intrinsics()
    }
    if aes() != 0 {
        return 140 + aes()
    }
    return 42
}
