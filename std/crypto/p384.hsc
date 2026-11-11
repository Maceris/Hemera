package crypto

/*
 * P-384 (secp384r1) ECDSA verification (FIPS 186-5, section 6.4.2), for certificates: many CAs' keys are
 * P-384's, like Let's Encrypt's ECDSA intermediates and ISRG Root X2, which sign with ecdsa-with-SHA384.
 *
 * Only verifying is here, which works with public values alone, so it's built on BigNumber and isn't
 * constant time; there's no P-384 signing or key agreement. Points are added with Renes, Costello and
 * Batina's complete formulas, as P-256's are.
 */

/** The field's prime, p = 2^384 - 2^128 - 2^96 + 2^32 - 1, big-endian. */
P384_P :: u8.[0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe,
    0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff]
/** The group's order, n, big-endian. */
P384_N :: u8.[0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xc7, 0x63, 0x4d, 0x81, 0xf4, 0x37, 0x2d, 0xdf,
    0x58, 0x1a, 0x0d, 0xb2, 0x48, 0xb0, 0xa7, 0x7a, 0xec, 0xec, 0x19, 0x6a, 0xcc, 0xc5, 0x29, 0x73]
/** The curve's b, big-endian; its a is -3. */
P384_B :: u8.[0xb3, 0x31, 0x2f, 0xa7, 0xe2, 0x3e, 0xe7, 0xe4, 0x98, 0x8e, 0x05, 0x6b, 0xe3, 0xf8, 0x2d, 0x19,
    0x18, 0x1d, 0x9c, 0x6e, 0xfe, 0x81, 0x41, 0x12, 0x03, 0x14, 0x08, 0x8f, 0x50, 0x13, 0x87, 0x5a,
    0xc6, 0x56, 0x39, 0x8d, 0x8a, 0x2e, 0xd1, 0x9d, 0x2a, 0x85, 0xc8, 0xed, 0xd3, 0xec, 0x2a, 0xef]
/** The base point's x, big-endian. */
P384_GX :: u8.[0xaa, 0x87, 0xca, 0x22, 0xbe, 0x8b, 0x05, 0x37, 0x8e, 0xb1, 0xc7, 0x1e, 0xf3, 0x20, 0xad, 0x74,
    0x6e, 0x1d, 0x3b, 0x62, 0x8b, 0xa7, 0x9b, 0x98, 0x59, 0xf7, 0x41, 0xe0, 0x82, 0x54, 0x2a, 0x38,
    0x55, 0x02, 0xf2, 0x5d, 0xbf, 0x55, 0x29, 0x6c, 0x3a, 0x54, 0x5e, 0x38, 0x72, 0x76, 0x0a, 0xb7]
/** The base point's y, big-endian. */
P384_GY :: u8.[0x36, 0x17, 0xde, 0x4a, 0x96, 0x26, 0x2c, 0x6f, 0x5d, 0x9e, 0x98, 0xbf, 0x92, 0x92, 0xdc, 0x29,
    0xf8, 0xf4, 0x1d, 0xbd, 0x28, 0x9a, 0x14, 0x7c, 0xe9, 0xda, 0x31, 0x13, 0xb5, 0xf0, 0xb8, 0xc0,
    0x0a, 0x60, 0xb1, 0xce, 0x1d, 0x7e, 0x81, 0x9d, 0x7a, 0x43, 0x1d, 0x7c, 0x90, 0xea, 0x0e, 0x5f]

/** A P-384 ECDSA signature as r then s, 48 big-endian bytes each: IEEE P1363's form. */
P384Signature :: distinct alias u8[96]

/** A point in projective coordinates, each in Montgomery form modulo p; the identity is (0 : 1 : 0). */
P384Point :: struct {
    /** X. */
    x: BigNumber,
    /** Y. */
    y: BigNumber,
    /** Z, 0 only for the identity. */
    z: BigNumber,
}

/** The field's modulus, and b in Montgomery form, for working out points. */
P384Curve :: struct {
    /** p, ready for Montgomery arithmetic. */
    p: BigModulus,
    /** b, in Montgomery form. */
    b: BigNumber,
    /** 1, in Montgomery form. */
    one: BigNumber,
}

/**
 * Make the curve's constants ready to work with.
 *
 * @return p as a modulus, and b and 1 in Montgomery form.
 */
p384_curve :: fn() -> P384Curve {
    p := big_from_bytes(P384_P) or_else BigNumber.{}
    modulus := big_modulus(&p) or_else BigModulus.{}
    b := big_from_bytes(P384_B) or_else BigNumber.{}
    one := BigNumber.{count = 1}
    one.limbs[0] = 1
    return P384Curve.{p = modulus, b = big_multiply(&b, &modulus.r2, &modulus), one = big_multiply(&one, &modulus.r2, &modulus)}
}

/**
 * Add two points: Renes, Costello and Batina's complete formula for a = -3 (2016, algorithm 4).
 *
 * @param c The curve.
 * @param p One point.
 * @param q The other.
 * @return p + q.
 */
p384_add :: fn(c: ptr[P384Curve], p: ptr[P384Point], q: ptr[P384Point]) -> P384Point {
    m := &c.p
    t0 := big_multiply(&p.x, &q.x, m)
    t1 := big_multiply(&p.y, &q.y, m)
    t2 := big_multiply(&p.z, &q.z, m)
    t3 := big_add(&p.x, &p.y, m)
    t4 := big_add(&q.x, &q.y, m)
    t3 = big_multiply(&t3, &t4, m)
    t4 = big_add(&t0, &t1, m)
    t3 = big_subtract(&t3, &t4, m)
    t4 = big_add(&p.y, &p.z, m)
    x3 := big_add(&q.y, &q.z, m)
    t4 = big_multiply(&t4, &x3, m)
    x3 = big_add(&t1, &t2, m)
    t4 = big_subtract(&t4, &x3, m)
    x3 = big_add(&p.x, &p.z, m)
    y3 := big_add(&q.x, &q.z, m)
    x3 = big_multiply(&x3, &y3, m)
    y3 = big_add(&t0, &t2, m)
    y3 = big_subtract(&x3, &y3, m)
    z3 := big_multiply(&c.b, &t2, m)
    x3 = big_subtract(&y3, &z3, m)
    z3 = big_add(&x3, &x3, m)
    x3 = big_add(&x3, &z3, m)
    z3 = big_subtract(&t1, &x3, m)
    x3 = big_add(&t1, &x3, m)
    y3 = big_multiply(&c.b, &y3, m)
    t1 = big_add(&t2, &t2, m)
    t2 = big_add(&t1, &t2, m)
    y3 = big_subtract(&y3, &t2, m)
    y3 = big_subtract(&y3, &t0, m)
    t1 = big_add(&y3, &y3, m)
    y3 = big_add(&t1, &y3, m)
    t1 = big_add(&t0, &t0, m)
    t0 = big_add(&t1, &t0, m)
    t0 = big_subtract(&t0, &t2, m)
    t1 = big_multiply(&t4, &y3, m)
    t2 = big_multiply(&t0, &y3, m)
    y3 = big_multiply(&x3, &z3, m)
    y3 = big_add(&y3, &t2, m)
    x3 = big_multiply(&x3, &t3, m)
    x3 = big_subtract(&x3, &t1, m)
    z3 = big_multiply(&t4, &z3, m)
    t1 = big_multiply(&t3, &t0, m)
    z3 = big_add(&z3, &t1, m)
    return P384Point.{x = x3, y = y3, z = z3}
}

/**
 * Read a public key: SEC 1's uncompressed point (0x04, x, y), checked to be on the curve.
 *
 * @param c The curve.
 * @param encoded The point's 97 bytes.
 * @param point Where the point goes, in Montgomery form with Z = 1; left alone if it's refused.
 * @return Whether it's a point on the curve: false for another count or first byte (a compressed point included), a
 *     coordinate not below p, or a point off the curve.
 */
p384_decode_point :: fn(c: ptr[P384Curve], encoded: u8[], point: ptr[mut P384Point]) -> bool {
    if encoded.count != 97 || encoded[0] != 0x04 {
        return false
    }
    x := big_from_bytes(encoded[1..<49]) or_return false
    y := big_from_bytes(encoded[49..<97]) or_return false
    if big_compare(&x, &c.p.n) >= 0 || big_compare(&y, &c.p.n) >= 0 {
        return false
    }
    m := &c.p
    xm := big_multiply(&x, &m.r2, m)
    ym := big_multiply(&y, &m.r2, m)
    // y^2 = x^3 - 3x + b
    left := big_multiply(&ym, &ym, m)
    x2 := big_multiply(&xm, &xm, m)
    right := big_multiply(&x2, &xm, m)
    three_x := big_add(&xm, &xm, m)
    three_x = big_add(&three_x, &xm, m)
    right = big_subtract(&right, &three_x, m)
    right = big_add(&right, &c.b, m)
    if big_compare(&left, &right) != 0 {
        return false
    }
    point^ = P384Point.{x = xm, y = ym, z = c.one}
    return true
}

/**
 * Read one of a signature's numbers, checking it's from 1 to n - 1.
 *
 * @param bytes Its 48 big-endian bytes.
 * @param n The group's order.
 * @return The number; or null when it's 0 or not below n.
 */
p384_signature_scalar :: fn(bytes: u8[], n: ptr[BigNumber]) -> BigNumber? {
    value := big_from_bytes(bytes) or_return null
    if value.count == 0 || big_compare(&value, n) >= 0 {
        return null
    }
    return value
}

/**
 * Verify a P-384 ECDSA signature on a message's digest (FIPS 186-5, section 6.4.2).
 *
 * Not constant time, as everything it works with is public: u1 * G + u2 * Q in one chain of doublings, a bit of each
 * at a time.
 *
 * @param public_key The signer's public key: SEC 1's uncompressed point, 97 bytes.
 * @param digest The message's digest from the hash the signature is for, of any length: its leftmost 48 bytes are
 *     taken, as SHA-384's whole digest is, and a shorter one is a smaller number.
 * @param signature The signature, r then s.
 * @return Whether it's a signature by that key on that digest: false too for a public key that isn't a point on the
 *     curve, or an r or s that isn't from 1 to n - 1.
 */
p384_ecdsa_verify :: fn(public_key: u8[], digest: u8[], signature: ptr[P384Signature]) -> bool {
    c := p384_curve()
    q : P384Point
    if !p384_decode_point(&c, public_key, &q) {
        return false
    }
    n := big_from_bytes(P384_N) or_return false
    order := big_modulus(&n) or_return false
    r := p384_signature_scalar(signature[0..<48], &n) or_return false
    s := p384_signature_scalar(signature[48..<96], &n) or_return false
    taken := digest
    if taken.count > 48 {
        taken = digest[0..<48]
    }
    z := big_from_bytes(taken) or_return false
    z.count = order.n.count
    big_reduce_once(&z, 0, &order)
    // w = 1 / s, u1 = z * w, u2 = r * w, modulo n
    exponent := n
    exponent.limbs[0] -= 2
    w := big_power(&s, &exponent, &order)
    u1 := big_multiply_plain(&z, &w, &order)
    u2 := big_multiply_plain(&r, &w, &order)
    gx := big_from_bytes(P384_GX) or_return false
    gy := big_from_bytes(P384_GY) or_return false
    g := P384Point.{x = big_multiply(&gx, &c.p.r2, &c.p), y = big_multiply(&gy, &c.p.r2, &c.p), z = c.one}
    both := p384_add(&c, &g, &q)
    zero := BigNumber.{count = c.p.n.count}
    sum := P384Point.{x = zero, y = c.one, z = zero}
    for bit in 0..<384 #reverse {
        sum = p384_add(&c, &sum, &sum)
        first := big_bit(&u1, cast[usize](bit))
        second := big_bit(&u2, cast[usize](bit))
        if first && second {
            sum = p384_add(&c, &sum, &both)
        }
        else if first {
            sum = p384_add(&c, &sum, &g)
        }
        else if second {
            sum = p384_add(&c, &sum, &q)
        }
    }
    // x = X / Z, out of Montgomery form, then compared with r modulo n
    one := BigNumber.{count = c.p.n.count}
    one.limbs[0] = 1
    z_plain := big_multiply(&sum.z, &one, &c.p)
    if big_bits(&z_plain) == 0 {
        return false
    }
    p_minus_2 := c.p.n
    p_minus_2.limbs[0] -= 2
    z_inverse := big_power(&z_plain, &p_minus_2, &c.p)
    x_plain := big_multiply(&sum.x, &one, &c.p)
    x := big_multiply_plain(&x_plain, &z_inverse, &c.p)
    x.count = order.n.count
    big_reduce_once(&x, 0, &order)
    return big_compare(&x, &r) == 0
}
