package crypto

import compiler from "base"
import intrinsics from "base"

/*
 * Ed25519 (RFC 8032): signatures. A secret key signs a message, and anyone with its public key can check
 * the signature was made with it, for that message.
 *
 *     public_key := crypto.ed25519_public_key(&secret_key)
 *     signature := crypto.ed25519_sign(&secret_key, message)
 *     if !crypto.ed25519_verify(&public_key, message, &signature) {
 *         // not signed with that key, or not this message
 *     }
 *
 * Signing works in constant time. Verifying only uses what's public, so it needn't, but it uses the same
 * arithmetic, and refuses a public key or signature that isn't written the one way it should be.
 *
 * Multiples of the base point come from a table of them, worked out while compiling (ED_BASE_TABLE), each
 * read by looking at every entry it could be.
 */

// An Ed25519 secret key, 32 random bytes, which RFC 8032 calls the seed.
Ed25519SecretKey :: distinct alias u8[32] #secret
// An Ed25519 public key, an encoded point.
Ed25519PublicKey :: distinct alias u8[32]
// An Ed25519 signature: a point, R, then a number, S.
Ed25519Signature :: distinct alias u8[64]

// A point on the curve, in extended coordinates: x = X / Z, y = Y / Z, and x * y = T / Z.
EdPoint :: struct {
    x: Fe,
    y: Fe,
    z: Fe,
    t: Fe,
}

ED_D :: u64.[0x3_4dca_1359_78a3, 0x1_a828_3b15_6ebd, 0x5_e7a2_6001_c029, 0x7_39c6_63a0_3cbb, 0x5_2036_cee2_b6ff]
ED_D2 :: u64.[0x6_9b94_26b2_f159, 0x3_5050_762a_dd7a, 0x3_cf44_c003_8052, 0x6_738c_c740_7977, 0x2_406d_9dc5_6dff]
ED_SQRT_M1 :: u64.[0x6_1b27_4a0e_a0b0, 0x0_d5a5_fc8f_189d, 0x7_ef5e_9cbd_0c60, 0x7_8595_a680_4c9e, 0x2_b832_4804_fc1d]
ED_BASE_X :: u64.[0x6_2d60_8f25_d51a, 0x4_12a4_b4f6_592a, 0x7_5b71_71a4_b31d, 0x1_ff60_5271_18fe, 0x2_1693_6d3c_d6e5]
ED_BASE_Y :: u64.[0x6_6666_6666_6658, 0x4_cccc_cccc_cccc, 0x1_9999_9999_9999, 0x3_3333_3333_3333, 0x6_6666_6666_6666]
ED_BASE_T :: u64.[0x6_8ab3_a5b7_dda3, 0x0_0eea_2a5e_adbb, 0x2_af8d_f483_c27e, 0x3_32b3_7527_4732, 0x6_7875_f0fd_78b7]

ed_identity #constant_time :: fn() -> EdPoint {
    return EdPoint.{x = fe_of(u64.[0, 0, 0, 0, 0]), y = fe_of(u64.[1, 0, 0, 0, 0]), z = fe_of(u64.[1, 0, 0, 0, 0]),
        t = fe_of(u64.[0, 0, 0, 0, 0])}
}

ed_base #constant_time :: fn() -> EdPoint {
    return EdPoint.{x = fe_of(ED_BASE_X), y = fe_of(ED_BASE_Y), z = fe_of(u64.[1, 0, 0, 0, 0]), t = fe_of(ED_BASE_T)}
}

// p + q (RFC 8032, 5.1.4), which works for any two points, the same or not, so doubling uses it too.
ed_add #constant_time :: fn(p: EdPoint, q: EdPoint) -> EdPoint {
    a := fe_multiply(fe_subtract(p.y, p.x), fe_subtract(q.y, q.x))
    b := fe_multiply(fe_add(p.y, p.x), fe_add(q.y, q.x))
    c := fe_multiply(fe_multiply(p.t, fe_of(ED_D2)), q.t)
    d := fe_multiply(fe_add(p.z, p.z), q.z)
    e := fe_subtract(b, a)
    f := fe_subtract(d, c)
    g := fe_add(d, c)
    h := fe_add(b, a)
    return EdPoint.{x = fe_multiply(e, f), y = fe_multiply(g, h), z = fe_multiply(f, g), t = fe_multiply(e, h)}
}

// 2p (RFC 8032, 5.1.4's doubling): four multiplications and four squarings, rather than an addition's nine.
ed_double #constant_time :: fn(p: EdPoint) -> EdPoint {
    a := fe_square(p.x)
    b := fe_square(p.y)
    c := fe_add(fe_square(p.z), fe_square(p.z))
    h := fe_add(a, b)
    e := fe_subtract(h, fe_square(fe_add(p.x, p.y)))
    g := fe_subtract(a, b)
    f := fe_add(c, g)
    return EdPoint.{x = fe_multiply(e, f), y = fe_multiply(g, h), z = fe_multiply(f, g), t = fe_multiply(e, h)}
}

ed_negate #constant_time :: fn(p: EdPoint) -> EdPoint {
    return EdPoint.{x = fe_negate(p.x), y = p.y, z = p.z, t = fe_negate(p.t)}
}

ed_select #constant_time :: fn(condition: SecretBool, chosen: EdPoint, otherwise: EdPoint) -> EdPoint {
    return EdPoint.{x = fe_select(condition, chosen.x, otherwise.x), y = fe_select(condition, chosen.y, otherwise.y),
        z = fe_select(condition, chosen.z, otherwise.z), t = fe_select(condition, chosen.t, otherwise.t)}
}

// scalar, 32 little-endian bytes, times point: doubling and adding for every bit, keeping the sum or not.
ed_multiply #constant_time :: fn(scalar: SecretByte[32], point: EdPoint) -> EdPoint {
    q := ed_identity()
    for i in 0..<256 #reverse {
        q = ed_double(q)
        bit := cast[SecretBool](((cast[u8](scalar[i / 8]) >> cast[u8](i % 8)) & 1) == 1)
        q = ed_select(bit, ed_add(q, point), q)
    }
    return q
}

/*
 * A point as y + x, y - x and 2d * x * y, with z = 1: what adding it to another needs, so a table of them
 * costs one multiplication fewer an addition (ref10's "Niels" form).
 */
EdNiels :: struct {
    sum: Fe,
    difference: Fe,
    product: Fe,
}

// p + q, q in Niels form: seven multiplications.
ed_add_niels #constant_time :: fn(p: EdPoint, q: EdNiels) -> EdPoint {
    a := fe_multiply(fe_subtract(p.y, p.x), q.difference)
    b := fe_multiply(fe_add(p.y, p.x), q.sum)
    c := fe_multiply(p.t, q.product)
    d := fe_add(p.z, p.z)
    e := fe_subtract(b, a)
    f := fe_subtract(d, c)
    g := fe_add(d, c)
    h := fe_add(b, a)
    return EdPoint.{x = fe_multiply(e, f), y = fe_multiply(g, h), z = fe_multiply(f, g), t = fe_multiply(e, h)}
}

/*
 * The base point's table (ref10's): for each j from 0 to 31 the multiples 1 to 8 of 256^j * B, in Niels form,
 * as limbs, worked out while compiling. 32 * 8 entries of 3 values of 5 limbs.
 */
ED_TABLE_SIZE :: 3840
ED_BASE_TABLE :: #run ed_base_table()

ed_base_table :: fn() -> u64[3840] {
    table : u64[3840]
    position := ed_base()
    for j in 0..<32 {
        multiple := position
        for k in 0..<8 {
            inverse := fe_invert(multiple.z)
            x := fe_multiply(multiple.x, inverse)
            y := fe_multiply(multiple.y, inverse)
            values := Fe.[fe_add(y, x), fe_subtract(y, x), fe_multiply(fe_multiply(x, y), fe_of(ED_D2))]
            for v in 0..<3 {
                limbs := fe_carry(values[v])
                for l in 0..<5 {
                    table[((j * 8 + k) * 3 + v) * 5 + l] = compiler.declassify(limbs[l])
                }
            }
            multiple = ed_add(multiple, position)
        }
        // 256 times: eight doublings
        for d in 0..<8 {
            position = ed_double(position)
        }
    }
    return table
}

ed_table_value #constant_time :: fn(entry: int, v: int) -> Fe {
    f : Fe
    for l in 0..<5 {
        f[l] = ED_BASE_TABLE[cast[usize]((entry * 3 + v) * 5 + l) % ED_TABLE_SIZE]
    }
    return f
}

/*
 * digit * 256^j * B, for a digit from -8 to 8, read from the table without the digit deciding what's read:
 * every one of position j's entries looked at, the right one kept with a mask, then negated if the digit is.
 */
ed_table_select #constant_time :: fn(j: int, digit: SecretWord) -> EdNiels {
    d := cast[u64](digit)
    negative := d >> 63
    // |digit|, without a branch
    magnitude := (d ~ (cast[u64](0) - negative)) + negative
    one := fe_of(u64.[1, 0, 0, 0, 0])
    zero := fe_of(u64.[0, 0, 0, 0, 0])
    chosen := EdNiels.{sum = one, difference = one, product = zero}
    for k in 0..<8 {
        found := cast[SecretBool](magnitude == cast[u64](k + 1))
        entry := j * 8 + k
        chosen.sum = fe_select(found, ed_table_value(entry, 0), chosen.sum)
        chosen.difference = fe_select(found, ed_table_value(entry, 1), chosen.difference)
        chosen.product = fe_select(found, ed_table_value(entry, 2), chosen.product)
    }
    // -P swaps y + x and y - x and negates x * y
    flip := cast[SecretBool](negative == 1)
    return EdNiels.{sum = fe_select(flip, chosen.difference, chosen.sum), difference = fe_select(flip, chosen.sum, chosen.difference),
        product = fe_select(flip, fe_negate(chosen.product), chosen.product)}
}

/*
 * scalar times the base point with the table (ref10's ge_scalarmult_base): the scalar as 64 signed digits
 * from -8 to 8 in base 16, the odd ones' multiples added, times 16, then the even ones'. scalar's top bit is 0,
 * as a clamped or reduced scalar's is.
 */
ed_multiply_base #constant_time :: fn(scalar: SecretByte[32]) -> EdPoint {
    // Two digits a byte, kept as u64s in two's complement
    e : EdDigits
    for i in 0..<32 {
        byte := cast[u64](scalar[i])
        e[2 * i] = byte & 15
        e[2 * i + 1] = (byte >> 4) & 15
    }
    carry := compiler.secret(cast[u64](0))
    for i in 0..<63 {
        e[i] = e[i] + carry
        carry = (e[i] + 8) >> 4
        e[i] = e[i] - (carry << 4)
    }
    e[63] = e[63] + carry
    q := ed_identity()
    for i in 0..<32 {
        q = ed_add_niels(q, ed_table_select(i, cast[SecretWord](e[2 * i + 1])))
    }
    q = ed_double(ed_double(ed_double(ed_double(q))))
    for i in 0..<32 {
        q = ed_add_niels(q, ed_table_select(i, cast[SecretWord](e[2 * i])))
    }
    return q
}

// y, with x's low bit as the top bit (RFC 8032, 5.1.2).
ed_encode #constant_time :: fn(p: EdPoint) -> SecretByte[32] {
    inverse := fe_invert(p.z)
    x := fe_to_bytes(fe_multiply(p.x, inverse))
    bytes := fe_to_bytes(fe_multiply(p.y, inverse))
    bytes[31] = cast[SecretByte](cast[u8](bytes[31]) | ((cast[u8](x[0]) & 1) << 7))
    return bytes
}

/*
 * The point bytes encode, into point (RFC 8032, 5.1.3), or false if they don't encode one: y isn't
 * below p, or x^2 has no square root, or x is 0 but said to be odd.
 */
ed_decode #constant_time :: fn(bytes: u8[32], point: ptr[mut EdPoint]) -> bool {
    y_bytes : SecretByte[32]
    for i in 0..<32 {
        y_bytes[i] = cast[SecretByte](bytes[i])
    }
    y_bytes[31] = cast[SecretByte](bytes[31] & 127)
    y := fe_from_bytes(y_bytes)
    reduced := fe_to_bytes(y)
    for i in 0..<32 {
        if compiler.declassify(reduced[i] != y_bytes[i]) {
            return false
        }
    }
    // x^2 = u / v; x = u * v^3 * (u * v^7)^((p - 5) / 8), then checked
    one := fe_of(u64.[1, 0, 0, 0, 0])
    y2 := fe_square(y)
    u := fe_subtract(y2, one)
    v := fe_add(fe_multiply(fe_of(ED_D), y2), one)
    v3 := fe_multiply(fe_square(v), v)
    x := fe_multiply(fe_multiply(u, v3), fe_power_p58(fe_multiply(fe_multiply(u, fe_square(v3)), v)))
    vxx := fe_multiply(v, fe_square(x))
    root := compiler.declassify(fe_is_zero(fe_subtract(vxx, u)))
    negated_root := compiler.declassify(fe_is_zero(fe_add(vxx, u)))
    if !root && !negated_root {
        return false
    }
    if negated_root {
        x = fe_multiply(x, fe_of(ED_SQRT_M1))
    }
    odd := (bytes[31] >> 7) == 1
    if compiler.declassify(fe_is_zero(x)) && odd {
        return false
    }
    if compiler.declassify(fe_is_negative(x)) != odd {
        x = fe_negate(x)
    }
    point^ = EdPoint.{x = x, y = y, z = one, t = fe_multiply(x, y)}
    return true
}

// A scalar's 64 signed digits, each a u64 in two's complement
EdDigits :: distinct alias u64[64] #secret

// A number mod the group's order, L = 2^252 + 27742317777372353535851937790883648493, in 64-bit limbs.
Scalar :: distinct alias u64[4] #secret
// A product, or a hash, before it's reduced mod L.
ScalarWide :: distinct alias u64[8] #secret

ED_ORDER :: u64.[0x5812_631a_5cf5_d3ed, 0x14de_f9de_a2f7_9cd6, 0, 0x1000_0000_0000_0000]

// s - L, and whether that went below 0, so s was below L.
scalar_less_order #constant_time :: fn(s: Scalar, below: ptr[mut SecretBool]) -> Scalar {
    difference : Scalar
    borrow := compiler.secret(cast[u64](0))
    for k in 0..<4 {
        wide := cast[u128](s[k]) - cast[u128](ED_ORDER[k]) - cast[u128](borrow)
        difference[k] = cast[u64](wide)
        borrow = cast[u64](wide >> 127)
    }
    below^ = cast[SecretBool](borrow == 1)
    return difference
}

// x mod L, a bit at a time from the top: doubled, the bit added, and L taken away if it's more.
scalar_reduce #constant_time :: fn(x: ScalarWide) -> Scalar {
    r : Scalar
    for i in 0..<512 #reverse {
        r[3] = (r[3] << 1) | (r[2] >> 63)
        r[2] = (r[2] << 1) | (r[1] >> 63)
        r[1] = (r[1] << 1) | (r[0] >> 63)
        r[0] = (r[0] << 1) | ((x[i / 64] >> cast[u64](i % 64)) & 1)
        below : SecretBool
        less := scalar_less_order(r, &below)
        for k in 0..<4 {
            r[k] = intrinsics.select(cast[bool](below), r[k], less[k])
        }
    }
    return r
}

// 64 little-endian bytes, like a hash, as a number to reduce.
scalar_wide_of #constant_time :: fn(bytes: SecretByte[64]) -> ScalarWide {
    wide : ScalarWide
    for i in 0..<8 {
        for j in 0..<8 {
            wide[i] = wide[i] | (cast[u64](bytes[8 * i + j]) << (8 * cast[u64](j)))
        }
    }
    return wide
}

scalar_of #constant_time :: fn(bytes: SecretByte[32]) -> Scalar {
    s : Scalar
    for i in 0..<4 {
        for j in 0..<8 {
            s[i] = s[i] | (cast[u64](bytes[8 * i + j]) << (8 * cast[u64](j)))
        }
    }
    return s
}

scalar_bytes #constant_time :: fn(s: Scalar) -> SecretByte[32] {
    bytes : SecretByte[32]
    for i in 0..<4 {
        for j in 0..<8 {
            bytes[8 * i + j] = cast[SecretByte](s[i] >> (8 * cast[u64](j)))
        }
    }
    return bytes
}

// (k * a + r) mod L, for k and r below L and a below 2^255.
scalar_multiply_add #constant_time :: fn(k: Scalar, a: Scalar, r: Scalar) -> Scalar {
    wide : ScalarWide
    for i in 0..<4 {
        wide[i] = r[i]
    }
    for i in 0..<4 {
        carry := compiler.secret(cast[u128](0))
        for j in 0..<4 {
            sum := cast[u128](k[i]) * cast[u128](a[j]) + cast[u128](wide[(i + j) % 8]) + carry
            wide[(i + j) % 8] = cast[u64](sum)
            carry = sum >> 64
        }
        // Carried on up, as r's limbs make the sum more than a product's
        for j in i + 4..<8 {
            sum := cast[u128](wide[j]) + carry
            wide[j] = cast[u64](sum)
            carry = sum >> 64
        }
    }
    return scalar_reduce(wide)
}

// A secret key's scalar, clamped, and the prefix that makes each message's nonce (RFC 8032, 5.1.5).
ed25519_expand #constant_time :: fn(secret_key: ptr[Ed25519SecretKey], scalar: ptr[mut SecretByte[32]],
    prefix: ptr[mut SecretByte[32]]) {

    seed : SecretByte[32]
    for i in 0..<32 {
        seed[i] = cast[SecretByte](secret_key[i])
    }
    hasher := sha512_start()
    sha512_update_secret(&hasher, seed)
    digest := sha512_finish_secret(&hasher)
    for i in 0..<32 {
        scalar[i] = digest[i]
        prefix[i] = digest[32 + i]
    }
    scalar[0] = cast[SecretByte](cast[u8](scalar[0]) & 248)
    scalar[31] = cast[SecretByte]((cast[u8](scalar[31]) & 127) | 64)
    intrinsics.secure_zero(&seed, size_of(SecretByte[32]))
    intrinsics.secure_zero(&digest, size_of(SecretByte[64]))
}

// The public key going with a secret one.
ed25519_public_key #constant_time :: fn(secret_key: ptr[Ed25519SecretKey]) -> Ed25519PublicKey {
    scalar : SecretByte[32]
    prefix : SecretByte[32]
    ed25519_expand(secret_key, &scalar, &prefix)
    encoded := ed_encode(ed_multiply_base(scalar))
    public_key : Ed25519PublicKey
    for i in 0..<32 {
        public_key[i] = compiler.declassify(cast[u8](encoded[i]))
    }
    intrinsics.secure_zero(&scalar, size_of(SecretByte[32]))
    intrinsics.secure_zero(&prefix, size_of(SecretByte[32]))
    return public_key
}

// The hash of R, the public key and the message, reduced: what the signature's S answers for.
ed25519_challenge #constant_time :: fn(r: ptr[Ed25519Signature], public_key: ptr[Ed25519PublicKey], message: u8[]) -> Scalar {
    r_bytes : u8[32]
    for i in 0..<32 {
        r_bytes[i] = r[i]
    }
    hasher := sha512_start()
    sha512_update(&hasher, r_bytes)
    sha512_update(&hasher, cast[u8[32]](public_key^))
    sha512_update(&hasher, message)
    digest := sha512_finish(&hasher)
    secret_digest : SecretByte[64]
    for i in 0..<64 {
        secret_digest[i] = cast[SecretByte](digest[i])
    }
    return scalar_reduce(scalar_wide_of(secret_digest))
}

// message signed with secret_key (RFC 8032, 5.1.6).
ed25519_sign #constant_time :: fn(secret_key: ptr[Ed25519SecretKey], message: u8[]) -> Ed25519Signature {
    scalar : SecretByte[32]
    prefix : SecretByte[32]
    ed25519_expand(secret_key, &scalar, &prefix)
    public_encoded := ed_encode(ed_multiply_base(scalar))
    public_key : Ed25519PublicKey
    for i in 0..<32 {
        public_key[i] = compiler.declassify(cast[u8](public_encoded[i]))
    }

    // r, the nonce, from the prefix and the message, so the same message always gets the same one
    hasher := sha512_start()
    sha512_update_secret(&hasher, prefix)
    sha512_update(&hasher, message)
    r := scalar_reduce(scalar_wide_of(sha512_finish_secret(&hasher)))
    r_encoded := ed_encode(ed_multiply_base(scalar_bytes(r)))
    signature : Ed25519Signature
    for i in 0..<32 {
        signature[i] = compiler.declassify(cast[u8](r_encoded[i]))
    }

    k := ed25519_challenge(&signature, &public_key, message)
    s := scalar_bytes(scalar_multiply_add(k, scalar_of(scalar), r))
    for i in 0..<32 {
        signature[32 + i] = compiler.declassify(cast[u8](s[i]))
    }
    intrinsics.secure_zero(&scalar, size_of(SecretByte[32]))
    intrinsics.secure_zero(&prefix, size_of(SecretByte[32]))
    return signature
}

/*
 * Whether signature is public_key's for message (RFC 8032, 5.1.7): S below L, and [S]B = R + [k]A, as
 * the encoding of [S]B - [k]A matching R's bytes.
 */
ed25519_verify :: fn(public_key: ptr[Ed25519PublicKey], message: u8[], signature: ptr[Ed25519Signature]) -> bool {
    a : EdPoint
    if !ed_decode(cast[u8[32]](public_key^), &a) {
        return false
    }
    s_bytes : SecretByte[32]
    for i in 0..<32 {
        s_bytes[i] = cast[SecretByte](signature[32 + i])
    }
    below : SecretBool
    _ = scalar_less_order(scalar_of(s_bytes), &below)
    if !compiler.declassify(below) {
        return false
    }
    k := ed25519_challenge(signature, public_key, message)
    check := ed_add(ed_multiply_base(s_bytes), ed_multiply(scalar_bytes(k), ed_negate(a)))
    encoded := ed_encode(check)
    for i in 0..<32 {
        if compiler.declassify(cast[u8](encoded[i])) != signature[i] {
            return false
        }
    }
    return true
}
