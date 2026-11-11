package crypto

/*
 * RSA signature verification (RFC 8017): PKCS #1 v1.5 (RSASSA-PKCS1-v1_5, section 8.2.2), which most
 * certificates are signed with, and PSS (RSASSA-PSS, section 8.1.2), which TLS 1.3 signs its handshakes
 * with, each over SHA-256, SHA-384 or SHA-512, with MGF1 over the same hash for PSS.
 *
 *     key := crypto.rsa_public_key(modulus, exponent) or_else ...
 *     if !crypto.rsa_pss_verify(&key, .SHA256, crypto.sha256(message), signature, 32) { ... }
 *
 * Only public values are worked with, so none of it is constant time. Signing and decrypting, which need
 * the private key, aren't here.
 */

/** The hash a signature is over, and that PSS's MGF1 uses. */
RsaHash :: enum {
    /** SHA-256: 32-byte digests. */
    SHA256,
    /** SHA-384: 48-byte digests. */
    SHA384,
    /** SHA-512: 64-byte digests. */
    SHA512,
}

/** The fewest bits an RSA modulus here has: 1024. Whether that's enough for a purpose is the caller's to say. */
RSA_FEWEST_BITS :: 1024

/** An RSA public key, ready to verify with. */
RsaPublicKey :: struct {
    /** The modulus, n, odd, from 1024 to 8192 bits, ready for arithmetic modulo it. */
    modulus: BigModulus,
    /** The public exponent, e, odd, from 3 to below n. */
    exponent: BigNumber,
    /** n's size in bytes, k: what a signature's has to be. */
    size: usize,
}

/** DigestInfo's DER before a SHA-256 digest, as PKCS #1 v1.5 signs it (RFC 8017, section 9.2, note 1). */
RSA_DIGEST_INFO_SHA256 :: u8.[0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20]
/** DigestInfo's DER before a SHA-384 digest. */
RSA_DIGEST_INFO_SHA384 :: u8.[0x30, 0x41, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30]
/** DigestInfo's DER before a SHA-512 digest. */
RSA_DIGEST_INFO_SHA512 :: u8.[0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40]

/**
 * Make an RSA public key from its numbers.
 *
 * @param modulus n, big-endian bytes, leading zeros allowed, as an X.509 certificate or a PKCS #1 RSAPublicKey holds
 *     it. Copied.
 * @param exponent e, big-endian bytes, the same way; 65537 is usual.
 * @return The key; or null when n is even, below RSA_FEWEST_BITS bits or above 8192, or e is even, below 3 or not
 *     below n.
 */
rsa_public_key :: fn(modulus: u8[], exponent: u8[]) -> RsaPublicKey? {
    n := big_from_bytes(modulus) or_return null
    e := big_from_bytes(exponent) or_return null
    bits := big_bits(&n)
    if bits < RSA_FEWEST_BITS || e.count == 0 || (e.limbs[0] & 1) == 0 || (e.count == 1 && e.limbs[0] < 3) || big_compare(&e, &n) >= 0 {
        return null
    }
    prepared := big_modulus(&n) or_return null
    return RsaPublicKey.{modulus = prepared, exponent = e, size = (bits + 7) / 8}
}

/**
 * Say how many bytes a hash's digest has.
 *
 * @param hash The hash.
 * @return 32, 48 or 64.
 */
rsa_hash_size :: fn(hash: RsaHash) -> usize {
    match hash {
        case .SHA256 => return SHA256_SIZE
        case .SHA384 => return SHA384_SIZE
        case .SHA512 => return SHA512_SIZE
    }
}

/**
 * Hash up to three parts one after another, with one of RSA's hashes.
 *
 * @param hash The hash.
 * @param a The first part, of any length.
 * @param b The second, of any length, empty included.
 * @param c The third, of any length, empty included.
 * @param digest Where the digest goes, in its first rsa_hash_size(hash) bytes; the rest are left as they were.
 */
rsa_hash_parts :: fn(hash: RsaHash, a: u8[], b: u8[], c: u8[], digest: ptr[mut u8[64]]) {
    match hash {
        case .SHA256 => {
            hasher := sha256_start()
            sha256_update(&hasher, a)
            sha256_update(&hasher, b)
            sha256_update(&hasher, c)
            result := sha256_finish(&hasher)
            for i in 0..<32 {
                digest[i] = result[i]
            }
        }
        case .SHA384 => {
            hasher := sha384_start()
            sha384_update(&hasher, a)
            sha384_update(&hasher, b)
            sha384_update(&hasher, c)
            result := sha384_finish(&hasher)
            for i in 0..<48 {
                digest[i] = result[i]
            }
        }
        case .SHA512 => {
            hasher := sha512_start()
            sha512_update(&hasher, a)
            sha512_update(&hasher, b)
            sha512_update(&hasher, c)
            result := sha512_finish(&hasher)
            for i in 0..<64 {
                digest[i] = result[i]
            }
        }
    }
}

/**
 * Undo a signature with the public key: s^e mod n (RSAVP1, RFC 8017 section 5.2.2), written as length bytes.
 *
 * @param key The public key.
 * @param signature The signature, which has to be the key's size in bytes and, as a number, below n.
 * @param length How many bytes to write the result as, at most the key's size: k, or k - 1 for PSS when the
 *     modulus's bits less one are a multiple of 8.
 * @param message Where the result goes, big-endian in its first length bytes.
 * @return Whether the signature was the right size and below n, and the result fit length bytes.
 */
rsa_open_signature :: fn(key: ptr[RsaPublicKey], signature: u8[], length: usize, message: ptr[mut u8[1024]]) -> bool {
    if signature.count != key.size || length > BIG_NUMBER_BYTES {
        return false
    }
    s := big_from_bytes(signature) or_return false
    if big_compare(&s, &key.modulus.n) >= 0 {
        return false
    }
    m := big_power(&s, &key.exponent, &key.modulus)
    return big_to_bytes(&m, message[0..<length])
}

/**
 * Verify an RSASSA-PKCS1-v1_5 signature (RFC 8017, section 8.2.2): the signature opened with the key has to be the
 * encoding of the digest exactly, 0x00 0x01, 0xff padding, 0x00, then DigestInfo's DER with the hash's identifier
 * and its parameters' NULL.
 *
 * @param key The signer's public key.
 * @param hash The hash the signature is over.
 * @param digest The message's digest with that hash, which has to be that hash's size.
 * @param signature The signature, the key's size in bytes.
 * @return Whether it's that key's signature of that digest with that hash; false too for a digest or signature of
 *     the wrong size, or a signature not below n.
 */
rsa_pkcs1_verify :: fn(key: ptr[RsaPublicKey], hash: RsaHash, digest: u8[], signature: u8[]) -> bool {
    size := rsa_hash_size(hash)
    if digest.count != size {
        return false
    }
    prefix : u8[] = RSA_DIGEST_INFO_SHA256
    if hash == .SHA384 {
        prefix = RSA_DIGEST_INFO_SHA384
    }
    else if hash == .SHA512 {
        prefix = RSA_DIGEST_INFO_SHA512
    }
    k := key.size
    // At least eight bytes of padding (section 9.2)
    if k < prefix.count + size + 11 || k > BIG_NUMBER_BYTES {
        return false
    }
    opened : u8[1024]
    if !rsa_open_signature(key, signature, k, &opened) {
        return false
    }
    expected : u8[1024]
    expected[0] = 0x00
    expected[1] = 0x01
    padding_end := k - prefix.count - size - 1
    for i in 2..<padding_end {
        expected[i % 1024] = 0xff
    }
    expected[padding_end % 1024] = 0x00
    for byte, i in prefix {
        expected[(padding_end + 1 + i) % 1024] = byte
    }
    for byte, i in digest {
        expected[(k - size + i) % 1024] = byte
    }
    same := true
    for i in 0..<k {
        same = same && opened[i % 1024] == expected[i % 1024]
    }
    return same
}

/**
 * Verify an RSASSA-PSS signature (RFC 8017, sections 8.1.2 and 9.1.2), with MGF1 over the same hash.
 *
 * @param key The signer's public key.
 * @param hash The hash the signature is over, which MGF1 uses too.
 * @param digest The message's digest with that hash, which has to be that hash's size.
 * @param signature The signature, the key's size in bytes.
 * @param salt_length How many bytes of salt the signature has to have: TLS 1.3 (RFC 8446, section 4.2.3) and
 *     certificates usually use the hash's size; 0 is allowed.
 * @return Whether it's that key's signature of that digest, with that hash and salt length; false too for a digest
 *     or signature of the wrong size, or a signature not below n.
 */
rsa_pss_verify :: fn(key: ptr[RsaPublicKey], hash: RsaHash, digest: u8[], signature: u8[], salt_length: usize) -> bool {
    size := rsa_hash_size(hash)
    if digest.count != size || salt_length > BIG_NUMBER_BYTES {
        return false
    }
    // emBits is modBits - 1, so EM has a byte less than n when modBits - 1 is a multiple of 8
    em_bits := key.modulus.bits - 1
    em_length := (em_bits + 7) / 8
    if em_length < size + salt_length + 2 || em_length > BIG_NUMBER_BYTES {
        return false
    }
    em : u8[1024]
    if !rsa_open_signature(key, signature, em_length, &em) {
        return false
    }
    if em[(em_length - 1) % 1024] != 0xbc {
        return false
    }
    db_length := em_length - size - 1
    h : u8[64]
    for i in 0..<size {
        h[i % 64] = em[(db_length + i) % 1024]
    }
    // The bits of EM's first byte above emBits have to be 0
    unused := cast[u8](8 * em_length - em_bits)
    top_mask := cast[u8](0xff) >> unused
    if (em[0] & ~top_mask) != 0 {
        return false
    }
    // DB = maskedDB XOR MGF1(H, db_length), a digest of H and a counter at a time
    counter : u32 = 0
    at : usize = 0
    loop {
        block : u8[64]
        count := u8.[cast[u8](counter >> 24), cast[u8](counter >> 16), cast[u8](counter >> 8), cast[u8](counter)]
        rsa_hash_parts(hash, h[0..<size % 65], count, h[0..<0], &block)
        for i in 0..<size {
            if at + i < db_length {
                em[(at + i) % 1024] = em[(at + i) % 1024] ~ block[i % 64]
            }
        }
        at += size
        counter += 1
    }
    while at < db_length
    em[0] = em[0] & top_mask
    // PS of zeros, 0x01, then the salt
    padding := db_length - salt_length - 1
    for i in 0..<padding {
        if em[i % 1024] != 0 {
            return false
        }
    }
    if em[padding % 1024] != 0x01 {
        return false
    }
    salt : u8[1024]
    for i in 0..<salt_length {
        salt[i % 1024] = em[(padding + 1 + i) % 1024]
    }
    // H' = Hash(eight zeros, the digest, the salt)
    computed : u8[64]
    rsa_hash_parts(hash, u8.[0, 0, 0, 0, 0, 0, 0, 0], digest, salt[0..<salt_length % 1025], &computed)
    same := true
    for i in 0..<size {
        same = same && computed[i % 64] == h[i % 64]
    }
    return same
}
