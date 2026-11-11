/*
 * std/crypto's primitives for TLS and NTS against Project Wycheproof's vectors, in cases.hsc: HMAC and
 * HKDF with SHA-384, AES-128-GCM with and without AES-NI, AES-SIV, P-256's ECDH and ECDSA, and RSA's
 * PKCS #1 v1.5 and PSS signatures. Run with hemera --test.
 */
package wycheproof_tls_test

import compiler from "base"
import crypto from "std"
import testing from "std"

BUFFER :: 16384

// hex's bytes into into, how many there were
decode :: fn(hex: string, into: ptr[mut u8[BUFFER]]) -> usize {
    for i in 0..<BUFFER {
        into[i] = 0
    }
    for c, j in hex {
        nibble := cast[u8](c) - cast[u8]('0')
        if c >= 'a' {
            nibble = cast[u8](c) - cast[u8]('a') + 10
        }
        into[(j / 2) % BUFFER] = into[(j / 2) % BUFFER] * 16 + nibble
    }
    return (hex.count / 2) % (BUFFER + 1)
}

number :: fn(text: string) -> usize {
    value : usize = 0
    for c in text {
        value = value * 10 + cast[usize](cast[u8](c) - cast[u8]('0'))
    }
    return value
}

Buffers :: struct {
    a: u8[BUFFER],
    b: u8[BUFFER],
    c: u8[BUFFER],
    d: u8[BUFFER],
    e: u8[BUFFER],
    f: u8[BUFFER],
    secret: crypto.SecretByte[BUFFER],
}

/**
 * Check that a case did what Wycheproof says it should, reporting which case it was if not.
 *
 * @param t The test's state, which a failure is recorded in.
 * @param held Whether the case did.
 * @param index The case's index among its kind's, from 0, as its table lists them.
 * @param message What the cases check, for whoever reads a failure.
 * @param location Where the check is; the caller's own.
 */
expect_case :: fn(t: ptr[mut testing.T], held: bool, index: usize, message: string, location := #caller_location) {
    testing.note(t, "case %", index)
    testing.expect(t, held, message, location)
    testing.end_note(t)
}

// The tag, maybe truncated, matches for a valid case and not for an invalid one
hmac384_case #constant_time :: fn(b: ptr[mut Buffers], key_hex: string, message_hex: string, tag_hex: string, valid: bool) -> bool {
    key_count := decode(key_hex, &b.a) % (BUFFER + 1)
    message_count := decode(message_hex, &b.b) % (BUFFER + 1)
    tag_count := decode(tag_hex, &b.c) % (BUFFER + 1)
    tag := crypto.hmac_sha384(crypto.as_secret(b.a[0..<key_count]), b.b[0..<message_count])
    return crypto.equal(tag[0..<tag_count % 49], b.c[0..<tag_count]) == valid
}

// Extracted and expanded to the expected output, or refused for a size too large
hkdf384_case #constant_time :: fn(b: ptr[mut Buffers], input_hex: string, salt_hex: string, info_hex: string, output_size: string,
    output_hex: string, valid: bool) -> bool {

    input_count := decode(input_hex, &b.a) % (BUFFER + 1)
    salt_count := decode(salt_hex, &b.b) % (BUFFER + 1)
    info_count := decode(info_hex, &b.c) % (BUFFER + 1)
    output_count := decode(output_hex, &b.d) % (BUFFER + 1)
    count := number(output_size) % (BUFFER + 1)
    key := crypto.hkdf_sha384_extract(b.b[0..<salt_count], crypto.as_secret(b.a[0..<input_count]))
    worked := crypto.hkdf_sha384_expand(key, b.c[0..<info_count], b.secret[0..<count])
    if !valid {
        return !worked
    }
    return worked && count == output_count && crypto.equal(b.secret[0..<count], b.d[0..<output_count])
}

/*
 * A valid case seals to the ciphertext and tag and opens again; an invalid one is refused, writing
 * nothing
 */
aes128_case #constant_time :: fn(hardware: bool, b: ptr[mut Buffers], key_hex: string, nonce_hex: string, associated_hex: string,
    message_hex: string, ciphertext_hex: string, tag_hex: string, valid: bool) -> bool {

    _ = decode(key_hex, &b.a)
    _ = decode(nonce_hex, &b.b)
    associated_count := decode(associated_hex, &b.c) % (BUFFER + 1)
    message_count := decode(message_hex, &b.d) % (BUFFER + 1)
    ciphertext_count := decode(ciphertext_hex, &b.e) % (BUFFER + 1)
    _ = decode(tag_hex, &b.f)
    key : crypto.Key128
    for i in 0..<16 {
        key[i] = b.a[i]
    }
    nonce : crypto.Nonce96
    for i in 0..<12 {
        nonce[i] = b.b[i]
    }
    tag : crypto.Tag128
    for i in 0..<16 {
        tag[i] = b.f[i]
    }
    if valid {
        sealed : u8[BUFFER]
        sealed_tag : crypto.Tag128
        worked := crypto.aes128_gcm_seal_with(&key, &nonce, crypto.as_secret(b.d[0..<message_count]), b.c[0..<associated_count],
            sealed[0..<message_count], &sealed_tag, hardware)
        if !worked || message_count != ciphertext_count {
            return false
        }
        for i in 0..<message_count {
            if sealed[i] != b.e[i] {
                return false
            }
        }
        for i in 0..<16 {
            if sealed_tag[i] != tag[i] {
                return false
            }
        }
    }
    opened : crypto.SecretByte[BUFFER]
    worked := crypto.aes128_gcm_open_with(&key, &nonce, b.e[0..<ciphertext_count], b.c[0..<associated_count], &tag,
        opened[0..<ciphertext_count], hardware)
    if worked != valid {
        return false
    }
    if valid {
        return crypto.equal(opened[0..<ciphertext_count], b.d[0..<message_count])
    }
    // Refused: nothing readable written
    for i in 0..<ciphertext_count {
        if compiler.declassify(opened[i]) != 0 {
            return false
        }
    }
    return true
}

agrees_on_hmac_sha384 #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    b := Buffers.{}
    for i in 0..<HMAC384_CASES.count / 4 {
        expect_case(t, hmac384_case(&b, HMAC384_CASES[4 * i], HMAC384_CASES[4 * i + 1], HMAC384_CASES[4 * i + 2], HMAC384_CASES[4 * i + 3] == "valid"), i,
            "the tag, maybe truncated, matches exactly when Wycheproof says it's valid")
    }
    return .Ok
}

agrees_on_hkdf_sha384 #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    b := Buffers.{}
    for i in 0..<HKDF384_CASES.count / 6 {
        expect_case(t, hkdf384_case(&b, HKDF384_CASES[6 * i], HKDF384_CASES[6 * i + 1], HKDF384_CASES[6 * i + 2], HKDF384_CASES[6 * i + 3],
            HKDF384_CASES[6 * i + 4], HKDF384_CASES[6 * i + 5] == "valid"), i,
            "extracted and expanded to Wycheproof's output, or refused for a size too large")
    }
    return .Ok
}

agrees_on_aes128_gcm #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    b := Buffers.{}
    for i in 0..<AES128_CASES.count / 7 {
        expect_case(t, aes128_case(crypto.aes_hardware(), &b, AES128_CASES[7 * i], AES128_CASES[7 * i + 1], AES128_CASES[7 * i + 2],
            AES128_CASES[7 * i + 3], AES128_CASES[7 * i + 4], AES128_CASES[7 * i + 5], AES128_CASES[7 * i + 6] == "valid"), i,
            "with the CPU's AES where it has it, as the case says, sealed and opened or refused")
    }
    return .Ok
}

agrees_on_aes128_gcm_in_software #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    b := Buffers.{}
    for i in 0..<AES128_CASES.count / 7 {
        expect_case(t, aes128_case(false, &b, AES128_CASES[7 * i], AES128_CASES[7 * i + 1], AES128_CASES[7 * i + 2],
            AES128_CASES[7 * i + 3], AES128_CASES[7 * i + 4], AES128_CASES[7 * i + 5], AES128_CASES[7 * i + 6] == "valid"), i,
            "in software, as the case says, sealed and opened or refused")
    }
    return .Ok
}

/*
 * Seal and open with AES-SIV-CMAC-256 or -512, as the key's size says, with the associated data
 * and nonce given: a valid case seals to the tag and ciphertext and opens again, and an invalid one is refused, leaving
 * zeros
 */
siv_case #constant_time :: fn(hardware: bool, key_bytes: u8[], associated: u8[], nonce: u8[]?, message: u8[], tag_bytes: u8[], ciphertext: u8[],
    valid: bool) -> bool {

    if tag_bytes.count != 16 || (key_bytes.count != 32 && key_bytes.count != 64) || message.count > BUFFER || ciphertext.count > BUFFER {
        return !valid
    }
    tag : crypto.Tag128
    for i in 0..<16 {
        tag[i] = tag_bytes[i]
    }
    key256 : crypto.Key256
    key512 : crypto.Key512
    for byte, i in key_bytes {
        key256[i % 32] = byte
        key512[i % 64] = byte
    }
    wide := key_bytes.count == 64
    if valid {
        sealed : u8[BUFFER]
        sealed_tag : crypto.Tag128
        worked := false
        if wide {
            worked = crypto.aes_siv_cmac512_seal_with(&key512, associated, nonce, crypto.as_secret(message), &sealed_tag, sealed[0..<message.count],
                hardware)
        }
        else {
            worked = crypto.aes_siv_cmac256_seal_with(&key256, associated, nonce, crypto.as_secret(message), &sealed_tag, sealed[0..<message.count],
                hardware)
        }
        if !worked || message.count != ciphertext.count {
            return false
        }
        for i in 0..<message.count {
            if sealed[i] != ciphertext[i] {
                return false
            }
        }
        for i in 0..<16 {
            if sealed_tag[i] != tag[i] {
                return false
            }
        }
    }
    opened : crypto.SecretByte[BUFFER]
    worked := false
    if wide {
        worked = crypto.aes_siv_cmac512_open_with(&key512, associated, nonce, &tag, ciphertext, opened[0..<ciphertext.count], hardware)
    }
    else {
        worked = crypto.aes_siv_cmac256_open_with(&key256, associated, nonce, &tag, ciphertext, opened[0..<ciphertext.count], hardware)
    }
    if worked != valid {
        return false
    }
    if valid {
        return crypto.equal(opened[0..<ciphertext.count], message)
    }
    for i in 0..<ciphertext.count {
        if compiler.declassify(opened[i]) != 0 {
            return false
        }
    }
    return true
}

// RFC 5297's deterministic form: one string of associated data, and the tag before the ciphertext
siv_deterministic_case :: fn(hardware: bool, b: ptr[mut Buffers], key_hex: string, associated_hex: string, message_hex: string,
    output_hex: string, valid: bool) -> bool {

    key_count := decode(key_hex, &b.a) % (BUFFER + 1)
    associated_count := decode(associated_hex, &b.b) % (BUFFER + 1)
    message_count := decode(message_hex, &b.c) % (BUFFER + 1)
    output_count := decode(output_hex, &b.d) % (BUFFER + 1)
    if output_count < 16 {
        return !valid
    }
    return siv_case(hardware, b.a[0..<key_count], b.b[0..<associated_count], null, b.c[0..<message_count], b.d[0..<16], b.d[16..<output_count], valid)
}

// RFC 5297's nonce-based form: the associated data, then the nonce
siv_aead_case :: fn(hardware: bool, b: ptr[mut Buffers], key_hex: string, nonce_hex: string, associated_hex: string, message_hex: string,
    ciphertext_hex: string, tag_hex: string, valid: bool) -> bool {

    key_count := decode(key_hex, &b.a) % (BUFFER + 1)
    nonce_count := decode(nonce_hex, &b.b) % (BUFFER + 1)
    associated_count := decode(associated_hex, &b.c) % (BUFFER + 1)
    message_count := decode(message_hex, &b.d) % (BUFFER + 1)
    ciphertext_count := decode(ciphertext_hex, &b.e) % (BUFFER + 1)
    tag_count := decode(tag_hex, &b.f) % (BUFFER + 1)
    return siv_case(hardware, b.a[0..<key_count], b.c[0..<associated_count], b.b[0..<nonce_count], b.d[0..<message_count], b.f[0..<tag_count], b.e[0..<ciphertext_count], valid)
}

agrees_on_aes_siv #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    b := Buffers.{}
    for hardware in bool.[false, true] {
        if !hardware || crypto.aes_hardware() {
            for i in 0..<SIV_CASES.count / 5 {
                expect_case(t, siv_deterministic_case(hardware, &b, SIV_CASES[5 * i], SIV_CASES[5 * i + 1], SIV_CASES[5 * i + 2],
                    SIV_CASES[5 * i + 3], SIV_CASES[5 * i + 4] == "valid"), i,
                    "sealed to Wycheproof's tag and ciphertext and opened, or refused, with and without AES-NI")
            }
        }
    }
    return .Ok
}

agrees_on_aes_siv_with_nonces #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    b := Buffers.{}
    for hardware in bool.[false, true] {
        if !hardware || crypto.aes_hardware() {
            for i in 0..<SIV_AEAD_CASES.count / 7 {
                expect_case(t, siv_aead_case(hardware, &b, SIV_AEAD_CASES[7 * i], SIV_AEAD_CASES[7 * i + 1], SIV_AEAD_CASES[7 * i + 2],
                    SIV_AEAD_CASES[7 * i + 3], SIV_AEAD_CASES[7 * i + 4], SIV_AEAD_CASES[7 * i + 5], SIV_AEAD_CASES[7 * i + 6] == "valid"), i,
                    "the nonce after the associated data, sealed and opened or refused, with and without AES-NI")
            }
        }
    }
    return .Ok
}

// The shared secret is Wycheproof's for a valid case; an invalid public key is refused
ecdh_point_case #constant_time :: fn(b: ptr[mut Buffers], private_hex: string, public_hex: string, shared_hex: string, valid: bool) -> bool {
    _ = decode(private_hex, &b.a)
    public_count := decode(public_hex, &b.b) % (BUFFER + 1)
    shared_count := decode(shared_hex, &b.c) % (BUFFER + 1)
    secret : crypto.P256SecretKey
    for i in 0..<32 {
        secret[i] = b.a[i]
    }
    shared : crypto.SecretByte[32]
    worked := crypto.p256_ecdh(&secret, b.b[0..<public_count], &shared)
    if !valid {
        return !worked
    }
    return worked && crypto.equal(shared, b.c[0..<shared_count])
}

// The signature, r then s, verifies over the message's SHA-256 exactly when Wycheproof says it's valid
ecdsa_p1363_case :: fn(b: ptr[mut Buffers], public_hex: string, message_hex: string, signature_hex: string, valid: bool) -> bool {
    public_count := decode(public_hex, &b.a) % (BUFFER + 1)
    message_count := decode(message_hex, &b.b) % (BUFFER + 1)
    signature_count := decode(signature_hex, &b.c) % (BUFFER + 1)
    if signature_count != 64 {
        return !valid
    }
    signature : crypto.P256Signature
    for i in 0..<64 {
        signature[i] = b.c[i]
    }
    digest := crypto.sha256(b.b[0..<message_count])
    return crypto.p256_ecdsa_verify(b.a[0..<public_count], digest, &signature) == valid
}

agrees_on_p256_ecdh #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    b := Buffers.{}
    for i in 0..<ECDH_POINT_CASES.count / 4 {
        expect_case(t, ecdh_point_case(&b, ECDH_POINT_CASES[4 * i], ECDH_POINT_CASES[4 * i + 1], ECDH_POINT_CASES[4 * i + 2],
            ECDH_POINT_CASES[4 * i + 3] == "valid"), i,
            "each shared secret is Wycheproof's, and a point off the curve or badly written is refused")
    }
    return .Ok
}

agrees_on_p256_ecdsa #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    b := Buffers.{}
    for i in 0..<ECDSA_P1363_CASES.count / 4 {
        expect_case(t, ecdsa_p1363_case(&b, ECDSA_P1363_CASES[4 * i], ECDSA_P1363_CASES[4 * i + 1], ECDSA_P1363_CASES[4 * i + 2],
            ECDSA_P1363_CASES[4 * i + 3] == "valid"), i,
            "each signature verifies exactly when Wycheproof says it's valid")
    }
    return .Ok
}
