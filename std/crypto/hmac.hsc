package crypto

/*
 * HMAC (RFC 2104) and HKDF (RFC 5869), with SHA-256 or SHA-512. The key, and what HKDF derives, are
 * secrets; a tag is one too until it's compared, with crypto.equal:
 *
 *     tag :: crypto.hmac_sha256(key, message)
 *     if crypto.equal(tag, given_tag) { ... }
 *
 *     pseudo_random :: crypto.hkdf_sha256_extract(salt, shared_secret)
 *     _ = crypto.hkdf_sha256_expand(pseudo_random, "session keys", keys)
 */

HmacSha256 :: struct {
    inner: Sha256,
    outer: Sha256,
}

HmacSha512 :: struct {
    inner: Sha512,
    outer: Sha512,
}

// A key padded to a block, hashed first if it's longer, as HMAC uses it.
HmacSha256Block :: distinct alias u8[64] #secret
HmacSha512Block :: distinct alias u8[128] #secret

hmac_sha256_start #constant_time :: fn(key: SecretByte[]) -> HmacSha256 {
    padded : HmacSha256Block
    if key.count > SHA256_BLOCK {
        hashed := sha256_start()
        sha256_update_secret(&hashed, key)
        digest := sha256_finish_secret(&hashed)
        for i in 0..<SHA256_SIZE {
            padded[i] = cast[u8](digest[i])
        }
    }
    else {
        for byte, i in key {
            padded[i % SHA256_BLOCK] = cast[u8](byte)
        }
    }
    hmac := HmacSha256.{inner = sha256_start(), outer = sha256_start()}
    for i in 0..<SHA256_BLOCK {
        hmac.inner.state.block[i] = padded[i] ~ 0x36
        hmac.outer.state.block[i] = padded[i] ~ 0x5c
    }
    sha256_compress(&hmac.inner.state)
    sha256_compress(&hmac.outer.state)
    hmac.inner.total = SHA256_BLOCK
    hmac.outer.total = SHA256_BLOCK
    return hmac
}

hmac_sha256_update :: fn(hmac: ptr[mut HmacSha256], message: u8[]) {
    sha256_update(&hmac.inner, message)
}

hmac_sha256_update_secret #constant_time :: fn(hmac: ptr[mut HmacSha256], message: SecretByte[]) {
    sha256_update_secret(&hmac.inner, message)
}

hmac_sha256_finish #constant_time :: fn(hmac: ptr[mut HmacSha256]) -> SecretByte[32] {
    inner := sha256_finish_secret(&hmac.inner)
    sha256_update_secret(&hmac.outer, inner)
    return sha256_finish_secret(&hmac.outer)
}

hmac_sha256 #constant_time :: fn(key: SecretByte[], message: u8[]) -> SecretByte[32] {
    hmac := hmac_sha256_start(key)
    hmac_sha256_update(&hmac, message)
    return hmac_sha256_finish(&hmac)
}

hmac_sha512_start #constant_time :: fn(key: SecretByte[]) -> HmacSha512 {
    padded : HmacSha512Block
    if key.count > SHA512_BLOCK {
        hashed := sha512_start()
        sha512_update_secret(&hashed, key)
        digest := sha512_finish_secret(&hashed)
        for i in 0..<SHA512_SIZE {
            padded[i] = cast[u8](digest[i])
        }
    }
    else {
        for byte, i in key {
            padded[i % SHA512_BLOCK] = cast[u8](byte)
        }
    }
    hmac := HmacSha512.{inner = sha512_start(), outer = sha512_start()}
    for i in 0..<SHA512_BLOCK {
        hmac.inner.state.block[i] = padded[i] ~ 0x36
        hmac.outer.state.block[i] = padded[i] ~ 0x5c
    }
    sha512_compress(&hmac.inner.state)
    sha512_compress(&hmac.outer.state)
    hmac.inner.total = SHA512_BLOCK
    hmac.outer.total = SHA512_BLOCK
    return hmac
}

hmac_sha512_update :: fn(hmac: ptr[mut HmacSha512], message: u8[]) {
    sha512_update(&hmac.inner, message)
}

hmac_sha512_update_secret #constant_time :: fn(hmac: ptr[mut HmacSha512], message: SecretByte[]) {
    sha512_update_secret(&hmac.inner, message)
}

hmac_sha512_finish #constant_time :: fn(hmac: ptr[mut HmacSha512]) -> SecretByte[64] {
    inner := sha512_finish_secret(&hmac.inner)
    sha512_update_secret(&hmac.outer, inner)
    return sha512_finish_secret(&hmac.outer)
}

hmac_sha512 #constant_time :: fn(key: SecretByte[], message: u8[]) -> SecretByte[64] {
    hmac := hmac_sha512_start(key)
    hmac_sha512_update(&hmac, message)
    return hmac_sha512_finish(&hmac)
}

// HKDF's first step: a pseudorandom key from what was agreed, with a public salt, which may be empty.
hkdf_sha256_extract #constant_time :: fn(salt: u8[], input: SecretByte[]) -> SecretByte[32] {
    hmac := hmac_sha256_start(as_secret(salt))
    hmac_sha256_update_secret(&hmac, input)
    return hmac_sha256_finish(&hmac)
}

/*
 * HKDF's second step: output filled with keys from the pseudorandom key, for what info says they're
 * for. False, with nothing written, for more than 255 hashes' worth.
 */
hkdf_sha256_expand #constant_time :: fn(pseudo_random: SecretByte[], info: u8[], output: mut SecretByte[]) -> bool {
    if output.count > 255 * SHA256_SIZE {
        return false
    }
    previous : SecretByte[32]
    written : usize = 0
    counter : u8 = 1
    loop {
        hmac := hmac_sha256_start(pseudo_random)
        if counter > 1 {
            hmac_sha256_update_secret(&hmac, previous)
        }
        hmac_sha256_update(&hmac, info)
        hmac_sha256_update(&hmac, u8.[counter])
        previous = hmac_sha256_finish(&hmac)
        for byte in previous {
            if written < output.count {
                output[written] = byte
                written += 1
            }
        }
        counter += 1
    }
    while written < output.count
    return true
}

hkdf_sha512_extract #constant_time :: fn(salt: u8[], input: SecretByte[]) -> SecretByte[64] {
    hmac := hmac_sha512_start(as_secret(salt))
    hmac_sha512_update_secret(&hmac, input)
    return hmac_sha512_finish(&hmac)
}

hkdf_sha512_expand #constant_time :: fn(pseudo_random: SecretByte[], info: u8[], output: mut SecretByte[]) -> bool {
    if output.count > 255 * SHA512_SIZE {
        return false
    }
    previous : SecretByte[64]
    written : usize = 0
    counter : u8 = 1
    loop {
        hmac := hmac_sha512_start(pseudo_random)
        if counter > 1 {
            hmac_sha512_update_secret(&hmac, previous)
        }
        hmac_sha512_update(&hmac, info)
        hmac_sha512_update(&hmac, u8.[counter])
        previous = hmac_sha512_finish(&hmac)
        for byte in previous {
            if written < output.count {
                output[written] = byte
                written += 1
            }
        }
        counter += 1
    }
    while written < output.count
    return true
}
