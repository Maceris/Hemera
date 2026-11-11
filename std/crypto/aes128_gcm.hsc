package crypto

/*
 * AES-128-GCM (FIPS 197, NIST SP 800-38D): AES-256-GCM's construction (see aes256_gcm.hsc, whose AES and
 * GHASH it uses) with a 16-byte key and 10 rounds. TLS 1.3's one mandatory cipher suite,
 * TLS_AES_128_GCM_SHA256, is built on it.
 *
 *     sealed := crypto.aes128_gcm_seal(&key, &nonce, crypto.as_secret(message), header, ciphertext, &tag)
 *     if !crypto.aes128_gcm_open(&key, &nonce, ciphertext, header, &tag, opened) {
 *         // forged or damaged: nothing was written
 *     }
 */

/** A 16-byte secret key, AES-128's. */
Key128 :: distinct alias u8[16] #secret

/**
 * AES's round constants, Rcon (FIPS 197, section 5.2), as AES-128's key expansion takes them: entry i for word 4 * i,
 * entries 1 to 10 used, and entry 0 not.
 */
AES128_ROUND_CONSTANTS :: u8.[0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36]

/** The most bytes an AES-128-GCM message can have: AES_GCM_MOST, just under 64 GiB. */
AES128_GCM_MOST :: AES_GCM_MOST

/**
 * Expand an AES-128 key into its round keys (FIPS 197, section 5.2), in constant time.
 *
 * @param key The 16-byte key.
 * @return The 11 round keys in the schedule's first 176 bytes, the rest zero; the first is the key itself. Secret.
 */
aes128_expand #constant_time :: fn(key: ptr[Key128]) -> AesSchedule {
    schedule : AesSchedule
    for i in 0..<16 {
        schedule[i] = key[i]
    }
    // Word i + 4 from words i + 3 and i
    for i in 0..<40 {
        word := i + 4
        t0 := cast[SecretByte](schedule[4 * i + 12])
        t1 := cast[SecretByte](schedule[4 * i + 13])
        t2 := cast[SecretByte](schedule[4 * i + 14])
        t3 := cast[SecretByte](schedule[4 * i + 15])
        if word % 4 == 0 {
            rotated := t0
            t0 = aes_sbox(t1)
            t1 = aes_sbox(t2)
            t2 = aes_sbox(t3)
            t3 = aes_sbox(rotated)
            t0 = cast[SecretByte](cast[u8](t0) ~ AES128_ROUND_CONSTANTS[(word / 4) % 11])
        }
        schedule[4 * i + 16] = schedule[4 * i] ~ cast[u8](t0)
        schedule[4 * i + 17] = schedule[4 * i + 1] ~ cast[u8](t1)
        schedule[4 * i + 18] = schedule[4 * i + 2] ~ cast[u8](t2)
        schedule[4 * i + 19] = schedule[4 * i + 3] ~ cast[u8](t3)
    }
    return schedule
}

/**
 * Encrypt and authenticate a message with AES-128-GCM (FIPS 197, NIST SP 800-38D).
 *
 * AES-NI and PCLMULQDQ are used when aes_hardware says the CPU has them; otherwise AES and GHASH are worked out in
 * software, in constant time. A kernel without vector state calls aes128_gcm_seal_with instead.
 *
 * @param key The 16-byte secret key, which whoever opens the message has too; read, not changed. Its expanded copy on
 *     the stack isn't wiped.
 * @param nonce The nonce, which must never have been used with this key before: a repeat gives away the XOR of the
 *     two plaintexts and GHASH's key, which lets tags be forged. A counter, or 12 random bytes, will do.
 * @param plaintext The message, up to AES128_GCM_MOST bytes; empty is allowed.
 * @param associated Data authenticated with the message but not encrypted, like a header sent in the clear, of any
 *     length; empty for none.
 * @param ciphertext Where the encrypted message goes, which has to have plaintext's count. It's public.
 * @param tag Where the tag goes, to be sent with the ciphertext.
 * @return True with ciphertext and tag written, or false, with nothing written, when the counts differ or the message
 *     is longer than AES128_GCM_MOST.
 */
aes128_gcm_seal #constant_time :: fn(key: ptr[Key128], nonce: ptr[Nonce96], plaintext: SecretByte[], associated: u8[],
    ciphertext: mut u8[], tag: ptr[mut Tag128]) -> bool {

    return aes128_gcm_seal_with(key, nonce, plaintext, associated, ciphertext, tag, aes_hardware())
}

/**
 * Check and decrypt a message sealed with AES-128-GCM (FIPS 197, NIST SP 800-38D).
 *
 * The tag is checked first, in constant time, and the plaintext is only written once the ciphertext and the
 * associated data are found to be what was sealed. AES-NI and PCLMULQDQ are used when aes_hardware says the CPU has
 * them.
 *
 * @param key The key it was sealed with.
 * @param nonce The nonce it was sealed with.
 * @param ciphertext The encrypted message as sealing wrote it, up to AES128_GCM_MOST bytes; empty is allowed.
 * @param associated The associated data it was sealed with, which has to be the same bytes.
 * @param tag The tag that came with it.
 * @param plaintext Where the message goes, which has to have ciphertext's count.
 * @return True with plaintext written, or false, with nothing written, when the tag doesn't match (the ciphertext,
 *     the associated data, the nonce, the key or the tag is wrong: forged or damaged), the counts differ, or the
 *     ciphertext is longer than AES128_GCM_MOST.
 */
aes128_gcm_open #constant_time :: fn(key: ptr[Key128], nonce: ptr[Nonce96], ciphertext: u8[], associated: u8[],
    tag: ptr[Tag128], plaintext: mut SecretByte[]) -> bool {

    return aes128_gcm_open_with(key, nonce, ciphertext, associated, tag, plaintext, aes_hardware())
}

/**
 * Encrypt and authenticate a message with AES-128-GCM, choosing whether AES-NI and PCLMULQDQ may be used.
 *
 * @param key The 16-byte secret key; read, not changed. Its expanded copy on the stack isn't wiped.
 * @param nonce The nonce, which must never have been used with this key before.
 * @param plaintext The message, up to AES128_GCM_MOST bytes; empty is allowed.
 * @param associated Data authenticated with the message but not encrypted, of any length; empty for none.
 * @param ciphertext Where the encrypted message goes, which has to have plaintext's count. It's public.
 * @param tag Where the tag goes, to be sent with the ciphertext.
 * @param hardware Whether to use AES-NI and PCLMULQDQ, which only works on a CPU that has them, as aes_hardware says;
 *     a kernel without vector state gives false, unless it saves the vector registers around the call. The result is
 *     the same either way.
 * @return True with ciphertext and tag written, or false, with nothing written, when the counts differ or the message
 *     is longer than AES128_GCM_MOST.
 */
aes128_gcm_seal_with #constant_time :: fn(key: ptr[Key128], nonce: ptr[Nonce96], plaintext: SecretByte[], associated: u8[],
    ciphertext: mut u8[], tag: ptr[mut Tag128], hardware: bool) -> bool {

    if plaintext.count != ciphertext.count || cast[u64](plaintext.count) > AES_GCM_MOST {
        return false
    }
    gcm := aes_gcm_start(aes_key(aes128_expand(key), 10, hardware), hardware)
    return aes_gcm_seal(&gcm, nonce, plaintext, associated, ciphertext, tag)
}

/**
 * Check and decrypt a message sealed with AES-128-GCM, choosing whether AES-NI and PCLMULQDQ may be used.
 *
 * The tag is checked first, in constant time, and the plaintext is only written once it matches.
 *
 * @param key The key it was sealed with.
 * @param nonce The nonce it was sealed with.
 * @param ciphertext The encrypted message as sealing wrote it, up to AES128_GCM_MOST bytes; empty is allowed.
 * @param associated The associated data it was sealed with, which has to be the same bytes.
 * @param tag The tag that came with it.
 * @param plaintext Where the message goes, which has to have ciphertext's count.
 * @param hardware Whether to use AES-NI and PCLMULQDQ, which only works on a CPU that has them; see
 *     aes128_gcm_seal_with.
 * @return True with plaintext written, or false, with nothing written, when the tag doesn't match (forged or
 *     damaged), the counts differ, or the ciphertext is longer than AES128_GCM_MOST.
 */
aes128_gcm_open_with #constant_time :: fn(key: ptr[Key128], nonce: ptr[Nonce96], ciphertext: u8[], associated: u8[],
    tag: ptr[Tag128], plaintext: mut SecretByte[], hardware: bool) -> bool {

    if plaintext.count != ciphertext.count || cast[u64](ciphertext.count) > AES_GCM_MOST {
        return false
    }
    gcm := aes_gcm_start(aes_key(aes128_expand(key), 10, hardware), hardware)
    return aes_gcm_open(&gcm, nonce, ciphertext, associated, tag, plaintext)
}
