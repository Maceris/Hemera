package crypto

import compiler from "base"

/*
 * AES-SIV with CMAC (RFC 5297): authenticated encryption that holds up when a nonce repeats. The tag is
 * worked out first, from the associated data and the plaintext (S2V, a chain of CMACs), and it's the
 * counter that encrypts, so a repeated nonce, or none, gives away only whether two messages were the same.
 * NTS (RFC 8915) seals its cookies and extension fields with AEAD_AES_SIV_CMAC_256, RFC 5297's
 * nonce-based form, whose S2V takes the associated data, then the nonce, then the plaintext:
 *
 *     siv : crypto.Tag128
 *     _ = crypto.aes_siv_cmac256_seal(&key, header, nonce, crypto.as_secret(fields), &siv, ciphertext)
 *     if !crypto.aes_siv_cmac256_open(&key, header, nonce, &siv, ciphertext, opened) {
 *         // forged or damaged: opened is all zeros
 *     }
 *
 * Without a nonce (null) it's RFC 5297's deterministic form, whose S2V takes the associated data and the
 * plaintext: the same message sealed twice gives the same output. RFC 5297's S2V takes any number of
 * strings of associated data; the one or two here are what its two forms and NTS use.
 *
 * The key is two AES keys of one size, the first for CMAC and the second for the counter: AES-128's for
 * AES-SIV-CMAC-256, AES-256's for AES-SIV-CMAC-512. RFC 5297's AES-SIV-CMAC-384, with AES-192, isn't here.
 */

/** A 64-byte secret key, AES-SIV-CMAC-512's: two AES-256 keys. */
Key512 :: distinct alias u8[64] #secret

/** AES-SIV's keys, ready to use: CMAC's AES key and its two subkeys, and the counter's AES key. Secret throughout. */
AesSiv :: struct {
    /** The first half of the key, which CMAC and so S2V use. */
    mac: AesKey,
    /** The second half, which encrypts the counter. */
    counter: AesKey,
    /** CMAC's first subkey, K1: zeros encrypted, then doubled; added to a last block that's whole. */
    first: AesBlock,
    /** CMAC's second subkey, K2: K1 doubled; added to a last block that's padded. */
    second: AesBlock,
}

/** A CMAC (RFC 4493) in progress. The bytes it holds are secret; how many isn't. */
AesCmac :: struct {
    /** The running value: every block taken so far, chained through AES. */
    value: AesBlock,
    /** The bytes not yet taken, up to a whole block, which is held back until it's known not to be the last. */
    buffer: AesBlock,
    /** How many of the buffer's bytes are filled, 0 to 16. */
    buffered: usize,
}

/**
 * Double a block in GF(2^128), as CMAC and S2V do (RFC 5297's dbl): shifted left one bit, and x^7 + x^2 + x + 1
 * added, as 0x87, when the bit shifted out was 1, without a branch.
 *
 * @param block Any block, read as a 128-bit big-endian number.
 * @return The block doubled.
 */
aes_siv_double #constant_time :: fn(block: AesBlock) -> AesBlock {
    doubled : AesBlock
    for i in 0..<15 {
        doubled[i] = (block[i] << 1) | (block[i + 1] >> 7)
    }
    carry := block[0] >> 7
    doubled[15] = (block[15] << 1) ~ (0x87 & (cast[u8](0) - carry))
    return doubled
}

/**
 * Add one block to another: XOR, byte by byte.
 *
 * @param into The block added to, changed in place.
 * @param other The block added.
 */
aes_siv_add #constant_time :: fn(into: ptr[mut AesBlock], other: ptr[AesBlock]) {
    for i in 0..<16 {
        into[i] = into[i] ~ other[i]
    }
}

/**
 * Add bytes to a CMAC.
 *
 * @param mac The AES key CMAC uses.
 * @param cmac The CMAC, not yet finished: each block but the last is taken as a later byte comes after it.
 * @param data The bytes, of any number, none included; what they are is secret, how many isn't.
 */
aes_cmac_update #constant_time :: fn(mac: ptr[AesKey], cmac: ptr[mut AesCmac], data: SecretByte[]) {
    for byte in data {
        if cmac.buffered == 16 {
            aes_siv_add(&cmac.value, &cmac.buffer)
            aes_encrypt_block(mac, &cmac.value)
            cmac.buffered = 0
        }
        cmac.buffer[cmac.buffered % 16] = cast[u8](byte)
        cmac.buffered += 1
    }
}

/**
 * Finish a CMAC: the last block, whole and with K1 added, or padded with 0x80 then zeros and with K2 added, as an
 * empty message's one block is.
 *
 * @param siv The keys, whose CMAC key and subkeys are used.
 * @param cmac The CMAC, spent afterwards.
 * @return The 16-byte tag, secret.
 */
aes_cmac_finish #constant_time :: fn(siv: ptr[AesSiv], cmac: ptr[mut AesCmac]) -> AesBlock {
    last := cmac.buffer
    if cmac.buffered == 16 {
        aes_siv_add(&last, &siv.first)
    }
    else {
        last[cmac.buffered % 16] = 0x80
        for i in cmac.buffered + 1..<16 {
            last[i] = 0
        }
        aes_siv_add(&last, &siv.second)
    }
    aes_siv_add(&cmac.value, &last)
    aes_encrypt_block(&siv.mac, &cmac.value)
    return cmac.value
}

/**
 * Compute bytes' CMAC (RFC 4493), all at once.
 *
 * @param siv The keys, whose CMAC key and subkeys are used.
 * @param data The bytes, of any number, none included.
 * @return The 16-byte tag, secret.
 */
aes_cmac #constant_time :: fn(siv: ptr[AesSiv], data: SecretByte[]) -> AesBlock {
    cmac := AesCmac.{}
    aes_cmac_update(&siv.mac, &cmac, data)
    return aes_cmac_finish(siv, &cmac)
}

/**
 * Make AES-SIV's keys from its two AES keys: CMAC's subkeys are worked out from the first.
 *
 * @param mac The first half's AES key, for CMAC, from aes_key.
 * @param counter The second half's AES key, for the counter, from aes_key.
 * @return The keys, secret throughout; nothing wipes them when they're done with.
 */
aes_siv_start #constant_time :: fn(mac: AesKey, counter: AesKey) -> AesSiv {
    siv := AesSiv.{mac = mac, counter = counter}
    zero : AesBlock
    aes_encrypt_block(&siv.mac, &zero)
    siv.first = aes_siv_double(zero)
    siv.second = aes_siv_double(siv.first)
    return siv
}

/**
 * Work out the synthetic IV, S2V (RFC 5297, section 2.4): each string of associated data's CMAC chained with
 * doublings, then the plaintext's, with the chain added into its last 16 bytes, or, when it's shorter, doubled once
 * more and added to it padded.
 *
 * @param siv The keys.
 * @param associated The associated data, the first string S2V takes, of any length; empty counts as a string.
 * @param nonce The nonce, the second string, of any length, or null for none, which isn't the same as empty.
 * @param plaintext The plaintext, of any length.
 * @return The synthetic IV, V: the tag, secret until it's compared or sent.
 */
aes_siv_s2v #constant_time :: fn(siv: ptr[AesSiv], associated: u8[], nonce: u8[]?, plaintext: SecretByte[]) -> AesBlock {
    zero : AesBlock
    d := aes_cmac(siv, bit_cast[SecretByte[16]](zero))
    d = aes_siv_double(d)
    associated_tag := aes_cmac(siv, as_secret(associated))
    aes_siv_add(&d, &associated_tag)
    match nonce {
        case Some(given) => {
            d = aes_siv_double(d)
            nonce_tag := aes_cmac(siv, as_secret(given))
            aes_siv_add(&d, &nonce_tag)
        }
        case None => {}
    }
    if plaintext.count >= 16 {
        cmac := AesCmac.{}
        split := plaintext.count - 16
        aes_cmac_update(&siv.mac, &cmac, plaintext[0..<split])
        end : AesBlock
        for i in cast[usize](0)..<16 {
            end[i] = cast[u8](plaintext[split + i]) ~ d[i]
        }
        aes_cmac_update(&siv.mac, &cmac, bit_cast[SecretByte[16]](end))
        return aes_cmac_finish(siv, &cmac)
    }
    t := aes_siv_double(d)
    for byte, i in plaintext {
        t[i % 16] = t[i % 16] ~ cast[u8](byte)
    }
    t[plaintext.count % 16] = t[plaintext.count % 16] ~ 0x80
    return aes_cmac(siv, bit_cast[SecretByte[16]](t))
}

/**
 * Start AES-SIV's counter from the synthetic IV: bits 63 and 31 cleared (RFC 5297, section 2.5), so an
 * implementation that counts in 32 or 64 bits gives the same blocks.
 *
 * @param iv The synthetic IV.
 * @return The counter, a 128-bit big-endian number in two halves, secret.
 */
aes_siv_counter_of #constant_time :: fn(iv: ptr[AesBlock]) -> Ghash {
    counter := Ghash.{high = 0, low = 0}
    for i in 0..<8 {
        counter.high = (counter.high << 8) | cast[u64](iv[i])
        counter.low = (counter.low << 8) | cast[u64](iv[8 + i])
    }
    counter.low = counter.low & 0x7fff_ffff_7fff_ffff
    return counter
}

/**
 * Make four blocks of AES-SIV's keystream: the counter's next four values, encrypted.
 *
 * @param siv The keys, whose counter key is used.
 * @param counter The counter, moved on by four, wrapping past 2^128 - 1.
 * @param stream Where the 64 bytes of keystream go.
 */
aes_siv_keystream #constant_time :: fn(siv: ptr[AesSiv], counter: ptr[mut Ghash], stream: ptr[mut AesBlocks4]) {
    for b in 0..<4 {
        for j in 0..<8 {
            shift := 56 - 8 * cast[u64](j)
            stream[16 * b + j] = cast[u8](counter.high >> shift)
            stream[16 * b + 8 + j] = cast[u8](counter.low >> shift)
        }
        next := counter.low + 1
        // A carry out of the low half when its top bit goes from 1 to 0
        counter.high = counter.high + ((counter.low & ~next) >> 63)
        counter.low = next
    }
    aes_encrypt4(&siv.counter, stream)
}

/**
 * Seal with AES-SIV's keys: S2V's tag, then the plaintext encrypted with it as the counter.
 *
 * @param siv The keys.
 * @param associated The associated data, of any length.
 * @param nonce The nonce, of any length, or null for none.
 * @param plaintext The message, of any length.
 * @param tag Where the synthetic IV goes.
 * @param ciphertext Where the encrypted message goes, which has to have plaintext's count.
 * @return True with tag and ciphertext written, or false, with nothing written, when the counts differ.
 */
aes_siv_seal #constant_time :: fn(siv: ptr[AesSiv], associated: u8[], nonce: u8[]?, plaintext: SecretByte[], tag: ptr[mut Tag128],
    ciphertext: mut u8[]) -> bool {

    if plaintext.count != ciphertext.count {
        return false
    }
    v := aes_siv_s2v(siv, associated, nonce, plaintext)
    counter := aes_siv_counter_of(&v)
    stream : AesBlocks4
    at : usize = 0
    loop {
        aes_siv_keystream(siv, &counter, &stream)
        for i in cast[usize](0)..<64 {
            if at + i < plaintext.count && at + i < ciphertext.count {
                ciphertext[at + i] = compiler.declassify(cast[u8](plaintext[at + i]) ~ stream[i])
            }
        }
        at += 64
    }
    while at < plaintext.count
    for i in 0..<16 {
        tag[i] = compiler.declassify(v[i])
    }
    return true
}

/**
 * Open with AES-SIV's keys: the ciphertext decrypted with the tag as the counter, then S2V's tag worked out from
 * what it gave and compared, in constant time, with the one given.
 *
 * @param siv The keys.
 * @param associated The associated data it was sealed with.
 * @param nonce The nonce it was sealed with, or null if none.
 * @param tag The synthetic IV that came with it.
 * @param ciphertext The encrypted message.
 * @param plaintext Where the message goes, which has to have ciphertext's count.
 * @return True with plaintext written; false when the tag doesn't match, with plaintext set to zeros, or when the
 *     counts differ, with nothing written.
 */
aes_siv_open #constant_time :: fn(siv: ptr[AesSiv], associated: u8[], nonce: u8[]?, tag: ptr[Tag128], ciphertext: u8[],
    plaintext: mut SecretByte[]) -> bool {

    if plaintext.count != ciphertext.count {
        return false
    }
    given : AesBlock
    public_tag : u8[16]
    for i in 0..<16 {
        given[i] = tag[i]
        public_tag[i] = tag[i]
    }
    counter := aes_siv_counter_of(&given)
    stream : AesBlocks4
    at : usize = 0
    loop {
        aes_siv_keystream(siv, &counter, &stream)
        for i in cast[usize](0)..<64 {
            if at + i < ciphertext.count && at + i < plaintext.count {
                plaintext[at + i] = cast[SecretByte](ciphertext[at + i] ~ stream[i])
            }
        }
        at += 64
    }
    while at < ciphertext.count
    v := aes_siv_s2v(siv, associated, nonce, plaintext)
    if !equal(bit_cast[SecretByte[16]](v), public_tag) {
        for i in 0..<plaintext.count {
            plaintext[i] = cast[SecretByte](0)
        }
        return false
    }
    return true
}

/**
 * Make AES-SIV-CMAC-256's keys: two AES-128 keys.
 *
 * @param key The 32-byte key: CMAC's AES-128 key, then the counter's.
 * @param hardware Whether AES-NI is used, which only a CPU that has it, as aes_hardware says, may be told.
 * @return The keys.
 */
aes_siv_cmac256_keys #constant_time :: fn(key: ptr[Key256], hardware: bool) -> AesSiv {
    mac : Key128
    counter : Key128
    for i in 0..<16 {
        mac[i] = key[i]
        counter[i] = key[16 + i]
    }
    return aes_siv_start(aes_key(aes128_expand(&mac), 10, hardware), aes_key(aes128_expand(&counter), 10, hardware))
}

/**
 * Make AES-SIV-CMAC-512's keys: two AES-256 keys.
 *
 * @param key The 64-byte key: CMAC's AES-256 key, then the counter's.
 * @param hardware Whether AES-NI is used, which only a CPU that has it, as aes_hardware says, may be told.
 * @return The keys.
 */
aes_siv_cmac512_keys #constant_time :: fn(key: ptr[Key512], hardware: bool) -> AesSiv {
    mac : Key256
    counter : Key256
    for i in 0..<32 {
        mac[i] = key[i]
        counter[i] = key[32 + i]
    }
    return aes_siv_start(aes_key(aes256_expand(&mac), 14, hardware), aes_key(aes256_expand(&counter), 14, hardware))
}

/**
 * Encrypt and authenticate a message with AES-SIV-CMAC-256 (RFC 5297), AEAD_AES_SIV_CMAC_256 as NTS uses it.
 *
 * AES-NI is used when aes_hardware says the CPU has it; otherwise AES is worked out in software, in constant time.
 *
 * @param key The 32-byte secret key, two AES-128 keys; read, not changed. Its expanded copies on the stack aren't
 *     wiped.
 * @param associated Data authenticated with the message but not encrypted, like a header sent in the clear, of any
 *     length; empty is a string of its own, as RFC 5297 has it.
 * @param nonce The nonce, of any length, empty included (NTS's are 16 bytes), for RFC 5297's nonce-based form; a
 *     repeat gives away only whether two messages were the same. Null for its deterministic form, without one.
 * @param plaintext The message, of any length, empty included.
 * @param tag Where the synthetic IV goes, the 16 bytes RFC 5297 puts before the ciphertext.
 * @param ciphertext Where the encrypted message goes, which has to have plaintext's count. It's public.
 * @return True with tag and ciphertext written, or false, with nothing written, when the counts differ.
 */
aes_siv_cmac256_seal #constant_time :: fn(key: ptr[Key256], associated: u8[], nonce: u8[]?, plaintext: SecretByte[], tag: ptr[mut Tag128],
    ciphertext: mut u8[]) -> bool {

    return aes_siv_cmac256_seal_with(key, associated, nonce, plaintext, tag, ciphertext, aes_hardware())
}

/**
 * Check and decrypt a message sealed with AES-SIV-CMAC-256 (RFC 5297).
 *
 * The message is decrypted into plaintext before it's checked, as S2V needs it, and zeroed again if the tag doesn't
 * match. AES-NI is used when aes_hardware says the CPU has it.
 *
 * @param key The key it was sealed with.
 * @param associated The associated data it was sealed with, the same bytes.
 * @param nonce The nonce it was sealed with, or null if none.
 * @param tag The synthetic IV that came with it.
 * @param ciphertext The encrypted message, of any length.
 * @param plaintext Where the message goes, which has to have ciphertext's count.
 * @return True with plaintext written; false when the tag doesn't match (forged or damaged, or the key or the
 *     associated data is wrong), with plaintext all zeros, or when the counts differ, with nothing written.
 */
aes_siv_cmac256_open #constant_time :: fn(key: ptr[Key256], associated: u8[], nonce: u8[]?, tag: ptr[Tag128], ciphertext: u8[],
    plaintext: mut SecretByte[]) -> bool {

    return aes_siv_cmac256_open_with(key, associated, nonce, tag, ciphertext, plaintext, aes_hardware())
}

/**
 * Encrypt and authenticate a message with AES-SIV-CMAC-256, choosing whether AES-NI may be used.
 *
 * @param key The 32-byte secret key, two AES-128 keys; read, not changed.
 * @param associated The associated data, of any length.
 * @param nonce The nonce, of any length, or null for none.
 * @param plaintext The message, of any length.
 * @param tag Where the synthetic IV goes.
 * @param ciphertext Where the encrypted message goes, which has to have plaintext's count. It's public.
 * @param hardware Whether to use AES-NI, which only works on a CPU that has it, as aes_hardware says. The result is the
 *     same either way.
 * @return True with tag and ciphertext written, or false, with nothing written, when the counts differ.
 */
aes_siv_cmac256_seal_with #constant_time :: fn(key: ptr[Key256], associated: u8[], nonce: u8[]?, plaintext: SecretByte[],
    tag: ptr[mut Tag128], ciphertext: mut u8[], hardware: bool) -> bool {

    siv := aes_siv_cmac256_keys(key, hardware)
    return aes_siv_seal(&siv, associated, nonce, plaintext, tag, ciphertext)
}

/**
 * Check and decrypt a message sealed with AES-SIV-CMAC-256, choosing whether AES-NI may be used.
 *
 * @param key The key it was sealed with.
 * @param associated The associated data it was sealed with.
 * @param nonce The nonce it was sealed with, or null if none.
 * @param tag The synthetic IV that came with it.
 * @param ciphertext The encrypted message.
 * @param plaintext Where the message goes, which has to have ciphertext's count.
 * @param hardware Whether to use AES-NI, which only works on a CPU that has it.
 * @return True with plaintext written; false when the tag doesn't match, with plaintext all zeros, or when the counts
 *     differ, with nothing written.
 */
aes_siv_cmac256_open_with #constant_time :: fn(key: ptr[Key256], associated: u8[], nonce: u8[]?, tag: ptr[Tag128], ciphertext: u8[],
    plaintext: mut SecretByte[], hardware: bool) -> bool {

    siv := aes_siv_cmac256_keys(key, hardware)
    return aes_siv_open(&siv, associated, nonce, tag, ciphertext, plaintext)
}

/**
 * Encrypt and authenticate a message with AES-SIV-CMAC-512 (RFC 5297): AES-SIV-CMAC-256's construction with two
 * AES-256 keys.
 *
 * @param key The 64-byte secret key, two AES-256 keys; read, not changed.
 * @param associated The associated data, of any length.
 * @param nonce The nonce, of any length, or null for none.
 * @param plaintext The message, of any length.
 * @param tag Where the synthetic IV goes.
 * @param ciphertext Where the encrypted message goes, which has to have plaintext's count. It's public.
 * @param hardware Whether to use AES-NI, which only works on a CPU that has it, as aes_hardware says. The result is the
 *     same either way.
 * @return True with tag and ciphertext written, or false, with nothing written, when the counts differ.
 */
aes_siv_cmac512_seal_with #constant_time :: fn(key: ptr[Key512], associated: u8[], nonce: u8[]?, plaintext: SecretByte[],
    tag: ptr[mut Tag128], ciphertext: mut u8[], hardware: bool) -> bool {

    siv := aes_siv_cmac512_keys(key, hardware)
    return aes_siv_seal(&siv, associated, nonce, plaintext, tag, ciphertext)
}

/**
 * Check and decrypt a message sealed with AES-SIV-CMAC-512, choosing whether AES-NI may be used.
 *
 * @param key The key it was sealed with.
 * @param associated The associated data it was sealed with.
 * @param nonce The nonce it was sealed with, or null if none.
 * @param tag The synthetic IV that came with it.
 * @param ciphertext The encrypted message.
 * @param plaintext Where the message goes, which has to have ciphertext's count.
 * @param hardware Whether to use AES-NI, which only works on a CPU that has it.
 * @return True with plaintext written; false when the tag doesn't match, with plaintext all zeros, or when the counts
 *     differ, with nothing written.
 */
aes_siv_cmac512_open_with #constant_time :: fn(key: ptr[Key512], associated: u8[], nonce: u8[]?, tag: ptr[Tag128], ciphertext: u8[],
    plaintext: mut SecretByte[], hardware: bool) -> bool {

    siv := aes_siv_cmac512_keys(key, hardware)
    return aes_siv_open(&siv, associated, nonce, tag, ciphertext, plaintext)
}
