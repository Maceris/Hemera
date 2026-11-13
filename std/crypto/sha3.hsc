package crypto

import compiler from "base"
import intrinsics from "base"

/*
 * SHA-3 and SHAKE (FIPS 202): Keccak-f[1600]'s sponge, as SHA3-256 and SHA3-512, digests of 32 and 64 bytes, and
 * SHAKE128 and SHAKE256, which give as many bytes as asked for. ML-KEM (ml_kem.hsc) is made of them.
 *
 *     digest :: crypto.sha3_256(message)
 *     sponge := crypto.shake128_start()
 *     crypto.keccak_absorb(&sponge, crypto.as_secret(seed))
 *     crypto.keccak_squeeze(&sponge, output)
 *
 * The state is secret, so what's absorbed may be: a key, or a password. A sponge that's absorbed only public bytes
 * gives public ones, which keccak_squeeze_public declassifies, as sha3_256 and the others do.
 */

/** Keccak-f[1600]'s state: 25 lanes of 64 bits, the first at x = 0, y = 0, then x first. Secret, as what's absorbed may be. */
KeccakState :: distinct alias u64[25] #secret

/** Five lanes: θ's column parities, or a row χ works on. Secret, as the state is. */
KeccakRow :: distinct alias u64[5] #secret

/** SHA3-256's rate in bytes: 1600 bits less its capacity, twice the digest's 256 bits (FIPS 202). */
SHA3_256_RATE :: 136
/** SHA3-512's rate. */
SHA3_512_RATE :: 72
/** SHAKE128's rate. */
SHAKE128_RATE :: 168
/** SHAKE256's rate. */
SHAKE256_RATE :: 136
/** The bits SHA-3 appends to its message before the padding, 01, with the padding's first 1: FIPS 202's 0x06. */
SHA3_DOMAIN : u8 : 0x06
/** SHAKE's, 1111 then the padding's 1: 0x1f. */
SHAKE_DOMAIN : u8 : 0x1f

/** Keccak-f[1600]'s round constants, ι's. */
KECCAK_ROUND_CONSTANTS :: u64.[0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
    0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009, 0x000000000000008a,
    0x0000000000000088, 0x0000000080008009, 0x000000008000000a, 0x000000008000808b, 0x800000000000008b,
    0x8000000000008089, 0x8000000000008003, 0x8000000000008002, 0x8000000000000080, 0x000000000000800a,
    0x800000008000000a, 0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008]

/** ρ's rotations, each in the order π visits the lanes. */
KECCAK_ROTATIONS :: u32.[1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44]

/** π's order: each lane after lane 1, where the one before it goes. */
KECCAK_PI :: usize.[10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1]

/**
 * A sponge absorbing or squeezing: its state, its rate, where in the rate it is, the domain bits its padding starts
 * with, and whether it's squeezing.
 */
Keccak :: struct {
    state : KeccakState,
    rate : usize,
    at : usize,
    domain : u8,
    squeezing : bool,
}

/**
 * Permute the state: Keccak-f[1600]'s 24 rounds of θ, ρ, π, χ and ι.
 *
 * @param a The state, permuted in place.
 */
keccak_f1600 #constant_time :: fn(a: ptr[mut KeccakState]) {
    for round in 0..<24 {
        // θ: each column's parity into its neighbours
        c : KeccakRow
        for x in 0..<5 {
            c[x] = a[x] ~ a[x + 5] ~ a[x + 10] ~ a[x + 15] ~ a[x + 20]
        }
        for x in 0..<5 {
            d :: c[(x + 4) % 5] ~ intrinsics.rotate_left(c[(x + 1) % 5], 1)
            for y in 0..<5 {
                a[x + 5 * y] = a[x + 5 * y] ~ d
            }
        }
        // ρ and π: each lane rotated, and moved to where π puts it
        moving : KeccakRow
        moving[0] = a[1]
        for t in 0..<24 {
            lane :: KECCAK_PI[t] % 25
            moving[1] = a[lane]
            a[lane] = intrinsics.rotate_left(moving[0], KECCAK_ROTATIONS[t])
            moving[0] = moving[1]
        }
        // χ: each row
        for y in 0..<5 {
            row : KeccakRow
            for x in 0..<5 {
                row[x] = a[x + 5 * y]
            }
            for x in 0..<5 {
                a[x + 5 * y] = row[x] ~ (~row[(x + 1) % 5] & row[(x + 2) % 5])
            }
        }
        // ι
        a[0] = a[0] ~ KECCAK_ROUND_CONSTANTS[round]
    }
}

/**
 * Start a sponge.
 *
 * @param rate Its rate in bytes, a multiple of 8 below 200: SHA3_256_RATE and the others.
 * @param domain The bits its padding starts with: SHA3_DOMAIN or SHAKE_DOMAIN.
 * @return The sponge, empty, absorbing.
 */
keccak_start :: fn(rate: usize, domain: u8) -> Keccak {
    return Keccak.{rate = rate, domain = domain}
}

/** A sponge for SHA3-256. */
sha3_256_start :: fn() -> Keccak {
    return keccak_start(SHA3_256_RATE, SHA3_DOMAIN)
}

/** A sponge for SHA3-512. */
sha3_512_start :: fn() -> Keccak {
    return keccak_start(SHA3_512_RATE, SHA3_DOMAIN)
}

/** A sponge for SHAKE128. */
shake128_start :: fn() -> Keccak {
    return keccak_start(SHAKE128_RATE, SHAKE_DOMAIN)
}

/** A sponge for SHAKE256. */
shake256_start :: fn() -> Keccak {
    return keccak_start(SHAKE256_RATE, SHAKE_DOMAIN)
}

/**
 * Absorb bytes into a sponge that hasn't started squeezing.
 *
 * @param sponge The sponge; bytes after it's squeezed are ignored.
 * @param data The bytes, secret or not (as_secret makes public ones so).
 */
keccak_absorb #constant_time :: fn(sponge: ptr[mut Keccak], data: SecretByte[]) {
    if sponge.squeezing || sponge.rate == 0 || sponge.rate >= 200 {
        return void
    }
    for byte in data {
        lane :: (sponge.at / 8) % 25
        sponge.state[lane] = sponge.state[lane] ~ (cast[u64](cast[u8](byte)) << (8 * cast[u64](sponge.at % 8)))
        sponge.at += 1
        if sponge.at == sponge.rate {
            keccak_f1600(&sponge.state)
            sponge.at = 0
        }
    }
}

/**
 * Squeeze bytes out of a sponge, padding what it's absorbed the first time.
 *
 * @param sponge The sponge; it absorbs nothing after.
 * @param output Where the bytes go, every byte of it.
 */
keccak_squeeze #constant_time :: fn(sponge: ptr[mut Keccak], output: mut SecretByte[]) {
    if sponge.rate == 0 || sponge.rate >= 200 {
        return void
    }
    if !sponge.squeezing {
        // The domain bits and the padding's first 1 where absorbing ended, its last 1 at the rate's end
        first :: (sponge.at / 8) % 25
        sponge.state[first] = sponge.state[first] ~ (cast[u64](sponge.domain) << (8 * cast[u64](sponge.at % 8)))
        last :: ((sponge.rate - 1) / 8) % 25
        sponge.state[last] = sponge.state[last] ~ (cast[u64](0x80) << (8 * cast[u64]((sponge.rate - 1) % 8)))
        keccak_f1600(&sponge.state)
        sponge.at = 0
        sponge.squeezing = true
    }
    for &byte in output {
        if sponge.at == sponge.rate {
            keccak_f1600(&sponge.state)
            sponge.at = 0
        }
        byte^ = cast[SecretByte](sponge.state[(sponge.at / 8) % 25] >> (8 * cast[u64](sponge.at % 8)))
        sponge.at += 1
    }
}

/**
 * Squeeze bytes out of a sponge that's absorbed only public bytes, as public bytes.
 *
 * @param sponge The sponge, whose bytes are public as everything it absorbed was.
 * @param output Where the bytes go, every byte of it.
 */
keccak_squeeze_public #constant_time :: fn(sponge: ptr[mut Keccak], output: mut u8[]) {
    for &byte in output {
        one : SecretByte[1]
        keccak_squeeze(sponge, one[0..<1])
        byte^ = compiler.declassify(cast[u8](one[0]))
    }
}

/**
 * Hash public bytes with SHA3-256.
 *
 * @param data The bytes.
 * @return The 32-byte digest.
 */
sha3_256 :: fn(data: u8[]) -> u8[32] {
    sponge := sha3_256_start()
    keccak_absorb(&sponge, as_secret(data))
    digest : u8[32]
    keccak_squeeze_public(&sponge, digest[0..<32])
    return digest
}

/**
 * Hash public bytes with SHA3-512.
 *
 * @param data The bytes.
 * @return The 64-byte digest.
 */
sha3_512 :: fn(data: u8[]) -> u8[64] {
    sponge := sha3_512_start()
    keccak_absorb(&sponge, as_secret(data))
    digest : u8[64]
    keccak_squeeze_public(&sponge, digest[0..<64])
    return digest
}

/**
 * Make SHAKE128's output from public bytes.
 *
 * @param data The bytes.
 * @param output Where the output goes, as many bytes as it has.
 */
shake128 :: fn(data: u8[], output: mut u8[]) {
    sponge := shake128_start()
    keccak_absorb(&sponge, as_secret(data))
    keccak_squeeze_public(&sponge, output)
}

/**
 * Make SHAKE256's output from public bytes.
 *
 * @param data The bytes.
 * @param output Where the output goes, as many bytes as it has.
 */
shake256 :: fn(data: u8[], output: mut u8[]) {
    sponge := shake256_start()
    keccak_absorb(&sponge, as_secret(data))
    keccak_squeeze_public(&sponge, output)
}
