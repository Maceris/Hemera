package crypto

import compiler from "base"

/*
 * ML-KEM-768 (FIPS 203): a key encapsulation mechanism from module lattices, which quantum computers aren't known to
 * break. One side makes a key pair and sends its public (encapsulation) key; the other encapsulates a shared secret to
 * it, sending the ciphertext; the first decapsulates the same secret from it.
 *
 *     crypto.ml_kem_768_key_pair(&d, &z, &public, &secret)
 *     _ = crypto.ml_kem_768_encapsulate(&public, &m, &ciphertext, &shared)      // the other side
 *     _ = crypto.ml_kem_768_decapsulate(&secret, &ciphertext, &shared)
 *
 * Its randomness, d and z for a key pair and m to encapsulate, is the caller's: 32 bytes each from a secure generator.
 * A ciphertext that's been changed decapsulates to a secret derived from z and the ciphertext instead (implicit
 * rejection), which the other side won't share, so nothing about the secret key is told by what comes of it.
 *
 * Polynomials have 256 coefficients modulo q = 3329, kept below q in u16s, each operation reducing with Barrett's
 * method rather than dividing; the transform is FIPS 203's NTT, with its tables of powers of 17. Everything working
 * with the secret key or the message is #constant_time.
 */

/** ML-KEM's modulus, q. */
ML_KEM_Q :: 3329
/** k for ML-KEM-768: polynomials in a vector. */
ML_KEM_768_K :: 3
/** Its public (encapsulation) key's bytes: 384 a polynomial of t, then ρ. */
ML_KEM_768_PUBLIC_KEY_BYTES :: 1184
/** Its secret (decapsulation) key's bytes: s, the public key, its hash, and z. */
ML_KEM_768_SECRET_KEY_BYTES :: 2400
/** Its ciphertext's bytes: u at 10 bits a coefficient, then v at 4. */
ML_KEM_768_CIPHERTEXT_BYTES :: 1088
/** The shared secret's bytes. */
ML_KEM_SHARED_BYTES :: 32

/** An ML-KEM-768 public key, as sent. */
MlKem768PublicKey :: distinct alias u8[1184]
/** An ML-KEM-768 secret key, as FIPS 203 encodes it. */
MlKem768SecretKey :: distinct alias u8[2400] #secret
/** An ML-KEM-768 ciphertext, as sent. */
MlKem768Ciphertext :: distinct alias u8[1088]

/** A polynomial's coefficients, each below q. Secret, as most are made from the secret key or the message. */
MlKemPoly :: distinct alias u16[256] #secret

/** ζ^BitRev7(i) for the NTT, ζ = 17 (FIPS 203, Appendix A). */
ML_KEM_ZETAS :: u64.[
    1, 1729, 2580, 3289, 2642, 630, 1897, 848, 1062, 1919, 193, 797, 2786, 3260, 569, 1746,
    296, 2447, 1339, 1476, 3046, 56, 2240, 1333, 1426, 2094, 535, 2882, 2393, 2879, 1974, 821,
    289, 331, 3253, 1756, 1197, 2304, 2277, 2055, 650, 1977, 2513, 632, 2865, 33, 1320, 1915,
    2319, 1435, 807, 452, 1438, 2868, 1534, 2402, 2647, 2617, 1481, 648, 2474, 3110, 1227, 910,
    17, 2761, 583, 2649, 1637, 723, 2288, 1100, 1409, 2662, 3281, 233, 756, 2156, 3015, 3050,
    1703, 1651, 2789, 1789, 1847, 952, 1461, 2687, 939, 2308, 2437, 2388, 733, 2337, 268, 641,
    1584, 2298, 2037, 3220, 375, 2549, 2090, 1645, 1063, 319, 2773, 757, 2099, 561, 2466, 2594,
    2804, 1092, 403, 1026, 1143, 2150, 2775, 886, 1722, 1212, 1874, 1029, 2110, 2935, 885, 2154]

/** ζ^(2 BitRev7(i) + 1) for multiplying in the NTT's domain (FIPS 203, Appendix A). */
ML_KEM_GAMMAS :: u64.[
    17, 3312, 2761, 568, 583, 2746, 2649, 680, 1637, 1692, 723, 2606, 2288, 1041, 1100, 2229,
    1409, 1920, 2662, 667, 3281, 48, 233, 3096, 756, 2573, 2156, 1173, 3015, 314, 3050, 279,
    1703, 1626, 1651, 1678, 2789, 540, 1789, 1540, 1847, 1482, 952, 2377, 1461, 1868, 2687, 642,
    939, 2390, 2308, 1021, 2437, 892, 2388, 941, 733, 2596, 2337, 992, 268, 3061, 641, 2688,
    1584, 1745, 2298, 1031, 2037, 1292, 3220, 109, 375, 2954, 2549, 780, 2090, 1239, 1645, 1684,
    1063, 2266, 319, 3010, 2773, 556, 757, 2572, 2099, 1230, 561, 2768, 2466, 863, 2594, 735,
    2804, 525, 1092, 2237, 403, 2926, 1026, 2303, 1143, 2186, 2150, 1179, 2775, 554, 886, 2443,
    1722, 1607, 1212, 2117, 1874, 1455, 1029, 2300, 2110, 1219, 2935, 394, 885, 2444, 2154, 1175]

// ---- Arithmetic modulo q

/**
 * Subtract q if it's not more: a value below 2q brought below q, without branching.
 *
 * @param x A value below 2q.
 * @return x mod q.
 */
ml_kem_fold #constant_time :: fn(x: SecretWord) -> SecretWord {
    d :: x - ML_KEM_Q
    return d + (ML_KEM_Q & (0 - (d >> 63)))
}

/**
 * Reduce modulo q by Barrett's method: x times 2^32 / q's floor, shifted, is x / q or one less.
 *
 * @param x A value below 2^32.
 * @return x mod q.
 */
ml_kem_reduce #constant_time :: fn(x: SecretWord) -> SecretWord {
    t :: (x * 1290167) >> 32
    return ml_kem_fold(x - t * ML_KEM_Q)
}

/** A coefficient as a SecretWord, to work on. */
ml_kem_word #constant_time :: fn(f: ptr[MlKemPoly], i: usize) -> SecretWord {
    return cast[SecretWord](f[i % 256])
}

/**
 * Divide by q, rounding down, by multiplying: exact for what Compress divides.
 *
 * @param x A value below 2^23.
 * @return x / q.
 */
ml_kem_divide #constant_time :: fn(x: SecretWord) -> SecretWord {
    return (x * 1290168) >> 32
}

// ---- The NTT (FIPS 203, Algorithms 9 to 12)

/**
 * Transform a polynomial into the NTT's domain (Algorithm 9).
 *
 * @param f The polynomial, transformed in place.
 */
ml_kem_ntt #constant_time :: fn(f: ptr[mut MlKemPoly]) {
    i := cast[usize](1)
    length := cast[usize](128)
    loop {
        start := cast[usize](0)
        loop {
            zeta :: cast[SecretWord](ML_KEM_ZETAS[i % 128])
            i += 1
            for j in start..<start + length {
                t :: ml_kem_reduce(zeta * ml_kem_word(f, j + length))
                low :: ml_kem_word(f, j)
                f[(j + length) % 256] = cast[u16](ml_kem_fold(low + ML_KEM_Q - t))
                f[j % 256] = cast[u16](ml_kem_fold(low + t))
            }
            start += 2 * length
        }
        while start < 256
        length /= 2
    }
    while length >= 2
}

/**
 * Transform a polynomial back from the NTT's domain (Algorithm 10).
 *
 * @param f The polynomial, transformed in place.
 */
ml_kem_inverse_ntt #constant_time :: fn(f: ptr[mut MlKemPoly]) {
    i := cast[usize](127)
    length := cast[usize](2)
    loop {
        start := cast[usize](0)
        loop {
            zeta :: cast[SecretWord](ML_KEM_ZETAS[i % 128])
            i -= 1
            for j in start..<start + length {
                t :: ml_kem_word(f, j)
                high :: ml_kem_word(f, j + length)
                f[j % 256] = cast[u16](ml_kem_fold(t + high))
                f[(j + length) % 256] = cast[u16](ml_kem_reduce(zeta * ml_kem_fold(high + ML_KEM_Q - t)))
            }
            start += 2 * length
        }
        while start < 256
        length *= 2
    }
    while length <= 128
    // 128's inverse, 3303
    for i in cast[usize](0)..<256 {
        f[i] = cast[u16](ml_kem_reduce(ml_kem_word(f, i) * 3303))
    }
}

/**
 * Multiply two polynomials in the NTT's domain, adding the product to a third (Algorithms 11 and 12).
 *
 * @param sum Where the product's added.
 * @param f One polynomial.
 * @param g The other.
 */
ml_kem_multiply_add #constant_time :: fn(sum: ptr[mut MlKemPoly], f: ptr[MlKemPoly], g: ptr[MlKemPoly]) {
    for i in cast[usize](0)..<128 {
        a0 :: ml_kem_word(f, 2 * i)
        a1 :: ml_kem_word(f, 2 * i + 1)
        b0 :: ml_kem_word(g, 2 * i)
        b1 :: ml_kem_word(g, 2 * i + 1)
        c0 :: ml_kem_reduce(a0 * b0 + ml_kem_reduce(a1 * b1) * cast[SecretWord](ML_KEM_GAMMAS[i % 128]))
        c1 :: ml_kem_reduce(a0 * b1 + a1 * b0)
        sum[(2 * i) % 256] = cast[u16](ml_kem_fold(ml_kem_word(sum, 2 * i) + c0))
        sum[(2 * i + 1) % 256] = cast[u16](ml_kem_fold(ml_kem_word(sum, 2 * i + 1) + c1))
    }
}

/**
 * Add one polynomial to another.
 *
 * @param sum Where it's added.
 * @param f What's added.
 */
ml_kem_add #constant_time :: fn(sum: ptr[mut MlKemPoly], f: ptr[MlKemPoly]) {
    for i in cast[usize](0)..<256 {
        sum[i] = cast[u16](ml_kem_fold(ml_kem_word(sum, i) + ml_kem_word(f, i)))
    }
}

// ---- Encoding (Algorithms 5 and 6) and compression (FIPS 203, 4.2.1)

/**
 * Encode a polynomial's coefficients at d bits each, little-endian (ByteEncode_d).
 *
 * @param f The polynomial, each coefficient below 2^d.
 * @param d The bits each: 1, 4, 10 or 12.
 * @param output Where the 32 d bytes go.
 */
ml_kem_encode #constant_time :: fn(f: ptr[MlKemPoly], d: u64, output: mut SecretByte[]) {
    held := cast[SecretWord](0)
    bits := cast[u64](0)
    at := cast[usize](0)
    for i in cast[usize](0)..<256 {
        held = held | (ml_kem_word(f, i) << bits)
        bits += d
        loop {
            if at < output.count {
                output[at] = cast[SecretByte](held)
            }
            at += 1
            held = held >> 8
            bits -= 8
        }
        while bits >= 8
    }
}

/**
 * Decode a polynomial's coefficients from d bits each (ByteDecode_d): each below 2^d, so for d = 12 one may be q or
 * more, which ml_kem_768_check_public_key looks for.
 *
 * @param input The 32 d bytes.
 * @param d The bits each: 1, 4, 10 or 12.
 * @param f Where the coefficients go.
 */
ml_kem_decode #constant_time :: fn(input: SecretByte[], d: u64, f: ptr[mut MlKemPoly]) {
    held := cast[SecretWord](0)
    bits := cast[u64](0)
    at := cast[usize](0)
    mask :: (cast[u64](1) << d) - 1
    for i in cast[usize](0)..<256 {
        loop {
            byte :: if at < input.count { cast[SecretWord](input[at]) } else { cast[SecretWord](0) }
            held = held | (byte << bits)
            bits += 8
            at += 1
        }
        while bits < d
        f[i] = cast[u16](held & cast[SecretWord](mask))
        held = held >> d
        bits -= d
    }
}

/**
 * Compress each coefficient to d bits: round(2^d / q x) mod 2^d.
 *
 * @param f The polynomial, compressed in place.
 * @param d The bits: 1, 4 or 10.
 */
ml_kem_compress #constant_time :: fn(f: ptr[mut MlKemPoly], d: u64) {
    for i in cast[usize](0)..<256 {
        f[i] = cast[u16](ml_kem_divide((ml_kem_word(f, i) << d) + ML_KEM_Q / 2) & cast[SecretWord]((cast[u64](1) << d) - 1))
    }
}

/**
 * Decompress each coefficient from d bits: round(q / 2^d y).
 *
 * @param f The polynomial, decompressed in place.
 * @param d The bits: 1, 4 or 10.
 */
ml_kem_decompress #constant_time :: fn(f: ptr[mut MlKemPoly], d: u64) {
    for i in cast[usize](0)..<256 {
        f[i] = cast[u16]((ml_kem_word(f, i) * ML_KEM_Q + cast[SecretWord](cast[u64](1) << (d - 1))) >> d)
    }
}

// ---- Sampling (Algorithms 7 and 8)

/**
 * Sample a polynomial in the NTT's domain from ρ and two indices (SampleNTT): SHAKE128's output, three bytes giving
 * two candidates of 12 bits, each kept if it's below q. Public, as ρ is.
 *
 * @param rho ρ, the public key's seed.
 * @param j The column.
 * @param i The row.
 * @param f Where the polynomial goes.
 */
ml_kem_sample_ntt #constant_time :: fn(rho: u8[], j: u8, i: u8, f: ptr[mut MlKemPoly]) {
    seed : u8[34]
    for byte, at in rho {
        if at < 32 {
            seed[at] = byte
        }
    }
    seed[32] = j
    seed[33] = i
    sponge := shake128_start()
    keccak_absorb(&sponge, as_secret(seed[0..<34]))
    block : u8[SHAKE128_RATE]
    count := cast[usize](0)
    loop {
        keccak_squeeze_public(&sponge, block[0..<block.count])
        with {
            at := cast[usize](0)
        }
        loop {
            second :: at + 1
            third :: at + 2
            b0 :: if at < block.count { cast[u64](block[at]) } else { cast[u64](0) }
            b1 :: if second < block.count { cast[u64](block[second]) } else { cast[u64](0) }
            b2 :: if third < block.count { cast[u64](block[third]) } else { cast[u64](0) }
            d1 :: b0 | ((b1 & 15) << 8)
            d2 :: (b1 >> 4) | (b2 << 4)
            if d1 < ML_KEM_Q && count < 256 {
                f[count] = cast[u16](d1)
                count += 1
            }
            if d2 < ML_KEM_Q && count < 256 {
                f[count] = cast[u16](d2)
                count += 1
            }
            at += 3
        }
        while at + 3 <= block.count && count < 256
    }
    while count < 256
}

/**
 * Sample a polynomial from the centered binomial distribution with η = 2 (SamplePolyCBD): PRF's 128 bytes of
 * SHAKE256(s ‖ b), each coefficient the difference of two sums of two bits.
 *
 * @param s The 32-byte seed, secret.
 * @param b The counter.
 * @param f Where the polynomial goes.
 */
ml_kem_sample_cbd #constant_time :: fn(s: SecretByte[], b: u8, f: ptr[mut MlKemPoly]) {
    sponge := shake256_start()
    keccak_absorb(&sponge, s)
    counter : u8[1]
    counter[0] = b
    keccak_absorb(&sponge, as_secret(counter[0..<1]))
    bytes : SecretByte[128]
    keccak_squeeze(&sponge, bytes[0..<128])
    for i in cast[usize](0)..<128 {
        byte :: cast[SecretWord](bytes[i])
        for half in cast[usize](0)..<2 {
            nibble :: byte >> (4 * cast[u64](half))
            x :: (nibble & 1) + ((nibble >> 1) & 1)
            y :: ((nibble >> 2) & 1) + ((nibble >> 3) & 1)
            f[(2 * i + half) % 256] = cast[u16](ml_kem_fold(x + ML_KEM_Q - y))
        }
    }
}

// ---- Parts of keys and ciphertexts

/** Bytes from an offset, as many as asked, or none if they aren't all there. */
ml_kem_part :: fn(bytes: u8[], from: usize, count: usize) -> u8[] {
    end :: from + count
    return if from <= end && end <= bytes.count { bytes[from..<end] } else { bytes[0..<0] }
}

/** The same, of secret bytes. */
ml_kem_secret_part #constant_time :: fn(bytes: SecretByte[], from: usize, count: usize) -> SecretByte[] {
    end :: from + count
    return if from <= end && end <= bytes.count { bytes[from..<end] } else { bytes[0..<0] }
}

/** The same, of secret bytes to write. */
ml_kem_output_part #constant_time :: fn(bytes: mut SecretByte[], from: usize, count: usize) -> mut SecretByte[] {
    end :: from + count
    return if from <= end && end <= bytes.count { bytes[from..<end] } else { bytes[0..<0] }
}

// ---- K-PKE (Algorithms 13 to 15)

/** K-PKE's public matrix, Â, row by row. */
MlKemMatrix :: struct {
    rows : MlKemPoly[9],
}

/** A vector of k polynomials. */
MlKemVector :: struct {
    polys : MlKemPoly[3],
}

/**
 * Make Â from ρ: Â[i][j] = SampleNTT(ρ ‖ j ‖ i), or its transpose.
 *
 * @param rho ρ.
 * @param transposed Whether to make Âᵀ, as encryption wants.
 * @param a Where it goes.
 */
ml_kem_matrix :: fn(rho: u8[], transposed: bool, a: ptr[mut MlKemMatrix]) {
    for i in cast[usize](0)..<3 {
        for j in cast[usize](0)..<3 {
            row :: if transposed { j } else { i }
            column :: if transposed { i } else { j }
            ml_kem_sample_ntt(rho, cast[u8](column), cast[u8](row), &a.rows[(3 * i + j) % 9])
        }
    }
}

/**
 * Hash with G, SHA3-512, into two 32-byte halves.
 *
 * @param data The bytes: one part.
 * @param more Another part after it, or none.
 * @param first The first half.
 * @param second The second.
 */
ml_kem_g #constant_time :: fn(data: SecretByte[], more: SecretByte[], first: ptr[mut SecretByte[32]], second: ptr[mut SecretByte[32]]) {
    sponge := sha3_512_start()
    keccak_absorb(&sponge, data)
    keccak_absorb(&sponge, more)
    digest : SecretByte[64]
    keccak_squeeze(&sponge, digest[0..<64])
    for i in cast[usize](0)..<32 {
        first[i] = digest[i]
        second[i] = digest[32 + i]
    }
}

/**
 * K-PKE's encryption: the message, under the public key, with randomness r (Algorithm 14).
 *
 * @param public The public key: t̂ encoded, then ρ.
 * @param message The 32-byte message.
 * @param r The 32 bytes of randomness.
 * @param ciphertext Where the ciphertext goes.
 */
ml_kem_encrypt #constant_time :: fn(public: ptr[MlKem768PublicKey], message: ptr[SecretByte[32]], r: ptr[SecretByte[32]],
    ciphertext: mut SecretByte[]) {

    t : MlKemVector
    for i in cast[usize](0)..<3 {
        ml_kem_decode(as_secret(ml_kem_part(public[0..<1184], 384 * i, 384)), 12, &t.polys[i])
    }
    a : MlKemMatrix
    ml_kem_matrix(ml_kem_part(public[0..<1184], 1152, 32), true, &a)
    y : MlKemVector
    for i in cast[usize](0)..<3 {
        ml_kem_sample_cbd(r[0..<32], cast[u8](i), &y.polys[i])
        ml_kem_ntt(&y.polys[i])
    }
    // u = NTT⁻¹(Âᵀ ŷ) + e₁
    for i in cast[usize](0)..<3 {
        u : MlKemPoly
        for j in cast[usize](0)..<3 {
            ml_kem_multiply_add(&u, &a.rows[(3 * i + j) % 9], &y.polys[j])
        }
        ml_kem_inverse_ntt(&u)
        e1 : MlKemPoly
        ml_kem_sample_cbd(r[0..<32], cast[u8](3 + i), &e1)
        ml_kem_add(&u, &e1)
        ml_kem_compress(&u, 10)
        ml_kem_encode(&u, 10, ml_kem_output_part(ciphertext, 320 * i, 320))
    }
    // v = NTT⁻¹(t̂ᵀ ŷ) + e₂ + μ
    v : MlKemPoly
    for j in cast[usize](0)..<3 {
        ml_kem_multiply_add(&v, &t.polys[j], &y.polys[j])
    }
    ml_kem_inverse_ntt(&v)
    e2 : MlKemPoly
    ml_kem_sample_cbd(r[0..<32], 6, &e2)
    ml_kem_add(&v, &e2)
    mu : MlKemPoly
    ml_kem_decode(message[0..<32], 1, &mu)
    ml_kem_decompress(&mu, 1)
    ml_kem_add(&v, &mu)
    ml_kem_compress(&v, 4)
    ml_kem_encode(&v, 4, ml_kem_output_part(ciphertext, 960, 128))
}

/**
 * K-PKE's decryption (Algorithm 15).
 *
 * @param s ŝ encoded, the secret key's first 1152 bytes.
 * @param ciphertext The ciphertext.
 * @param message Where the 32-byte message goes.
 */
ml_kem_decrypt #constant_time :: fn(s: SecretByte[], ciphertext: ptr[MlKem768Ciphertext], message: ptr[mut SecretByte[32]]) {
    w : MlKemPoly
    for i in cast[usize](0)..<3 {
        u : MlKemPoly
        ml_kem_decode(as_secret(ml_kem_part(ciphertext[0..<1088], 320 * i, 320)), 10, &u)
        ml_kem_decompress(&u, 10)
        ml_kem_ntt(&u)
        secret : MlKemPoly
        ml_kem_decode(ml_kem_secret_part(s, 384 * i, 384), 12, &secret)
        ml_kem_multiply_add(&w, &secret, &u)
    }
    ml_kem_inverse_ntt(&w)
    v : MlKemPoly
    ml_kem_decode(as_secret(ml_kem_part(ciphertext[0..<1088], 960, 128)), 4, &v)
    ml_kem_decompress(&v, 4)
    // w = v - NTT⁻¹(ŝᵀ û)
    for i in cast[usize](0)..<256 {
        w[i] = cast[u16](ml_kem_fold(ml_kem_word(&v, i) + ML_KEM_Q - ml_kem_word(&w, i)))
    }
    ml_kem_compress(&w, 1)
    ml_kem_encode(&w, 1, message[0..<32])
}

// ---- ML-KEM (Algorithms 16 to 18, and 19 to 21's checks)

/**
 * Make a key pair from its randomness (ML-KEM.KeyGen_internal): the same d and z make the same keys.
 *
 * @param d 32 random bytes, which make K-PKE's keys.
 * @param z 32 random bytes, which implicit rejection derives its secret from.
 * @param public Where the public key goes.
 * @param secret Where the secret key goes.
 */
ml_kem_768_key_pair #constant_time :: fn(d: ptr[SecretByte[32]], z: ptr[SecretByte[32]], public: ptr[mut MlKem768PublicKey],
    secret: ptr[mut MlKem768SecretKey]) {

    // (ρ, σ) = G(d ‖ k)
    k : SecretByte[1]
    k[0] = 3
    rho_secret : SecretByte[32]
    sigma : SecretByte[32]
    ml_kem_g(d[0..<32], k[0..<1], &rho_secret, &sigma)
    rho : u8[32]
    for i in cast[usize](0)..<32 {
        rho[i] = compiler.declassify(cast[u8](rho_secret[i]))
    }
    a : MlKemMatrix
    ml_kem_matrix(rho[0..<32], false, &a)
    s : MlKemVector
    e : MlKemVector
    for i in cast[usize](0)..<3 {
        ml_kem_sample_cbd(sigma[0..<32], cast[u8](i), &s.polys[i])
        ml_kem_ntt(&s.polys[i])
    }
    for i in cast[usize](0)..<3 {
        ml_kem_sample_cbd(sigma[0..<32], cast[u8](3 + i), &e.polys[i])
        ml_kem_ntt(&e.polys[i])
    }
    // t̂ = Â ŝ + ê, public; ŝ encoded is the secret key's start
    encoded : SecretByte[1152]
    for i in cast[usize](0)..<3 {
        t := e.polys[i]
        for j in cast[usize](0)..<3 {
            ml_kem_multiply_add(&t, &a.rows[(3 * i + j) % 9], &s.polys[j])
        }
        ml_kem_encode(&t, 12, ml_kem_output_part(encoded[0..<1152], 384 * i, 384))
        ml_kem_encode(&s.polys[i], 12, encoded_secret_part(secret, i))
    }
    for i in cast[usize](0)..<1152 {
        public[i] = compiler.declassify(cast[u8](encoded[i]))
    }
    for i in cast[usize](0)..<32 {
        public[1152 + i] = rho[i]
    }
    // The secret key: ŝ, the public key, H(public key), z
    for i in cast[usize](0)..<1184 {
        secret[1152 + i] = public[i]
    }
    hash :: sha3_256(public[0..<1184])
    for i in cast[usize](0)..<32 {
        secret[2336 + i] = hash[i]
        secret[2368 + i] = cast[u8](z[i])
    }
}

/** The secret key's bytes for ŝ's ith polynomial, as SecretBytes. */
encoded_secret_part #constant_time :: fn(secret: ptr[mut MlKem768SecretKey], i: usize) -> mut SecretByte[] {
    whole :: bit_cast[mut SecretByte[]](secret[0..<ML_KEM_768_SECRET_KEY_BYTES])
    return ml_kem_output_part(whole, 384 * (i % 3), 384)
}

/**
 * Check a public key is one ML-KEM makes (FIPS 203, 7.2's modulus check): each 12-bit coefficient below q.
 *
 * @param public The public key.
 * @return True if it is.
 */
ml_kem_768_check_public_key :: fn(public: ptr[MlKem768PublicKey]) -> bool {
    for i in cast[usize](0)..<3 {
        f : MlKemPoly
        ml_kem_decode(as_secret(ml_kem_part(public[0..<1184], 384 * i, 384)), 12, &f)
        for c in cast[usize](0)..<256 {
            if compiler.declassify(f[c] >= ML_KEM_Q) {
                return false
            }
        }
    }
    return true
}

/**
 * Encapsulate a shared secret to a public key (ML-KEM.Encaps_internal, with 7.2's check).
 *
 * @param public The other side's public key.
 * @param m 32 random bytes.
 * @param ciphertext Where the ciphertext goes, to send.
 * @param shared Where the 32-byte shared secret goes.
 * @return True; false, nothing written, if the public key fails the modulus check.
 */
ml_kem_768_encapsulate #constant_time :: fn(public: ptr[MlKem768PublicKey], m: ptr[SecretByte[32]], ciphertext: ptr[mut MlKem768Ciphertext],
    shared: ptr[mut SecretByte[32]]) -> bool {

    if !ml_kem_768_check_public_key(public) {
        return false
    }
    // (K, r) = G(m ‖ H(ek))
    hash :: sha3_256(public[0..<1184])
    r : SecretByte[32]
    ml_kem_g(m[0..<32], as_secret(hash[0..<32]), shared, &r)
    sealed : SecretByte[1088]
    ml_kem_encrypt(public, m, &r, sealed[0..<1088])
    for i in cast[usize](0)..<1088 {
        ciphertext[i] = compiler.declassify(cast[u8](sealed[i]))
    }
    return true
}

/**
 * Decapsulate the shared secret from a ciphertext (ML-KEM.Decaps_internal, with 7.3's hash check): a ciphertext
 * that isn't what encrypting the message decrypted from it gives back gets J(z ‖ c) instead, chosen without
 * branching.
 *
 * @param secret This side's secret key.
 * @param ciphertext The ciphertext received.
 * @param shared Where the 32-byte shared secret goes.
 * @return True; false, nothing written, if the secret key's hash of its public key doesn't match, so it's damaged.
 */
ml_kem_768_decapsulate #constant_time :: fn(secret: ptr[MlKem768SecretKey], ciphertext: ptr[MlKem768Ciphertext],
    shared: ptr[mut SecretByte[32]]) -> bool {

    whole :: bit_cast[SecretByte[]](secret[0..<ML_KEM_768_SECRET_KEY_BYTES])
    public : MlKem768PublicKey
    for byte, i in ml_kem_secret_part(whole, 1152, 1184) {
        if i < public.count {
            public[i] = compiler.declassify(cast[u8](byte))
        }
    }
    hash :: sha3_256(public[0..<1184])
    matches := compiler.secret(cast[u8](0))
    for byte, i in ml_kem_secret_part(whole, 2336, 32) {
        if i < hash.count {
            matches = matches | (hash[i] ~ cast[u8](byte))
        }
    }
    if compiler.declassify(matches != 0) {
        return false
    }
    message : SecretByte[32]
    ml_kem_decrypt(ml_kem_secret_part(whole, 0, 1152), ciphertext, &message)
    // (K', r') = G(m' ‖ h)
    key : SecretByte[32]
    r : SecretByte[32]
    ml_kem_g(message[0..<32], ml_kem_secret_part(whole, 2336, 32), &key, &r)
    again : SecretByte[1088]
    ml_kem_encrypt(&public, &message, &r, again[0..<1088])
    // K̄ = J(z ‖ c)
    sponge := shake256_start()
    keccak_absorb(&sponge, ml_kem_secret_part(whole, 2368, 32))
    keccak_absorb(&sponge, as_secret(ciphertext[0..<1088]))
    rejected : SecretByte[32]
    keccak_squeeze(&sponge, rejected[0..<32])
    differs := compiler.secret(cast[u8](0))
    for i in cast[usize](0)..<1088 {
        differs = differs | (cast[u8](again[i]) ~ ciphertext[i])
    }
    // All ones if they differ, else zeros
    mask :: cast[u8](0) - cast[u8]((cast[SecretWord](differs) + 255) >> 8)
    for i in cast[usize](0)..<32 {
        shared[i] = cast[SecretByte]((cast[u8](rejected[i]) & mask) | (cast[u8](key[i]) & ~mask))
    }
    return true
}
