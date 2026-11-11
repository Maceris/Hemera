package crypto

/*
 * HMAC (RFC 2104) and HKDF (RFC 5869), with SHA-256, SHA-384 or SHA-512. The key, and what HKDF derives, are
 * secrets; a tag is one too until it's compared, with crypto.equal:
 *
 *     tag :: crypto.hmac_sha256(key, message)
 *     if crypto.equal(tag, given_tag) { ... }
 *
 *     pseudo_random :: crypto.hkdf_sha256_extract(salt, shared_secret)
 *     _ = crypto.hkdf_sha256_expand(pseudo_random, "session keys", keys)
 */

/**
 * An HMAC-SHA-256 computation in progress, for a message that comes in parts: from hmac_sha256_start, fed with
 * hmac_sha256_update, and ended with hmac_sha256_finish. Its state is secret, as it's derived from the key.
 */
HmacSha256 :: struct {
    /** The inner hash, started with the key XOR ipad (0x36), which the message goes into. */
    inner: Sha256,
    /** The outer hash, started with the key XOR opad (0x5c), which the inner hash's digest goes into. */
    outer: Sha256,
}

/**
 * An HMAC-SHA-512 computation in progress, for a message that comes in parts: from hmac_sha512_start, fed with
 * hmac_sha512_update, and ended with hmac_sha512_finish. Its state is secret, as it's derived from the key.
 */
HmacSha512 :: struct {
    /** The inner hash, started with the key XOR ipad (0x36), which the message goes into. */
    inner: Sha512,
    /** The outer hash, started with the key XOR opad (0x5c), which the inner hash's digest goes into. */
    outer: Sha512,
}

/** A key padded with zeros to SHA-256's 64-byte block, hashed first if it's longer, as HMAC uses it. */
HmacSha256Block :: distinct alias u8[64] #secret
/** A key padded with zeros to SHA-512's 128-byte block, hashed first if it's longer, as HMAC uses it. */
HmacSha512Block :: distinct alias u8[128] #secret

/**
 * Start an HMAC-SHA-256 computation (RFC 2104) with a key.
 *
 * @param key The key, of any length: one longer than SHA-256's 64-byte block is hashed first, and a shorter one padded
 *     with zeros, as RFC 2104 says. RFC 2104 recommends at least 32 bytes. Not kept: only what's derived from it is.
 * @return The computation, ready for the message; its state is secret.
 */
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
    sha256_compress(&hmac.inner.state, hmac.inner.hardware)
    sha256_compress(&hmac.outer.state, hmac.outer.hardware)
    hmac.inner.total = SHA256_BLOCK
    hmac.outer.total = SHA256_BLOCK
    return hmac
}

/**
 * Add public bytes to the message an HMAC-SHA-256 computation authenticates.
 *
 * @param hmac The computation, not yet finished.
 * @param message The next part of the message, of any length, empty included; it's hashed, not kept.
 */
hmac_sha256_update :: fn(hmac: ptr[mut HmacSha256], message: u8[]) {
    sha256_update(&hmac.inner, message)
}

/**
 * Add secret bytes to the message an HMAC-SHA-256 computation authenticates, in constant time.
 *
 * @param hmac The computation, not yet finished.
 * @param message The next part of the message, of any length; its count isn't secret, its bytes are.
 */
hmac_sha256_update_secret #constant_time :: fn(hmac: ptr[mut HmacSha256], message: SecretByte[]) {
    sha256_update_secret(&hmac.inner, message)
}

/**
 * Finish an HMAC-SHA-256 computation.
 *
 * @param hmac The computation. It's spent afterwards: it can't be updated or finished again, and its state isn't
 *     wiped.
 * @return The 32-byte tag, a secret until it's compared with crypto.equal or sent.
 */
hmac_sha256_finish #constant_time :: fn(hmac: ptr[mut HmacSha256]) -> SecretByte[32] {
    inner := sha256_finish_secret(&hmac.inner)
    sha256_update_secret(&hmac.outer, inner)
    return sha256_finish_secret(&hmac.outer)
}

/**
 * Compute a message's HMAC-SHA-256 tag (RFC 2104), when the whole message is at hand.
 *
 * @param key The key, of any length; one longer than 64 bytes is hashed first. RFC 2104 recommends at least 32 bytes.
 * @param message The message, of any length.
 * @return The 32-byte tag, a secret until it's compared with crypto.equal or sent.
 */
hmac_sha256 #constant_time :: fn(key: SecretByte[], message: u8[]) -> SecretByte[32] {
    hmac := hmac_sha256_start(key)
    hmac_sha256_update(&hmac, message)
    return hmac_sha256_finish(&hmac)
}

/**
 * Start an HMAC-SHA-512 computation (RFC 2104) with a key.
 *
 * @param key The key, of any length: one longer than SHA-512's 128-byte block is hashed first, and a shorter one
 *     padded with zeros, as RFC 2104 says. RFC 2104 recommends at least 64 bytes. Not kept: only what's derived from
 *     it is.
 * @return The computation, ready for the message; its state is secret.
 */
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

/**
 * Add public bytes to the message an HMAC-SHA-512 computation authenticates.
 *
 * @param hmac The computation, not yet finished.
 * @param message The next part of the message, of any length, empty included; it's hashed, not kept.
 */
hmac_sha512_update :: fn(hmac: ptr[mut HmacSha512], message: u8[]) {
    sha512_update(&hmac.inner, message)
}

/**
 * Add secret bytes to the message an HMAC-SHA-512 computation authenticates, in constant time.
 *
 * @param hmac The computation, not yet finished.
 * @param message The next part of the message, of any length; its count isn't secret, its bytes are.
 */
hmac_sha512_update_secret #constant_time :: fn(hmac: ptr[mut HmacSha512], message: SecretByte[]) {
    sha512_update_secret(&hmac.inner, message)
}

/**
 * Finish an HMAC-SHA-512 computation.
 *
 * @param hmac The computation. It's spent afterwards: it can't be updated or finished again, and its state isn't
 *     wiped.
 * @return The 64-byte tag, a secret until it's compared with crypto.equal or sent.
 */
hmac_sha512_finish #constant_time :: fn(hmac: ptr[mut HmacSha512]) -> SecretByte[64] {
    inner := sha512_finish_secret(&hmac.inner)
    sha512_update_secret(&hmac.outer, inner)
    return sha512_finish_secret(&hmac.outer)
}

/**
 * Compute a message's HMAC-SHA-512 tag (RFC 2104), when the whole message is at hand.
 *
 * @param key The key, of any length; one longer than 128 bytes is hashed first. RFC 2104 recommends at least 64
 *     bytes.
 * @param message The message, of any length.
 * @return The 64-byte tag, a secret until it's compared with crypto.equal or sent.
 */
hmac_sha512 #constant_time :: fn(key: SecretByte[], message: u8[]) -> SecretByte[64] {
    hmac := hmac_sha512_start(key)
    hmac_sha512_update(&hmac, message)
    return hmac_sha512_finish(&hmac)
}

/**
 * Extract a pseudorandom key from input keying material: HKDF-SHA-256's first step (RFC 5869, section 2.2).
 *
 * @param salt A public, ideally random, value, of any length. Empty is allowed, and is the same as RFC 5869's default
 *     of 32 zero bytes.
 * @param input The input keying material, like a shared secret from a key agreement.
 * @return The 32-byte pseudorandom key, secret, for hkdf_sha256_expand.
 */
hkdf_sha256_extract #constant_time :: fn(salt: u8[], input: SecretByte[]) -> SecretByte[32] {
    hmac := hmac_sha256_start(as_secret(salt))
    hmac_sha256_update_secret(&hmac, input)
    return hmac_sha256_finish(&hmac)
}

/**
 * Expand a pseudorandom key into keys: HKDF-SHA-256's second step (RFC 5869, section 2.3).
 *
 * @param pseudo_random The pseudorandom key, from hkdf_sha256_extract, or another uniformly random key of at least 32
 *     bytes.
 * @param info Public context that says what the keys are for, of any length, empty included; different info gives
 *     unrelated keys from the same pseudorandom key.
 * @param output Where the keys go, filled entirely: up to 255 * 32 = 8160 bytes.
 * @return True once output is filled; false, with nothing written, when output is longer than 8160 bytes.
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

/**
 * Extract a pseudorandom key from input keying material: HKDF-SHA-512's first step (RFC 5869, section 2.2).
 *
 * @param salt A public, ideally random, value, of any length. Empty is allowed, and is the same as RFC 5869's default
 *     of 64 zero bytes.
 * @param input The input keying material, like a shared secret from a key agreement.
 * @return The 64-byte pseudorandom key, secret, for hkdf_sha512_expand.
 */
hkdf_sha512_extract #constant_time :: fn(salt: u8[], input: SecretByte[]) -> SecretByte[64] {
    hmac := hmac_sha512_start(as_secret(salt))
    hmac_sha512_update_secret(&hmac, input)
    return hmac_sha512_finish(&hmac)
}

/**
 * Expand a pseudorandom key into keys: HKDF-SHA-512's second step (RFC 5869, section 2.3).
 *
 * @param pseudo_random The pseudorandom key, from hkdf_sha512_extract, or another uniformly random key of at least 64
 *     bytes.
 * @param info Public context that says what the keys are for, of any length, empty included; different info gives
 *     unrelated keys from the same pseudorandom key.
 * @param output Where the keys go, filled entirely: up to 255 * 64 = 16320 bytes.
 * @return True once output is filled; false, with nothing written, when output is longer than 16320 bytes.
 */
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

/**
 * An HMAC-SHA-384 computation in progress, for a message that comes in parts: from hmac_sha384_start, fed with
 * hmac_sha384_update, and ended with hmac_sha384_finish. Its state is secret, as it's derived from the key.
 */
HmacSha384 :: struct {
    /** The inner hash, started with the key XOR ipad (0x36), which the message goes into. */
    inner: Sha384,
    /** The outer hash, started with the key XOR opad (0x5c), which the inner hash's digest goes into. */
    outer: Sha384,
}

/**
 * Start an HMAC-SHA-384 computation (RFC 2104, RFC 4231) with a key.
 *
 * @param key The key, of any length: one longer than SHA-384's 128-byte block is hashed first, and a shorter one
 *     padded with zeros, as RFC 2104 says. RFC 2104 recommends at least 48 bytes. Not kept: only what's derived from
 *     it is.
 * @return The computation, ready for the message; its state is secret.
 */
hmac_sha384_start #constant_time :: fn(key: SecretByte[]) -> HmacSha384 {
    padded : HmacSha512Block
    if key.count > SHA384_BLOCK {
        hashed := sha384_start()
        sha384_update_secret(&hashed, key)
        digest := sha384_finish_secret(&hashed)
        for i in 0..<SHA384_SIZE {
            padded[i] = cast[u8](digest[i])
        }
    }
    else {
        for byte, i in key {
            padded[i % SHA384_BLOCK] = cast[u8](byte)
        }
    }
    hmac := HmacSha384.{inner = sha384_start(), outer = sha384_start()}
    for i in 0..<SHA384_BLOCK {
        hmac.inner.hasher.state.block[i] = padded[i] ~ 0x36
        hmac.outer.hasher.state.block[i] = padded[i] ~ 0x5c
    }
    sha512_compress(&hmac.inner.hasher.state)
    sha512_compress(&hmac.outer.hasher.state)
    hmac.inner.hasher.total = SHA384_BLOCK
    hmac.outer.hasher.total = SHA384_BLOCK
    return hmac
}

/**
 * Add public bytes to the message an HMAC-SHA-384 computation authenticates.
 *
 * @param hmac The computation, not yet finished.
 * @param message The next part of the message, of any length, empty included; it's hashed, not kept.
 */
hmac_sha384_update :: fn(hmac: ptr[mut HmacSha384], message: u8[]) {
    sha384_update(&hmac.inner, message)
}

/**
 * Add secret bytes to the message an HMAC-SHA-384 computation authenticates, in constant time.
 *
 * @param hmac The computation, not yet finished.
 * @param message The next part of the message, of any length; its count isn't secret, its bytes are.
 */
hmac_sha384_update_secret #constant_time :: fn(hmac: ptr[mut HmacSha384], message: SecretByte[]) {
    sha384_update_secret(&hmac.inner, message)
}

/**
 * Finish an HMAC-SHA-384 computation.
 *
 * @param hmac The computation. It's spent afterwards: it can't be updated or finished again, and its state isn't
 *     wiped.
 * @return The 48-byte tag, a secret until it's compared with crypto.equal or sent.
 */
hmac_sha384_finish #constant_time :: fn(hmac: ptr[mut HmacSha384]) -> SecretByte[48] {
    inner := sha384_finish_secret(&hmac.inner)
    sha384_update_secret(&hmac.outer, inner)
    return sha384_finish_secret(&hmac.outer)
}

/**
 * Compute a message's HMAC-SHA-384 tag (RFC 2104, RFC 4231), when the whole message is at hand.
 *
 * @param key The key, of any length; one longer than 128 bytes is hashed first. RFC 2104 recommends at least 48
 *     bytes.
 * @param message The message, of any length.
 * @return The 48-byte tag, a secret until it's compared with crypto.equal or sent.
 */
hmac_sha384 #constant_time :: fn(key: SecretByte[], message: u8[]) -> SecretByte[48] {
    hmac := hmac_sha384_start(key)
    hmac_sha384_update(&hmac, message)
    return hmac_sha384_finish(&hmac)
}

/**
 * Extract a pseudorandom key from input keying material: HKDF-SHA-384's first step (RFC 5869, section 2.2).
 *
 * @param salt A public, ideally random, value, of any length. Empty is allowed, and is the same as RFC 5869's default
 *     of 48 zero bytes.
 * @param input The input keying material, like a shared secret from a key agreement.
 * @return The 48-byte pseudorandom key, secret, for hkdf_sha384_expand.
 */
hkdf_sha384_extract #constant_time :: fn(salt: u8[], input: SecretByte[]) -> SecretByte[48] {
    hmac := hmac_sha384_start(as_secret(salt))
    hmac_sha384_update_secret(&hmac, input)
    return hmac_sha384_finish(&hmac)
}

/**
 * Expand a pseudorandom key into keys: HKDF-SHA-384's second step (RFC 5869, section 2.3).
 *
 * @param pseudo_random The pseudorandom key, from hkdf_sha384_extract, or another uniformly random key of at least 48
 *     bytes.
 * @param info Public context that says what the keys are for, of any length, empty included; different info gives
 *     unrelated keys from the same pseudorandom key.
 * @param output Where the keys go, filled entirely: up to 255 * 48 = 12240 bytes.
 * @return True once output is filled; false, with nothing written, when output is longer than 12240 bytes.
 */
hkdf_sha384_expand #constant_time :: fn(pseudo_random: SecretByte[], info: u8[], output: mut SecretByte[]) -> bool {
    if output.count > 255 * SHA384_SIZE {
        return false
    }
    previous : SecretByte[48]
    written : usize = 0
    counter : u8 = 1
    loop {
        hmac := hmac_sha384_start(pseudo_random)
        if counter > 1 {
            hmac_sha384_update_secret(&hmac, previous)
        }
        hmac_sha384_update(&hmac, info)
        hmac_sha384_update(&hmac, u8.[counter])
        previous = hmac_sha384_finish(&hmac)
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
