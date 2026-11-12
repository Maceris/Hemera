package tls

import compiler from "base"
import crypto from "std"

/*
 * The key schedule (RFC 8446 §7): the transcript hash, HKDF over the suite's hash, HKDF-Expand-Label and Derive-Secret,
 * and the traffic keys and IVs each secret gives. Secrets are kept as SecretByte, 48 bytes each, of which a SHA-256
 * suite uses the first 32.
 */

/** The longest hash, SHA-384's, in bytes: what a secret or a transcript hash takes room for. */
HASH_MOST :: 48

/** The hash a suite uses for its transcript and HKDF. */
Hash :: enum {
    Sha256,
    Sha384,
}

/**
 * Give a hash's output length.
 *
 * @param hash The hash.
 * @return 32 for SHA-256, 48 for SHA-384.
 */
hash_length :: fn(hash: Hash) -> usize {
    return if hash == .Sha384 { cast[usize](48) } else { cast[usize](32) }
}

/** A secret of the schedule: its first hash_length(hash) bytes. */
Secret :: distinct alias u8[HASH_MOST] #secret

/**
 * The transcript: every handshake message so far, hashed with both hashes, as the suite isn't known when the first is
 * hashed; the suite's is read.
 */
Transcript :: struct {
    sha256 : crypto.Sha256,
    sha384 : crypto.Sha384,
}

/**
 * Start a transcript, empty.
 *
 * @return It.
 */
transcript_start :: fn() -> Transcript {
    return Transcript.{sha256 = crypto.sha256_start(), sha384 = crypto.sha384_start()}
}

/**
 * Add a handshake message to the transcript, its header included.
 *
 * @param transcript The transcript.
 * @param message The message, from its type to its end.
 */
transcript_add :: fn(transcript: ptr[mut Transcript], message: u8[]) {
    crypto.sha256_update(&transcript.sha256, message)
    crypto.sha384_update(&transcript.sha384, message)
}

/**
 * Give the transcript's hash so far, leaving the transcript to go on.
 *
 * @param transcript The transcript, not changed.
 * @param hash Which hash.
 * @param into Where the hash goes: its first hash_length(hash) bytes.
 */
transcript_hash :: fn(transcript: ptr[Transcript], hash: Hash, into: ptr[mut u8[HASH_MOST]]) {
    if hash == .Sha384 {
        copy := transcript.sha384
        digest :: crypto.sha384_finish(&copy)
        for byte, i in digest {
            into[i] = byte
        }
        return void
    }
    copy := transcript.sha256
    digest :: crypto.sha256_finish(&copy)
    for byte, i in digest {
        into[i] = byte
    }
}

/**
 * Hash bytes with a hash on their own, as the empty transcript's hash and HelloRetryRequest's message_hash take.
 *
 * @param hash Which hash.
 * @param bytes What's hashed.
 * @param into Where the hash goes.
 */
hash_of :: fn(hash: Hash, bytes: u8[], into: ptr[mut u8[HASH_MOST]]) {
    if hash == .Sha384 {
        digest :: crypto.sha384(bytes)
        for byte, i in digest {
            into[i] = byte
        }
        return void
    }
    digest :: crypto.sha256(bytes)
    for byte, i in digest {
        into[i] = byte
    }
}

/**
 * HKDF-Extract with a hash.
 *
 * @param hash Which hash.
 * @param salt The salt: a secret, as the schedule's salts are, its first hash_length(hash) bytes; or all zeros.
 * @param input The input keying material, hash_length(hash) bytes or the shared secret's.
 * @return The pseudorandom key.
 */
extract #constant_time :: fn(hash: Hash, salt: ptr[Secret], input: crypto.SecretByte[]) -> Secret {
    out : Secret
    length :: hash_length(hash)
    // HKDF's salt is HMAC's key, which a secret salt is as much as a public one
    salt_bytes : u8[HASH_MOST]
    for i in 0..<HASH_MOST {
        salt_bytes[i] = compiler.declassify(salt[i])
    }
    if hash == .Sha384 {
        prk :: crypto.hkdf_sha384_extract(range(salt_bytes, 0, length), input)
        for i in 0..<48 {
            out[i] = cast[u8](prk[i])
        }
        return out
    }
    prk :: crypto.hkdf_sha256_extract(range(salt_bytes, 0, length), input)
    for i in 0..<32 {
        out[i] = cast[u8](prk[i])
    }
    return out
}

/**
 * HKDF-Expand-Label (RFC 8446 §7.1): HKDF-Expand with info made of the length wanted, "tls13 " and the label, and the
 * context.
 *
 * @param hash Which hash.
 * @param secret The secret expanded, its first hash_length(hash) bytes.
 * @param label The label, without "tls13 ", at most 249 bytes.
 * @param context The context: a transcript hash, or empty.
 * @param output Where the output goes, as many bytes as it has, at most 255 * hash_length(hash).
 */
expand_label #constant_time :: fn(hash: Hash, secret: ptr[Secret], label: string, context: u8[], output: mut crypto.SecretByte[]) {
    info : u8[2 + 1 + 255 + 1 + 255]
    writer := Writer.{}
    prefix :: "tls13 "
    put_u16(info, &writer, cast[u16](output.count))
    put_u8(info, &writer, cast[u8](prefix.count + label.count))
    put_bytes(info, &writer, string_bytes(prefix))
    put_bytes(info, &writer, string_bytes(label))
    put_u8(info, &writer, cast[u8](context.count))
    put_bytes(info, &writer, context)
    at :: writer.at
    length :: hash_length(hash)
    key : crypto.SecretByte[HASH_MOST]
    for i in 0..<HASH_MOST {
        key[i] = cast[crypto.SecretByte](secret[i])
    }
    if hash == .Sha384 {
        _ = crypto.hkdf_sha384_expand(range(key, 0, length), range(info, 0, at), output)
    }
    else {
        _ = crypto.hkdf_sha256_expand(range(key, 0, length), range(info, 0, at), output)
    }
}

/**
 * Derive-Secret (RFC 8446 §7.1): HKDF-Expand-Label of a transcript hash, the hash's length.
 *
 * @param hash Which hash.
 * @param secret The secret.
 * @param label The label, without "tls13 ".
 * @param transcript The transcript hash, its first hash_length(hash) bytes.
 * @return The derived secret.
 */
derive_secret #constant_time :: fn(hash: Hash, secret: ptr[Secret], label: string, transcript: ptr[u8[HASH_MOST]]) -> Secret {
    length :: hash_length(hash)
    out : crypto.SecretByte[HASH_MOST]
    expand_label(hash, secret, label, range(transcript^, 0, length), range_mut(out, 0, length))
    derived : Secret
    for i in 0..<HASH_MOST {
        derived[i] = cast[u8](out[i])
    }
    return derived
}

/**
 * Derive-Secret over the empty transcript, as "derived" takes.
 *
 * @param hash Which hash.
 * @param secret The secret.
 * @param label The label.
 * @return The derived secret.
 */
derive_empty #constant_time :: fn(hash: Hash, secret: ptr[Secret], label: string) -> Secret {
    empty : u8[HASH_MOST]
    hash_of(hash, string_bytes(""), &empty)
    return derive_secret(hash, secret, label, &empty)
}

/** A direction's traffic key and IV, and its records' sequence number. */
TrafficKeys :: struct {
    /** The AEAD key: 16 bytes for AES-128-GCM, 32 for the others. */
    key : Secret,
    /** The IV, which the nonce is made from with the sequence number; public, as a nonce is. */
    iv : u8[12],
    /** The next record's sequence number. */
    sequence : u64,
}

/**
 * Give the traffic key and IV a traffic secret gives (RFC 8446 §7.3).
 *
 * @param hash The suite's hash.
 * @param key_length The suite's key length: 16 or 32.
 * @param secret The traffic secret.
 * @return The keys, their sequence number 0.
 */
traffic_keys #constant_time :: fn(hash: Hash, key_length: usize, secret: ptr[Secret]) -> TrafficKeys {
    keys := TrafficKeys.{}
    key : crypto.SecretByte[32]
    expand_label(hash, secret, "key", string_bytes(""), range_mut(key, 0, key_length))
    for i in 0..<32 {
        keys.key[i] = cast[u8](key[i])
    }
    iv : crypto.SecretByte[12]
    expand_label(hash, secret, "iv", string_bytes(""), iv[0..<12])
    for i in 0..<12 {
        keys.iv[i] = compiler.declassify(cast[u8](iv[i]))
    }
    return keys
}

/**
 * Give the next traffic secret, for a KeyUpdate (RFC 8446 §7.2).
 *
 * @param hash The suite's hash.
 * @param secret The traffic secret now.
 * @return The next one.
 */
next_traffic_secret #constant_time :: fn(hash: Hash, secret: ptr[Secret]) -> Secret {
    length :: hash_length(hash)
    out : crypto.SecretByte[HASH_MOST]
    expand_label(hash, secret, "traffic upd", string_bytes(""), range_mut(out, 0, length))
    next : Secret
    for i in 0..<HASH_MOST {
        next[i] = cast[u8](out[i])
    }
    return next
}

/**
 * Work out a Finished's verify_data (RFC 8446 §4.4.4): HMAC, with the finished key the traffic secret gives, of the
 * transcript hash.
 *
 * @param hash The suite's hash.
 * @param secret The handshake traffic secret of the side that sends it.
 * @param transcript The transcript hash up to the Finished.
 * @return The verify_data, its first hash_length(hash) bytes.
 */
finished_data #constant_time :: fn(hash: Hash, secret: ptr[Secret], transcript: ptr[u8[HASH_MOST]]) -> crypto.SecretByte[HASH_MOST] {
    length :: hash_length(hash)
    key : crypto.SecretByte[HASH_MOST]
    expand_label(hash, secret, "finished", string_bytes(""), range_mut(key, 0, length))
    out : crypto.SecretByte[HASH_MOST]
    if hash == .Sha384 {
        mac :: crypto.hmac_sha384(key[0..<48], transcript[0..<48])
        for i in 0..<48 {
            out[i] = mac[i]
        }
    }
    else {
        mac :: crypto.hmac_sha256(key[0..<32], transcript[0..<32])
        for i in 0..<32 {
            out[i] = mac[i]
        }
    }
    return out
}
