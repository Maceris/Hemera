package crypto

import compiler from "base"
import intrinsics from "base"

/*
 * Curve25519's field, numbers mod p = 2^255 - 19, which X25519 and Ed25519 both work in, and X25519
 * (RFC 7748): key agreement, where each side's secret key and the other's public key give both the same
 * shared secret.
 *
 *     public_key := crypto.x25519_public_key(&secret_key)       // sent to the other side
 *     shared : crypto.SecretByte[32]
 *     if !crypto.x25519(&secret_key, &their_public_key, &shared) {
 *         // their key was a low-order point, which would give everyone the same secret
 *     }
 *
 * The shared secret isn't a key yet: put it through HKDF with what both sides saw.
 */

// An X25519 secret key, 32 random bytes.
X25519SecretKey :: distinct alias u8[32] #secret
// An X25519 public key, a point's u coordinate.
X25519PublicKey :: distinct alias u8[32]

/*
 * A field element: five 51-bit limbs, least significant first, each kept under 2^52 so a product of two
 * limbs and the sums of them fit in a u128.
 */
Fe :: distinct alias u64[5] #secret

// Five limbs' worth of products, before they're carried down.
FeWide :: distinct alias u128[5] #secret

FE_MASK :: 0x7_ffff_ffff_ffff

// 4p, in limbs, added before subtracting so no limb goes below 0.
FE_FOUR_P :: u64.[0x1f_ffff_ffff_ffb4, 0x1f_ffff_ffff_fffc, 0x1f_ffff_ffff_fffc, 0x1f_ffff_ffff_fffc, 0x1f_ffff_ffff_fffc]

fe_of #constant_time :: fn(limbs: u64[5]) -> Fe {
    f : Fe
    for i in 0..<5 {
        f[i] = limbs[i]
    }
    return f
}

// Each limb's carry into the next, and the top one's, times 19, into the first, as 2^255 is 19 mod p.
fe_carry #constant_time :: fn(f: Fe) -> Fe {
    h := f
    for i in 0..<4 {
        h[i + 1] += h[i] >> 51
        h[i] = h[i] & FE_MASK
    }
    carry := h[4] >> 51
    h[4] = h[4] & FE_MASK
    h[0] += carry * 19
    return h
}

fe_add #constant_time :: fn(f: Fe, g: Fe) -> Fe {
    h : Fe
    for i in 0..<5 {
        h[i] = f[i] + g[i]
    }
    return fe_carry(h)
}

fe_subtract #constant_time :: fn(f: Fe, g: Fe) -> Fe {
    h : Fe
    for i in 0..<5 {
        h[i] = f[i] + FE_FOUR_P[i] - g[i]
    }
    return fe_carry(h)
}

fe_negate #constant_time :: fn(f: Fe) -> Fe {
    return fe_subtract(fe_of(u64.[0, 0, 0, 0, 0]), f)
}

// Wide limbs carried down to 51 bits each, the top one's carry times 19 into the first.
fe_carry_wide #constant_time :: fn(r: FeWide) -> Fe {
    c := r
    h : Fe
    for i in 0..<4 {
        c[i + 1] += c[i] >> 51
        h[i] = cast[u64](c[i]) & FE_MASK
    }
    h[4] = cast[u64](c[4]) & FE_MASK
    low := cast[u128](h[0]) + (c[4] >> 51) * 19
    h[0] = cast[u64](low) & FE_MASK
    h[1] += cast[u64](low >> 51)
    return h
}

fe_multiply #constant_time :: fn(f: Fe, g: Fe) -> Fe {
    f0 := cast[u128](f[0])
    f1 := cast[u128](f[1])
    f2 := cast[u128](f[2])
    f3 := cast[u128](f[3])
    f4 := cast[u128](f[4])
    g0 := cast[u128](g[0])
    g1 := cast[u128](g[1])
    g2 := cast[u128](g[2])
    g3 := cast[u128](g[3])
    g4 := cast[u128](g[4])
    g1_19 := g1 * 19
    g2_19 := g2 * 19
    g3_19 := g3 * 19
    g4_19 := g4 * 19
    r : FeWide
    r[0] = f0 * g0 + f1 * g4_19 + f2 * g3_19 + f3 * g2_19 + f4 * g1_19
    r[1] = f0 * g1 + f1 * g0 + f2 * g4_19 + f3 * g3_19 + f4 * g2_19
    r[2] = f0 * g2 + f1 * g1 + f2 * g0 + f3 * g4_19 + f4 * g3_19
    r[3] = f0 * g3 + f1 * g2 + f2 * g1 + f3 * g0 + f4 * g4_19
    r[4] = f0 * g4 + f1 * g3 + f2 * g2 + f3 * g1 + f4 * g0
    return fe_carry_wide(r)
}

fe_square #constant_time :: fn(f: Fe) -> Fe {
    return fe_multiply(f, f)
}

// f squared count times.
fe_square_times #constant_time :: fn(f: Fe, count: int) -> Fe {
    h := f
    for i in 0..<count {
        h = fe_multiply(h, h)
    }
    return h
}

fe_multiply_small #constant_time :: fn(f: Fe, n: u64) -> Fe {
    r : FeWide
    for i in 0..<5 {
        r[i] = cast[u128](f[i]) * cast[u128](n)
    }
    return fe_carry_wide(r)
}

// f^(2^250 - 1), and f^11 into eleven, which inverting and square roots both start from.
fe_power_250 #constant_time :: fn(f: Fe, eleven: ptr[mut Fe]) -> Fe {
    f2 := fe_square(f)
    f9 := fe_multiply(fe_square_times(f2, 2), f)
    f11 := fe_multiply(f9, f2)
    eleven^ = f11
    f_5 := fe_multiply(fe_square(f11), f9)
    f_10 := fe_multiply(fe_square_times(f_5, 5), f_5)
    f_20 := fe_multiply(fe_square_times(f_10, 10), f_10)
    f_40 := fe_multiply(fe_square_times(f_20, 20), f_20)
    f_50 := fe_multiply(fe_square_times(f_40, 10), f_10)
    f_100 := fe_multiply(fe_square_times(f_50, 50), f_50)
    f_200 := fe_multiply(fe_square_times(f_100, 100), f_100)
    return fe_multiply(fe_square_times(f_200, 50), f_50)
}

// 1 / f, as f^(p - 2); 0 for 0.
fe_invert #constant_time :: fn(f: Fe) -> Fe {
    f11 : Fe
    f_250 := fe_power_250(f, &f11)
    return fe_multiply(fe_square_times(f_250, 5), f11)
}

// f^((p - 5) / 8), for square roots.
fe_power_p58 #constant_time :: fn(f: Fe) -> Fe {
    f11 : Fe
    f_250 := fe_power_250(f, &f11)
    return fe_multiply(fe_square_times(f_250, 2), f)
}

// chosen if condition, otherwise otherwise, without a branch.
fe_select #constant_time :: fn(condition: SecretBool, chosen: Fe, otherwise: Fe) -> Fe {
    h : Fe
    for i in 0..<5 {
        h[i] = intrinsics.select(cast[bool](condition), chosen[i], otherwise[i])
    }
    return h
}

// 32 little-endian bytes, the top bit dropped.
fe_from_bytes #constant_time :: fn(bytes: SecretByte[32]) -> Fe {
    words := compiler.secret(u64.[0, 0, 0, 0])
    for i in 0..<4 {
        for j in 0..<8 {
            words[i] = words[i] | (cast[u64](bytes[8 * i + j]) << (8 * cast[u64](j)))
        }
    }
    f : Fe
    f[0] = words[0] & FE_MASK
    f[1] = ((words[0] >> 51) | (words[1] << 13)) & FE_MASK
    f[2] = ((words[1] >> 38) | (words[2] << 26)) & FE_MASK
    f[3] = ((words[2] >> 25) | (words[3] << 39)) & FE_MASK
    f[4] = (words[3] >> 12) & FE_MASK
    return f
}

// The 32 little-endian bytes of f, reduced below p, so each number has one encoding.
fe_to_bytes #constant_time :: fn(f: Fe) -> SecretByte[32] {
    h := fe_carry(fe_carry(f))
    // Under 2p now: whether it's p or more is whether adding 19 carries out of 2^255
    q := (h[0] + 19) >> 51
    for i in 1..<5 {
        q = (h[i] + q) >> 51
    }
    h[0] += 19 * q
    for i in 0..<4 {
        h[i + 1] += h[i] >> 51
        h[i] = h[i] & FE_MASK
    }
    h[4] = h[4] & FE_MASK
    words := compiler.secret(u64.[0, 0, 0, 0])
    words[0] = h[0] | (h[1] << 51)
    words[1] = (h[1] >> 13) | (h[2] << 38)
    words[2] = (h[2] >> 26) | (h[3] << 25)
    words[3] = (h[3] >> 39) | (h[4] << 12)
    bytes : SecretByte[32]
    for i in 0..<4 {
        for j in 0..<8 {
            bytes[8 * i + j] = cast[SecretByte](words[i] >> (8 * cast[u64](j)))
        }
    }
    return bytes
}

// Whether f is 0 mod p.
fe_is_zero #constant_time :: fn(f: Fe) -> SecretBool {
    bytes := fe_to_bytes(f)
    bits := compiler.secret(cast[u8](0))
    for byte in bytes {
        bits = bits | cast[u8](byte)
    }
    return cast[SecretBool](bits == 0)
}

// Whether f, reduced, is odd, which Ed25519 calls negative.
fe_is_negative #constant_time :: fn(f: Fe) -> SecretBool {
    bytes := fe_to_bytes(f)
    return cast[SecretBool]((cast[u8](bytes[0]) & 1) == 1)
}

// (A - 2) / 4 for Curve25519's A, 486662.
X25519_A24 :: 121665

/*
 * The u coordinate of scalar times the point with u coordinate u (RFC 7748, 5): the Montgomery
 * ladder, one step a bit, swapping without branching.
 */
x25519_ladder #constant_time :: fn(scalar: SecretByte[32], u: Fe) -> SecretByte[32] {
    x1 := u
    x2 := fe_of(u64.[1, 0, 0, 0, 0])
    z2 := fe_of(u64.[0, 0, 0, 0, 0])
    x3 := u
    z3 := fe_of(u64.[1, 0, 0, 0, 0])
    swap := cast[SecretBool](false)
    for t in 0..<255 #reverse {
        bit := cast[SecretBool](((cast[u8](scalar[t / 8]) >> cast[u8](t % 8)) & 1) == 1)
        swap = cast[SecretBool](swap != bit)
        next_x2 := fe_select(swap, x3, x2)
        x3 = fe_select(swap, x2, x3)
        x2 = next_x2
        next_z2 := fe_select(swap, z3, z2)
        z3 = fe_select(swap, z2, z3)
        z2 = next_z2
        swap = bit

        a := fe_add(x2, z2)
        aa := fe_square(a)
        b := fe_subtract(x2, z2)
        bb := fe_square(b)
        e := fe_subtract(aa, bb)
        c := fe_add(x3, z3)
        d := fe_subtract(x3, z3)
        da := fe_multiply(d, a)
        cb := fe_multiply(c, b)
        x3 = fe_square(fe_add(da, cb))
        z3 = fe_multiply(x1, fe_square(fe_subtract(da, cb)))
        x2 = fe_multiply(aa, bb)
        z2 = fe_multiply(e, fe_add(aa, fe_multiply_small(e, X25519_A24)))
    }
    x2 = fe_select(swap, x3, x2)
    z2 = fe_select(swap, z3, z2)
    return fe_to_bytes(fe_multiply(x2, fe_invert(z2)))
}

// A secret key's bytes as its scalar: a multiple of 8, with bit 254 set and 255 clear (RFC 7748, 5).
x25519_clamped #constant_time :: fn(secret_key: ptr[X25519SecretKey]) -> SecretByte[32] {
    scalar : SecretByte[32]
    for i in 0..<32 {
        scalar[i] = cast[SecretByte](secret_key[i])
    }
    scalar[0] = cast[SecretByte](cast[u8](scalar[0]) & 248)
    scalar[31] = cast[SecretByte]((cast[u8](scalar[31]) & 127) | 64)
    return scalar
}

// The public key going with a secret one, to send to the other side.
x25519_public_key #constant_time :: fn(secret_key: ptr[X25519SecretKey]) -> X25519PublicKey {
    base : SecretByte[32]
    base[0] = 9
    point := x25519_ladder(x25519_clamped(secret_key), fe_from_bytes(base))
    public_key : X25519PublicKey
    for i in 0..<32 {
        public_key[i] = compiler.declassify(cast[u8](point[i]))
    }
    return public_key
}

/*
 * The secret shared with whoever has public_key's secret key, into shared. False, with shared all
 * zeros, when public_key is a low-order point, which gives the same answer whatever the secret key.
 */
x25519 #constant_time :: fn(secret_key: ptr[X25519SecretKey], public_key: ptr[X25519PublicKey],
    shared: ptr[mut SecretByte[32]]) -> bool {

    u : SecretByte[32]
    for i in 0..<32 {
        u[i] = cast[SecretByte](public_key[i])
    }
    shared^ = x25519_ladder(x25519_clamped(secret_key), fe_from_bytes(u))
    bits := compiler.secret(cast[u8](0))
    for byte in shared^ {
        bits = bits | cast[u8](byte)
    }
    return compiler.declassify(bits != 0)
}
