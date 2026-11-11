package crypto

import compiler from "base"
import intrinsics from "base"

/*
 * P-256 (NIST's secp256r1, FIPS 186-5 and SEC 2): ECDH key agreement (SEC 1, section 3.3.1) and ECDSA
 * signatures (FIPS 186-5, section 6), as TLS uses them.
 *
 *     public : crypto.P256PublicKey
 *     if !crypto.p256_public_key(&secret, &public) {
 *         // the 32 random bytes were 0 or not below the group's order: draw others
 *     }
 *     shared : crypto.SecretByte[32]
 *     if !crypto.p256_ecdh(&secret, their_public, &shared) {
 *         // their point wasn't on the curve
 *     }
 *
 *     signature := crypto.p256_ecdsa_sign(&secret, crypto.sha256(message), random) or_else ...
 *     if !crypto.p256_ecdsa_verify(public, crypto.sha256(message), &signature) { ... }
 *
 * What's secret, the secret key and a signature's nonce, is worked with in constant time: numbers in
 * Montgomery form on four 64-bit limbs, points in projective coordinates added with Renes, Costello and
 * Batina's complete formulas (2016), which have no special cases to branch on, and multiples of a point
 * looked up by reading every entry of their table. Verifying works only with what's public, and skips the
 * additions of zero digits.
 *
 * Signing takes its nonce from the key and the digest, as RFC 6979 says, so it needs no random number, and
 * mixes in whatever random bytes it's given too.
 */

/** A P-256 secret key: a number from 1 to n - 1, as 32 big-endian bytes, secret. */
P256SecretKey :: distinct alias u8[32] #secret

/** A P-256 public key as SEC 1 writes it uncompressed (section 2.3.3): 0x04, then x and y, 32 big-endian bytes each. */
P256PublicKey :: distinct alias u8[65]

/** A P-256 ECDSA signature as r then s, 32 big-endian bytes each, each from 1 to n - 1: IEEE P1363's form. */
P256Signature :: distinct alias u8[64]

/** A number modulo p or n, four 64-bit limbs, least significant first, in Montgomery form (times 2^256). Secret. */
P256Element :: distinct alias u64[4] #secret

/** A point in projective coordinates, (X : Y : Z), the affine point (X / Z, Y / Z); the identity is (0 : 1 : 0). */
P256Point :: struct {
    /** X, in Montgomery form modulo p. */
    x: P256Element,
    /** Y, in Montgomery form modulo p. */
    y: P256Element,
    /** Z, in Montgomery form modulo p; 0 only for the identity. */
    z: P256Element,
}

/** The field's prime, p = 2^256 - 2^224 + 2^192 + 2^96 - 1, as limbs. */
P256_P :: u64.[0xffffffffffffffff, 0x00000000ffffffff, 0x0000000000000000, 0xffffffff00000001]
/** -1 / p modulo 2^64, which Montgomery reduction modulo p multiplies by. */
P256_P_INVERSE :: 0x1
/** The group's order, n, as limbs. */
P256_N :: u64.[0xf3b9cac2fc632551, 0xbce6faada7179e84, 0xffffffffffffffff, 0xffffffff00000000]
/** -1 / n modulo 2^64, which Montgomery reduction modulo n multiplies by. */
P256_N_INVERSE :: 0xccd1c8aaee00bc4f
/** 1 in Montgomery form modulo p: 2^256 mod p. */
P256_ONE_P :: u64.[0x0000000000000001, 0xffffffff00000000, 0xffffffffffffffff, 0x00000000fffffffe]
/** 2^512 mod p, which a number multiplied by goes into Montgomery form. */
P256_R2_P :: u64.[0x0000000000000003, 0xfffffffbffffffff, 0xfffffffffffffffe, 0x00000004fffffffd]
/** 2^512 mod n, which a number multiplied by goes into Montgomery form modulo n. */
P256_R2_N :: u64.[0x83244c95be79eea2, 0x4699799c49bd6fa6, 0x2845b2392b6bec59, 0x66e12d94f3d95620]
/** The curve's b, in Montgomery form; its a is -3. */
P256_B :: u64.[0xd89cdf6229c4bddf, 0xacf005cd78843090, 0xe5a220abf7212ed6, 0xdc30061d04874834]
/** The base point's x, in Montgomery form. */
P256_GX :: u64.[0x79e730d418a9143c, 0x75ba95fc5fedb601, 0x79fb732b77622510, 0x18905f76a53755c6]
/** The base point's y, in Montgomery form. */
P256_GY :: u64.[0xddf25357ce95560a, 0x8b4ab8e4ba19e45c, 0xd2e88688dd21f325, 0x8571ff1825885d85]
/** p - 2, big-endian: a number raised to it is its inverse modulo p. */
P256_P_MINUS_2 :: u8.[0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfd]
/** (p + 1) / 4, big-endian: a square raised to it is a square root, as p is 3 mod 4. */
P256_P_SQRT :: u8.[0x3f, 0xff, 0xff, 0xff, 0xc0, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
/** n - 2, big-endian: a number raised to it is its inverse modulo n. */
P256_N_MINUS_2 :: u8.[0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xbc, 0xe6, 0xfa, 0xad, 0xa7, 0x17, 0x9e, 0x84, 0xf3, 0xb9, 0xca, 0xc2, 0xfc, 0x63, 0x25, 0x4f]

/**
 * Make an element from public limbs, like a constant.
 *
 * @param limbs The four limbs, least significant first.
 * @return The element, secret.
 */
p256_of #constant_time :: fn(limbs: u64[4]) -> P256Element {
    e : P256Element
    for i in 0..<4 {
        e[i] = limbs[i]
    }
    return e
}

/**
 * Choose between two numbers without a branch, with intrinsics.select, which the optimizer can't turn into one (a
 * mask of ands and ors, it can).
 *
 * @param condition Which to choose, secret.
 * @param chosen The number chosen when condition is true.
 * @param otherwise The number chosen when it's false.
 * @return The number chosen.
 */
p256_select #constant_time :: fn(condition: SecretBool, chosen: P256Element, otherwise: P256Element) -> P256Element {
    e : P256Element
    for i in 0..<4 {
        e[i] = intrinsics.select(cast[bool](condition), chosen[i], otherwise[i])
    }
    return e
}

/**
 * Subtract the modulus from a number when it isn't below it, without a branch: what's left of an addition, a
 * multiplication or a reading, which is below twice the modulus.
 *
 * @param value The number's low 256 bits.
 * @param carry Its 257th bit, 0 or 1.
 * @param modulus p or n.
 * @return The number reduced, below the modulus.
 */
p256_reduce_once #constant_time :: fn(value: P256Element, carry: SecretWord, modulus: u64[4]) -> P256Element {
    difference : P256Element
    borrow := compiler.secret(cast[u64](0))
    for i in 0..<4 {
        wide := cast[u128](value[i]) - cast[u128](modulus[i]) - cast[u128](borrow)
        difference[i] = cast[u64](wide)
        borrow = cast[u64](wide >> 64) & 1
    }
    // Keep value only when the subtraction borrowed and there's no carry to pay for it
    keep := (borrow & ~cast[u64](carry) & 1) == 1
    return p256_select(cast[SecretBool](keep), value, difference)
}

/**
 * Add two numbers modulo p or n.
 *
 * @param a One addend, below the modulus.
 * @param b The other, below the modulus.
 * @param modulus p or n.
 * @return a + b, below the modulus.
 */
p256_add #constant_time :: fn(a: P256Element, b: P256Element, modulus: u64[4]) -> P256Element {
    sum : P256Element
    carry := compiler.secret(cast[u64](0))
    for i in 0..<4 {
        wide := cast[u128](a[i]) + cast[u128](b[i]) + cast[u128](carry)
        sum[i] = cast[u64](wide)
        carry = cast[u64](wide >> 64)
    }
    return p256_reduce_once(sum, cast[SecretWord](carry), modulus)
}

/**
 * Subtract one number from another modulo p or n.
 *
 * @param a The number subtracted from, below the modulus.
 * @param b The number subtracted, below the modulus.
 * @param modulus p or n.
 * @return a - b, below the modulus: the modulus is added back when the subtraction borrows.
 */
p256_subtract #constant_time :: fn(a: P256Element, b: P256Element, modulus: u64[4]) -> P256Element {
    difference : P256Element
    borrow := compiler.secret(cast[u64](0))
    for i in 0..<4 {
        wide := cast[u128](a[i]) - cast[u128](b[i]) - cast[u128](borrow)
        difference[i] = cast[u64](wide)
        borrow = cast[u64](wide >> 64) & 1
    }
    borrowed := borrow == 1
    carry := compiler.secret(cast[u64](0))
    for i in 0..<4 {
        addend := intrinsics.select(borrowed, modulus[i], cast[u64](0))
        wide := cast[u128](difference[i]) + cast[u128](addend) + cast[u128](carry)
        difference[i] = cast[u64](wide)
        carry = cast[u64](wide >> 64)
    }
    return difference
}

/**
 * Multiply two numbers in Montgomery form modulo p or n: their product divided by 2^256, word by word (CIOS).
 *
 * @param a One factor, below the modulus.
 * @param b The other, below the modulus.
 * @param modulus p or n, which is odd and above 2^255.
 * @param inverse -1 / modulus modulo 2^64: P256_P_INVERSE or P256_N_INVERSE.
 * @return a * b / 2^256 modulo the modulus, below it: the product of the two numbers a and b stand for, in
 *     Montgomery form.
 */
p256_multiply #constant_time :: fn(a: P256Element, b: P256Element, modulus: u64[4], inverse: u64) -> P256Element {
    t := compiler.secret(u64.[0, 0, 0, 0, 0, 0])
    for i in 0..<4 {
        carry := compiler.secret(cast[u64](0))
        for j in 0..<4 {
            wide := cast[u128](t[j]) + cast[u128](a[j]) * cast[u128](b[i]) + cast[u128](carry)
            t[j] = cast[u64](wide)
            carry = cast[u64](wide >> 64)
        }
        wide := cast[u128](t[4]) + cast[u128](carry)
        t[4] = cast[u64](wide)
        t[5] = cast[u64](wide >> 64)
        // A multiple of the modulus that makes the lowest word 0, which is then shifted out
        m := t[0] * inverse
        wide = cast[u128](t[0]) + cast[u128](m) * cast[u128](modulus[0])
        carry = cast[u64](wide >> 64)
        for j in 1..<4 {
            wide = cast[u128](t[j]) + cast[u128](m) * cast[u128](modulus[j]) + cast[u128](carry)
            t[j - 1] = cast[u64](wide)
            carry = cast[u64](wide >> 64)
        }
        wide = cast[u128](t[4]) + cast[u128](carry)
        t[3] = cast[u64](wide)
        t[4] = t[5] + cast[u64](wide >> 64)
    }
    low : P256Element
    for i in 0..<4 {
        low[i] = t[i]
    }
    return p256_reduce_once(low, cast[SecretWord](t[4]), modulus)
}

/**
 * Multiply two numbers modulo p, in Montgomery form.
 *
 * @param a One factor, below p.
 * @param b The other, below p.
 * @return Their product, in Montgomery form, below p.
 */
p256_field_multiply #constant_time :: fn(a: P256Element, b: P256Element) -> P256Element {
    return p256_multiply(a, b, P256_P, P256_P_INVERSE)
}

/**
 * Raise a number to a public power, modulo p or n, by squaring and multiplying from the exponent's top bit.
 *
 * Which multiplications are done depends only on the exponent, which is public, so the time doesn't depend on the
 * number.
 *
 * @param a The number, in Montgomery form, below the modulus.
 * @param exponent The power, 32 big-endian bytes; public.
 * @param one 1 in Montgomery form for the modulus: P256_ONE_P, or 2^256 mod n.
 * @param modulus p or n.
 * @param inverse -1 / modulus modulo 2^64.
 * @return a raised to the power, in Montgomery form.
 */
p256_power #constant_time :: fn(a: P256Element, exponent: u8[32], one: P256Element, modulus: u64[4], inverse: u64) -> P256Element {
    result := one
    for byte in exponent {
        for bit in 0..<8 {
            result = p256_multiply(result, result, modulus, inverse)
            if ((byte >> cast[u8](7 - bit)) & 1) == 1 {
                result = p256_multiply(result, a, modulus, inverse)
            }
        }
    }
    return result
}

/**
 * Read 32 big-endian bytes as a number's limbs, not reduced.
 *
 * @param bytes The bytes.
 * @return The number, any from 0 to 2^256 - 1, as limbs; not in Montgomery form.
 */
p256_limbs #constant_time :: fn(bytes: SecretByte[32]) -> P256Element {
    e : P256Element
    for i in 0..<4 {
        word := compiler.secret(cast[u64](0))
        for j in 0..<8 {
            word = (word << 8) | cast[u64](bytes[(8 * (3 - i) + j) %% 32])
        }
        e[i] = word
    }
    return e
}

/**
 * Write a number's limbs as 32 big-endian bytes.
 *
 * @param e The number, not in Montgomery form.
 * @return Its 32 bytes, secret.
 */
p256_bytes #constant_time :: fn(e: P256Element) -> SecretByte[32] {
    bytes : SecretByte[32]
    for i in 0..<4 {
        for j in 0..<8 {
            bytes[(8 * (3 - i) + j) %% 32] = cast[SecretByte](e[i] >> (56 - 8 * cast[u64](j)))
        }
    }
    return bytes
}

/**
 * Say whether a number is below a modulus, in constant time.
 *
 * @param e The number, as limbs.
 * @param modulus p or n.
 * @return All ones if e is below the modulus, all zeros if not.
 */
p256_below #constant_time :: fn(e: P256Element, modulus: u64[4]) -> SecretWord {
    borrow := compiler.secret(cast[u64](0))
    for i in 0..<4 {
        wide := cast[u128](e[i]) - cast[u128](modulus[i]) - cast[u128](borrow)
        borrow = cast[u64](wide >> 64) & 1
    }
    return cast[SecretWord](cast[u64](0) - borrow)
}

/**
 * Say whether a number is 0, in constant time.
 *
 * @param e The number, as limbs, in Montgomery form or not.
 * @return All ones if every limb is 0, all zeros if not.
 */
p256_zero #constant_time :: fn(e: P256Element) -> SecretWord {
    bits := e[0] | e[1] | e[2] | e[3]
    // The top bit of bits - 1 is set, without bits' own, only for 0
    nonzero := ((bits | (cast[u64](0) - bits)) >> 63) & 1
    return cast[SecretWord](nonzero - 1)
}

/**
 * Put a number in Montgomery form modulo p or n.
 *
 * @param e The number, as limbs, below the modulus.
 * @param r2 2^512 mod the modulus: P256_R2_P or P256_R2_N.
 * @param modulus p or n.
 * @param inverse -1 / modulus modulo 2^64.
 * @return e * 2^256 mod the modulus.
 */
p256_to_montgomery #constant_time :: fn(e: P256Element, r2: u64[4], modulus: u64[4], inverse: u64) -> P256Element {
    return p256_multiply(e, p256_of(r2), modulus, inverse)
}

/**
 * Take a number out of Montgomery form modulo p or n.
 *
 * @param e The number in Montgomery form, below the modulus.
 * @param modulus p or n.
 * @param inverse -1 / modulus modulo 2^64.
 * @return e / 2^256 mod the modulus, as limbs.
 */
p256_from_montgomery #constant_time :: fn(e: P256Element, modulus: u64[4], inverse: u64) -> P256Element {
    return p256_multiply(e, p256_of(u64.[1, 0, 0, 0]), modulus, inverse)
}

/**
 * Make the identity, the point at infinity: (0 : 1 : 0).
 *
 * @return The identity.
 */
p256_identity #constant_time :: fn() -> P256Point {
    return P256Point.{x = p256_of(u64.[0, 0, 0, 0]), y = p256_of(P256_ONE_P), z = p256_of(u64.[0, 0, 0, 0])}
}

/**
 * Make the base point, G, in projective coordinates.
 *
 * @return G, (Gx : Gy : 1).
 */
p256_base #constant_time :: fn() -> P256Point {
    return P256Point.{x = p256_of(P256_GX), y = p256_of(P256_GY), z = p256_of(P256_ONE_P)}
}

/**
 * Add two points: Renes, Costello and Batina's complete formula for a = -3 (2016, algorithm 4), the same for any
 * two points, equal, opposite or the identity included, so nothing branches on them.
 *
 * @param p One point.
 * @param q The other; the sum doesn't depend on which is which.
 * @return p + q.
 */
p256_point_add #constant_time :: fn(p: P256Point, q: P256Point) -> P256Point {
    b := p256_of(P256_B)
    t0 := p256_field_multiply(p.x, q.x)
    t1 := p256_field_multiply(p.y, q.y)
    t2 := p256_field_multiply(p.z, q.z)
    t3 := p256_add(p.x, p.y, P256_P)
    t4 := p256_add(q.x, q.y, P256_P)
    t3 = p256_field_multiply(t3, t4)
    t4 = p256_add(t0, t1, P256_P)
    t3 = p256_subtract(t3, t4, P256_P)
    t4 = p256_add(p.y, p.z, P256_P)
    x3 := p256_add(q.y, q.z, P256_P)
    t4 = p256_field_multiply(t4, x3)
    x3 = p256_add(t1, t2, P256_P)
    t4 = p256_subtract(t4, x3, P256_P)
    x3 = p256_add(p.x, p.z, P256_P)
    y3 := p256_add(q.x, q.z, P256_P)
    x3 = p256_field_multiply(x3, y3)
    y3 = p256_add(t0, t2, P256_P)
    y3 = p256_subtract(x3, y3, P256_P)
    z3 := p256_field_multiply(b, t2)
    x3 = p256_subtract(y3, z3, P256_P)
    z3 = p256_add(x3, x3, P256_P)
    x3 = p256_add(x3, z3, P256_P)
    z3 = p256_subtract(t1, x3, P256_P)
    x3 = p256_add(t1, x3, P256_P)
    y3 = p256_field_multiply(b, y3)
    t1 = p256_add(t2, t2, P256_P)
    t2 = p256_add(t1, t2, P256_P)
    y3 = p256_subtract(y3, t2, P256_P)
    y3 = p256_subtract(y3, t0, P256_P)
    t1 = p256_add(y3, y3, P256_P)
    y3 = p256_add(t1, y3, P256_P)
    t1 = p256_add(t0, t0, P256_P)
    t0 = p256_add(t1, t0, P256_P)
    t0 = p256_subtract(t0, t2, P256_P)
    t1 = p256_field_multiply(t4, y3)
    t2 = p256_field_multiply(t0, y3)
    y3 = p256_field_multiply(x3, z3)
    y3 = p256_add(y3, t2, P256_P)
    x3 = p256_field_multiply(x3, t3)
    x3 = p256_subtract(x3, t1, P256_P)
    z3 = p256_field_multiply(t4, z3)
    t1 = p256_field_multiply(t3, t0)
    z3 = p256_add(z3, t1, P256_P)
    return P256Point.{x = x3, y = y3, z = z3}
}

/**
 * Double a point: Renes, Costello and Batina's complete formula for a = -3 (2016, algorithm 6).
 *
 * @param p The point, the identity included.
 * @return 2p.
 */
p256_point_double #constant_time :: fn(p: P256Point) -> P256Point {
    b := p256_of(P256_B)
    t0 := p256_field_multiply(p.x, p.x)
    t1 := p256_field_multiply(p.y, p.y)
    t2 := p256_field_multiply(p.z, p.z)
    t3 := p256_field_multiply(p.x, p.y)
    t3 = p256_add(t3, t3, P256_P)
    z3 := p256_field_multiply(p.x, p.z)
    z3 = p256_add(z3, z3, P256_P)
    y3 := p256_field_multiply(b, t2)
    y3 = p256_subtract(y3, z3, P256_P)
    x3 := p256_add(y3, y3, P256_P)
    y3 = p256_add(x3, y3, P256_P)
    x3 = p256_subtract(t1, y3, P256_P)
    y3 = p256_add(t1, y3, P256_P)
    y3 = p256_field_multiply(x3, y3)
    x3 = p256_field_multiply(x3, t3)
    t3 = p256_add(t2, t2, P256_P)
    t2 = p256_add(t2, t3, P256_P)
    z3 = p256_field_multiply(b, z3)
    z3 = p256_subtract(z3, t2, P256_P)
    z3 = p256_subtract(z3, t0, P256_P)
    t3 = p256_add(z3, z3, P256_P)
    z3 = p256_add(z3, t3, P256_P)
    t3 = p256_add(t0, t0, P256_P)
    t0 = p256_add(t3, t0, P256_P)
    t0 = p256_subtract(t0, t2, P256_P)
    t0 = p256_field_multiply(t0, z3)
    y3 = p256_add(y3, t0, P256_P)
    t0 = p256_field_multiply(p.y, p.z)
    t0 = p256_add(t0, t0, P256_P)
    z3 = p256_field_multiply(t0, z3)
    x3 = p256_subtract(x3, z3, P256_P)
    z3 = p256_field_multiply(t0, t1)
    z3 = p256_add(z3, z3, P256_P)
    z3 = p256_add(z3, z3, P256_P)
    return P256Point.{x = x3, y = y3, z = z3}
}

/** A point's multiples 0 to 15, for a window of four bits. */
P256Table :: distinct alias P256Point[16]

/**
 * Work out a point's multiples 0 to 15.
 *
 * @param p The point.
 * @return The table: entry i is i * p, entry 0 the identity.
 */
p256_table :: fn(p: P256Point) -> P256Table {
    table : P256Table
    table[0] = p256_identity()
    table[1] = p
    for i in 2..<16 {
        if i % 2 == 0 {
            table[i] = p256_point_double(table[i / 2])
        }
        else {
            table[i] = p256_point_add(table[i - 1], p)
        }
    }
    return table
}

/**
 * Look up a multiple in a table without the digit deciding what's read: every entry is read, and the right one kept
 * with a mask.
 *
 * @param table The table, from p256_table.
 * @param digit Which multiple, 0 to 15; secret.
 * @return digit * the table's point.
 */
p256_table_select #constant_time :: fn(table: ptr[P256Table], digit: SecretWord) -> P256Point {
    d := cast[u64](digit)
    chosen := p256_identity()
    for i in cast[u64](0)..<16 {
        found := cast[SecretBool](d == i)
        entry := table[i % 16]
        chosen.x = p256_select(found, entry.x, chosen.x)
        chosen.y = p256_select(found, entry.y, chosen.y)
        chosen.z = p256_select(found, entry.z, chosen.z)
    }
    return chosen
}

/**
 * Multiply a point by a secret scalar, in constant time: four bits at a time from the top, four doublings and an
 * addition of the window's multiple each, whatever the bits.
 *
 * @param p The point.
 * @param scalar The scalar, 32 big-endian bytes, any value; secret.
 * @return scalar * p.
 */
p256_multiply_point #constant_time :: fn(p: P256Point, scalar: SecretByte[32]) -> P256Point {
    table := p256_table(p)
    result := p256_identity()
    for i in 0..<64 {
        for d in 0..<4 {
            result = p256_point_double(result)
        }
        byte := cast[u64](scalar[i / 2])
        digit := (byte >> (4 - 4 * cast[u64](i % 2))) & 15
        result = p256_point_add(result, p256_table_select(&table, cast[SecretWord](digit)))
    }
    return result
}

/**
 * Turn a point to affine coordinates: x = X / Z, y = Y / Z, out of Montgomery form.
 *
 * @param p The point.
 * @param x Where x goes, as limbs, not in Montgomery form; 0 for the identity.
 * @param y Where y goes, the same way; 0 for the identity.
 * @return All ones if the point is the identity, which has no affine coordinates, all zeros if not.
 */
p256_affine #constant_time :: fn(p: P256Point, x: ptr[mut P256Element], y: ptr[mut P256Element]) -> SecretWord {
    inverse := p256_power(p.z, P256_P_MINUS_2, p256_of(P256_ONE_P), P256_P, P256_P_INVERSE)
    x^ = p256_from_montgomery(p256_field_multiply(p.x, inverse), P256_P, P256_P_INVERSE)
    y^ = p256_from_montgomery(p256_field_multiply(p.y, inverse), P256_P, P256_P_INVERSE)
    return p256_zero(p.z)
}

/**
 * Work out y^2 = x^3 - 3x + b's right side, for checking or finding a point.
 *
 * @param x x, in Montgomery form, below p.
 * @return x^3 - 3x + b, in Montgomery form.
 */
p256_curve_side #constant_time :: fn(x: P256Element) -> P256Element {
    x3 := p256_field_multiply(p256_field_multiply(x, x), x)
    three_x := p256_add(p256_add(x, x, P256_P), x, P256_P)
    return p256_add(p256_subtract(x3, three_x, P256_P), p256_of(P256_B), P256_P)
}

/**
 * Read a public key: a point SEC 1 writes (section 2.3.4), uncompressed (0x04, x, y) or compressed (0x02 or 0x03
 * as y is even or odd, then x), checked to be on the curve.
 *
 * @param encoded The point's bytes: 65 uncompressed or 33 compressed. A point's coordinates aren't secret.
 * @param point Where the point goes, with Z = 1; left alone if it's refused.
 * @return Whether it's a point on the curve: false for another count or first byte, a coordinate not below p, a
 *     point off the curve, a compressed x with no point, or the identity's encoding, 0x00.
 */
p256_decode_point :: fn(encoded: u8[], point: ptr[mut P256Point]) -> bool {
    if (encoded.count != 65 || encoded[0] != 0x04) && (encoded.count != 33 || (encoded[0] != 0x02 && encoded[0] != 0x03)) {
        return false
    }
    x_bytes : SecretByte[32]
    for i in 0..<32 {
        x_bytes[i] = cast[SecretByte](encoded[1 + i])
    }
    x := p256_limbs(x_bytes)
    if !compiler.declassify(cast[u64](p256_below(x, P256_P)) == ~cast[u64](0)) {
        return false
    }
    x = p256_to_montgomery(x, P256_R2_P, P256_P, P256_P_INVERSE)
    side := p256_curve_side(x)
    y := p256_of(u64.[0, 0, 0, 0])
    if encoded.count == 65 {
        y_bytes : SecretByte[32]
        for i in 0..<32 {
            y_bytes[i] = cast[SecretByte](encoded[33 + i])
        }
        y = p256_limbs(y_bytes)
        if !compiler.declassify(cast[u64](p256_below(y, P256_P)) == ~cast[u64](0)) {
            return false
        }
        y = p256_to_montgomery(y, P256_R2_P, P256_P, P256_P_INVERSE)
        squared := p256_field_multiply(y, y)
        if !compiler.declassify(cast[u64](p256_zero(p256_subtract(squared, side, P256_P))) == ~cast[u64](0)) {
            return false
        }
    }
    else {
        y = p256_power(side, P256_P_SQRT, p256_of(P256_ONE_P), P256_P, P256_P_INVERSE)
        if !compiler.declassify(cast[u64](p256_zero(p256_subtract(p256_field_multiply(y, y), side, P256_P))) == ~cast[u64](0)) {
            return false
        }
        // The root whose parity the first byte says
        plain := p256_from_montgomery(y, P256_P, P256_P_INVERSE)
        if compiler.declassify(plain[0] & 1) != cast[u64](encoded[0] & 1) {
            y = p256_subtract(p256_of(u64.[0, 0, 0, 0]), y, P256_P)
        }
    }
    point^ = P256Point.{x = x, y = y, z = p256_of(P256_ONE_P)}
    return true
}

/**
 * Read a secret key as a scalar, checking it's from 1 to n - 1, in constant time.
 *
 * @param secret_key The key's 32 bytes.
 * @param scalar Where the scalar goes, as limbs, not in Montgomery form.
 * @return Whether the key is from 1 to n - 1; this answer is declassified, as a key outside is refused.
 */
p256_secret_scalar #constant_time :: fn(secret_key: ptr[P256SecretKey], scalar: ptr[mut P256Element]) -> bool {
    bytes : SecretByte[32]
    for i in 0..<32 {
        bytes[i] = cast[SecretByte](secret_key[i])
    }
    scalar^ = p256_limbs(bytes)
    good := cast[u64](p256_below(scalar^, P256_N)) & ~cast[u64](p256_zero(scalar^))
    return compiler.declassify(good) != 0
}

/**
 * Write a point's affine coordinates as SEC 1's uncompressed form.
 *
 * @param x x, as limbs, not in Montgomery form.
 * @param y y, the same way.
 * @return 0x04, then x and y, 32 big-endian bytes each.
 */
p256_encode #constant_time :: fn(x: P256Element, y: P256Element) -> P256PublicKey {
    encoded : P256PublicKey
    encoded[0] = 0x04
    x_bytes := p256_bytes(x)
    y_bytes := p256_bytes(y)
    for i in 0..<32 {
        encoded[1 + i] = compiler.declassify(cast[u8](x_bytes[i]))
        encoded[33 + i] = compiler.declassify(cast[u8](y_bytes[i]))
    }
    return encoded
}

/**
 * Work out a secret key's public key, in constant time: d * G.
 *
 * A secret key is made from 32 bytes from a secure random generator, drawn again in the rare case (about 1 in 2^32)
 * this refuses them.
 *
 * @param secret_key The secret key, d, which has to be from 1 to n - 1 as a big-endian number.
 * @param public_key Where the public key goes, SEC 1's uncompressed point; left alone if the key is refused.
 * @return Whether the secret key is from 1 to n - 1, and so the public key written.
 */
p256_public_key #constant_time :: fn(secret_key: ptr[P256SecretKey], public_key: ptr[mut P256PublicKey]) -> bool {
    scalar : P256Element
    if !p256_secret_scalar(secret_key, &scalar) {
        return false
    }
    point := p256_multiply_point(p256_base(), p256_bytes(scalar))
    x : P256Element
    y : P256Element
    _ = p256_affine(point, &x, &y)
    public_key^ = p256_encode(x, y)
    return true
}

/**
 * Agree on a shared secret with P-256 ECDH (SEC 1, section 3.3.1), in constant time: the x coordinate of d * Q.
 *
 * @param secret_key This side's secret key, d, from 1 to n - 1.
 * @param public_key The other side's public key, Q: SEC 1's uncompressed point, 65 bytes, as TLS 1.3 sends it, or
 *     compressed, 33 bytes. It's checked to be on the curve; as P-256's group has a prime order, any point on it but
 *     the identity is a good one.
 * @param shared Where the shared secret goes: x, 32 big-endian bytes. Like X25519's, it isn't a key yet: put it
 *     through HKDF with what both sides saw.
 * @return Whether both keys were good and the secret was written: false, with nothing written, for a secret key not
 *     from 1 to n - 1, or a public key that isn't a point on the curve.
 */
p256_ecdh #constant_time :: fn(secret_key: ptr[P256SecretKey], public_key: u8[], shared: ptr[mut SecretByte[32]]) -> bool {
    point : P256Point
    if !p256_decode_point(public_key, &point) {
        return false
    }
    scalar : P256Element
    if !p256_secret_scalar(secret_key, &scalar) {
        return false
    }
    product := p256_multiply_point(point, p256_bytes(scalar))
    x : P256Element
    y : P256Element
    if compiler.declassify(cast[u64](p256_affine(product, &x, &y))) != 0 {
        return false
    }
    shared^ = p256_bytes(x)
    return true
}

/**
 * Read a digest as ECDSA's z (FIPS 186-5, section 6.4.1, and RFC 6979's bits2int, then reduced): its leftmost 256
 * bits as a big-endian number, reduced modulo n.
 *
 * @param digest The message's digest, of any length: a longer one's leftmost 32 bytes are taken, and a shorter one is
 *     a smaller number.
 * @return z, as limbs, below n.
 */
p256_digest_scalar #constant_time :: fn(digest: SecretByte[]) -> P256Element {
    bytes : SecretByte[32]
    if digest.count >= 32 {
        for i in 0..<32 {
            bytes[i] = digest[i]
        }
    }
    else {
        for byte, i in digest {
            bytes[(32 - digest.count + i) % 32] = byte
        }
    }
    return p256_reduce_once(p256_limbs(bytes), cast[SecretWord](0), P256_N)
}

/**
 * Work out RFC 6979's deterministic nonce for P-256 with HMAC-SHA-256 (section 3.2), with extra random bytes mixed
 * in as section 3.6 allows.
 *
 * @param key The secret key's scalar, as limbs, from 1 to n - 1.
 * @param z The digest as a scalar, below n, from p256_digest_scalar: bits2octets(h1) is its bytes.
 * @param random Extra bytes mixed into the HMAC key, of any length, empty included.
 * @param attempt Which candidate to give, from 0: each is RFC 6979's next, used when the one before was refused.
 * @return The nonce, k, as 32 big-endian bytes; the caller checks it's from 1 to n - 1.
 */
p256_rfc6979_nonce #constant_time :: fn(key: P256Element, z: P256Element, random: SecretByte[], attempt: usize) -> SecretByte[32] {
    x := p256_bytes(key)
    h := p256_bytes(z)
    v : SecretByte[32]
    k : SecretByte[32]
    for i in 0..<32 {
        v[i] = cast[SecretByte](1)
        k[i] = cast[SecretByte](0)
    }
    for round in u8.[0, 1] {
        mac := hmac_sha256_start(k)
        hmac_sha256_update_secret(&mac, v)
        hmac_sha256_update(&mac, u8.[round])
        hmac_sha256_update_secret(&mac, x)
        hmac_sha256_update_secret(&mac, h)
        hmac_sha256_update_secret(&mac, random)
        k = hmac_sha256_finish(&mac)
        mac = hmac_sha256_start(k)
        hmac_sha256_update_secret(&mac, v)
        v = hmac_sha256_finish(&mac)
    }
    for i in 0..<attempt + 1 {
        if i > 0 {
            mac := hmac_sha256_start(k)
            hmac_sha256_update_secret(&mac, v)
            hmac_sha256_update(&mac, u8.[0])
            k = hmac_sha256_finish(&mac)
            mac = hmac_sha256_start(k)
            hmac_sha256_update_secret(&mac, v)
            v = hmac_sha256_finish(&mac)
        }
        mac := hmac_sha256_start(k)
        hmac_sha256_update_secret(&mac, v)
        v = hmac_sha256_finish(&mac)
    }
    return v
}

/**
 * Sign a message's digest with P-256 ECDSA (FIPS 186-5, section 6.4.1), in constant time, the nonce from RFC 6979.
 *
 * @param secret_key The secret key, d, from 1 to n - 1.
 * @param digest The message's digest, from the hash the signature is for, like SHA-256's 32 bytes, which TLS's
 *     ecdsa_secp256r1_sha256 uses; of any length, its leftmost 32 bytes taken when it's longer. Public.
 * @param random Extra random bytes mixed into the nonce, which keep a fault from giving the key away; empty for
 *     RFC 6979's nonce alone, which gives the same signature each time.
 * @return The signature, (r, s), public; or null when the secret key isn't from 1 to n - 1.
 */
p256_ecdsa_sign #constant_time :: fn(secret_key: ptr[P256SecretKey], digest: u8[], random: SecretByte[]) -> P256Signature? {
    d : P256Element
    if !p256_secret_scalar(secret_key, &d) {
        return null
    }
    z := p256_digest_scalar(as_secret(digest))
    one_n := p256_to_montgomery(p256_of(u64.[1, 0, 0, 0]), P256_R2_N, P256_N, P256_N_INVERSE)
    // Each candidate nonce from 1 to n - 1 gives r and s; a 0 for either, about 1 in 2^256, takes the next
    for attempt in cast[usize](0)..<64 {
        k_bytes := p256_rfc6979_nonce(d, z, random, attempt)
        k := p256_limbs(k_bytes)
        good := cast[u64](p256_below(k, P256_N)) & ~cast[u64](p256_zero(k))
        if compiler.declassify(good) != 0 {
            point := p256_multiply_point(p256_base(), k_bytes)
            x : P256Element
            y : P256Element
            _ = p256_affine(point, &x, &y)
            r := p256_reduce_once(x, cast[SecretWord](0), P256_N)
            // s = (z + r * d) / k, in Montgomery form modulo n
            k_m := p256_to_montgomery(k, P256_R2_N, P256_N, P256_N_INVERSE)
            k_inverse := p256_power(k_m, P256_N_MINUS_2, one_n, P256_N, P256_N_INVERSE)
            r_m := p256_to_montgomery(r, P256_R2_N, P256_N, P256_N_INVERSE)
            d_m := p256_to_montgomery(d, P256_R2_N, P256_N, P256_N_INVERSE)
            z_m := p256_to_montgomery(z, P256_R2_N, P256_N, P256_N_INVERSE)
            sum := p256_add(z_m, p256_multiply(r_m, d_m, P256_N, P256_N_INVERSE), P256_N)
            s := p256_from_montgomery(p256_multiply(sum, k_inverse, P256_N, P256_N_INVERSE), P256_N, P256_N_INVERSE)
            zeros := cast[u64](p256_zero(r)) | cast[u64](p256_zero(s))
            if compiler.declassify(zeros) == 0 {
                signature : P256Signature
                r_bytes := p256_bytes(r)
                s_bytes := p256_bytes(s)
                for i in 0..<32 {
                    signature[i] = compiler.declassify(cast[u8](r_bytes[i]))
                    signature[32 + i] = compiler.declassify(cast[u8](s_bytes[i]))
                }
                return signature
            }
        }
    }
    return null
}

/**
 * Read one of a signature's numbers, checking it's from 1 to n - 1.
 *
 * @param bytes Its 32 big-endian bytes.
 * @param scalar Where it goes, in Montgomery form modulo n.
 * @return Whether it's from 1 to n - 1.
 */
p256_signature_scalar #constant_time :: fn(bytes: u8[], scalar: ptr[mut P256Element]) -> bool {
    secret : SecretByte[32]
    for i in cast[usize](0)..<32 {
        if i < bytes.count {
            secret[i] = cast[SecretByte](bytes[i])
        }
    }
    value := p256_limbs(secret)
    good := cast[u64](p256_below(value, P256_N)) & ~cast[u64](p256_zero(value))
    if bytes.count != 32 || compiler.declassify(good) == 0 {
        return false
    }
    scalar^ = p256_to_montgomery(value, P256_R2_N, P256_N, P256_N_INVERSE)
    return true
}

/**
 * Work out a multiple of a point from a table, for verifying, where the digits are public: the additions of zero
 * digits are skipped.
 *
 * @param table The point's multiples, from p256_table.
 * @param result The sum so far, which the multiple is added to.
 * @param digit The digit, 0 to 15, public.
 */
p256_add_public_digit :: fn(table: ptr[P256Table], result: ptr[mut P256Point], digit: usize) {
    if digit != 0 {
        result^ = p256_point_add(result^, table[digit % 16])
    }
}

/**
 * Verify a P-256 ECDSA signature on a message's digest (FIPS 186-5, section 6.4.2).
 *
 * Only public values are worked with, so it isn't constant time: u1 * G + u2 * Q in one chain of doublings, four bits
 * of each at a time.
 *
 * @param public_key The signer's public key, Q: SEC 1's uncompressed point, 65 bytes, or compressed, 33.
 * @param digest The message's digest from the hash the signature is for, of any length, as p256_ecdsa_sign takes it.
 * @param signature The signature, r then s.
 * @return Whether it's a signature by that key on that digest: false too for a public key that isn't a point on the
 *     curve, or an r or s that isn't from 1 to n - 1.
 */
p256_ecdsa_verify :: fn(public_key: u8[], digest: u8[], signature: ptr[P256Signature]) -> bool {
    q : P256Point
    if !p256_decode_point(public_key, &q) {
        return false
    }
    r : P256Element
    s : P256Element
    if !p256_signature_scalar(signature[0..<32], &r) || !p256_signature_scalar(signature[32..<64], &s) {
        return false
    }
    one_n := p256_to_montgomery(p256_of(u64.[1, 0, 0, 0]), P256_R2_N, P256_N, P256_N_INVERSE)
    w := p256_power(s, P256_N_MINUS_2, one_n, P256_N, P256_N_INVERSE)
    z := p256_to_montgomery(p256_digest_scalar(as_secret(digest)), P256_R2_N, P256_N, P256_N_INVERSE)
    u1 := p256_bytes(p256_from_montgomery(p256_multiply(z, w, P256_N, P256_N_INVERSE), P256_N, P256_N_INVERSE))
    u2 := p256_bytes(p256_from_montgomery(p256_multiply(r, w, P256_N, P256_N_INVERSE), P256_N, P256_N_INVERSE))
    g_table := p256_table(p256_base())
    q_table := p256_table(q)
    sum := p256_identity()
    for i in 0..<64 {
        for d in 0..<4 {
            sum = p256_point_double(sum)
        }
        shift := cast[u8](4 - 4 * (i % 2))
        p256_add_public_digit(&g_table, &sum, cast[usize]((compiler.declassify(cast[u8](u1[i / 2])) >> shift) & 15))
        p256_add_public_digit(&q_table, &sum, cast[usize]((compiler.declassify(cast[u8](u2[i / 2])) >> shift) & 15))
    }
    x : P256Element
    y : P256Element
    if compiler.declassify(cast[u64](p256_affine(sum, &x, &y))) != 0 {
        return false
    }
    // x mod n against r, as numbers
    x_mod_n := p256_reduce_once(x, cast[SecretWord](0), P256_N)
    r_plain := p256_from_montgomery(r, P256_N, P256_N_INVERSE)
    return compiler.declassify(cast[u64](p256_zero(p256_subtract(x_mod_n, r_plain, P256_N)))) != 0
}
