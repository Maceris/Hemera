package ssh

import compiler from "base"
import crypto from "std"

/*
 * SSH's keys: public key blobs (RFC 4253, 6.6), as a host key and a user's key are sent, and the signatures they check
 * (ssh-ed25519, RFC 8709; ecdsa-sha2-nistp256, RFC 5656; rsa-sha2-256 and -512 over ssh-rsa keys, RFC 8332); and
 * OpenSSH's text forms: a public key's line, as authorized_keys has them ("ssh-ed25519 AAAA... comment"), its SHA256
 * fingerprint, and an unencrypted openssh-key-v1 private key (OpenSSH's PROTOCOL.key), for Ed25519.
 */

/** The longest public key blob kept: an 8192-bit RSA key's, and a little more. */
KEY_BLOB_BYTES :: 1100
/** An Ed25519 key's blob: string "ssh-ed25519", then string of its 32 bytes. */
ED25519_BLOB_BYTES :: 51
/** An Ed25519 signature's blob: string "ssh-ed25519", then string of its 64 bytes. */
ED25519_SIGNATURE_BYTES :: 83

/** What kind a public key is. */
KeyKind :: enum {
    None,
    Ed25519,
    EcdsaP256,
    Rsa,
}

/** A public key: its kind, and its blob, which says the rest. */
PublicKey :: struct {
    kind : KeyKind,
    blob : u8[KEY_BLOB_BYTES],
    blob_length : usize,
}

/** A public key's blob. */
blob_of :: fn(key: ptr[PublicKey]) -> u8[] {
    return range(key.blob[0..<KEY_BLOB_BYTES], 0, key.blob_length)
}

/** The name a kind of key's blob starts with. */
key_type_name :: fn(kind: KeyKind) -> string {
    return match kind {
        case .Ed25519 => "ssh-ed25519"
        case .EcdsaP256 => "ecdsa-sha2-nistp256"
        case .Rsa => "ssh-rsa"
        case .None => ""
    }
}

/**
 * Read a public key's blob, checking it's one this package takes.
 *
 * @param blob The blob.
 * @return The key; null if it's of another kind, malformed, or too long: an Ed25519 key not 32 bytes, a P-256 point
 *     not on the curve, an RSA key under 2048 bits.
 */
parse_public_key :: fn(blob: u8[]) -> PublicKey? {
    if blob.count > KEY_BLOB_BYTES {
        return null
    }
    reader := reader_of(blob)
    name :: get_string(blob, &reader)
    kind := KeyKind.None
    if is(name, "ssh-ed25519") {
        key :: get_string(blob, &reader)
        if key.count != 32 {
            return null
        }
        kind = .Ed25519
    }
    else if is(name, "ecdsa-sha2-nistp256") {
        curve :: get_string(blob, &reader)
        point :: get_string(blob, &reader)
        // Uncompressed; whether it's on the curve, p256_ecdsa_verify checks with each signature
        if !is(curve, "nistp256") || point.count != 65 || point[0] != 4 {
            return null
        }
        kind = .EcdsaP256
    }
    else if is(name, "ssh-rsa") {
        e :: get_mpint(blob, &reader)
        n :: get_mpint(blob, &reader)
        public :: crypto.rsa_public_key(n, e) or_return null
        if public.size < 256 {
            return null
        }
        kind = .Rsa
    }
    if kind == .None || !done(&reader) {
        return null
    }
    key := PublicKey.{kind = kind, blob_length = blob.count}
    for byte, i in blob {
        if i < key.blob.count {
            key.blob[i] = byte
        }
    }
    return key
}

/**
 * Check a signature, as SSH sends one (string of the algorithm's name, then string of the signature), over data.
 *
 * @param key The public key.
 * @param data What was signed.
 * @param signature The signature's blob.
 * @return True if it's the key's, by an algorithm that goes with the key: ssh-ed25519 for an Ed25519 key,
 *     ecdsa-sha2-nistp256 for a P-256 key, rsa-sha2-256 or rsa-sha2-512 for an RSA key (never SHA-1's ssh-rsa).
 */
verify_signature :: fn(key: ptr[PublicKey], data: u8[], signature: u8[]) -> bool {
    reader := reader_of(signature)
    algorithm :: get_string(signature, &reader)
    value :: get_string(signature, &reader)
    if !done(&reader) {
        return false
    }
    blob :: blob_of(key)
    key_reader := reader_of(blob)
    _ = get_string(blob, &key_reader)
    match key.kind {
        case .Ed25519 => {
            public_bytes :: get_string(blob, &key_reader)
            if !is(algorithm, "ssh-ed25519") || value.count != 64 || public_bytes.count != 32 {
                return false
            }
            public : crypto.Ed25519PublicKey
            for byte, i in public_bytes {
                if i < 32 {
                    public[i] = byte
                }
            }
            sig : crypto.Ed25519Signature
            for byte, i in value {
                if i < 64 {
                    sig[i] = byte
                }
            }
            return crypto.ed25519_verify(&public, data, &sig)
        }
        case .EcdsaP256 => {
            _ = get_string(blob, &key_reader)
            point :: get_string(blob, &key_reader)
            if !is(algorithm, "ecdsa-sha2-nistp256") {
                return false
            }
            inner := reader_of(value)
            r :: get_mpint(value, &inner)
            s :: get_mpint(value, &inner)
            if !done(&inner) || r.count > 32 || s.count > 32 {
                return false
            }
            sig : crypto.P256Signature
            for byte, i in r {
                at :: 32 - r.count + i
                if at < 64 {
                    sig[at] = byte
                }
            }
            for byte, i in s {
                at :: 64 - s.count + i
                if at < 64 {
                    sig[at] = byte
                }
            }
            digest :: crypto.sha256(data)
            return crypto.p256_ecdsa_verify(point, digest[0..<32], &sig)
        }
        case .Rsa => {
            e :: get_mpint(blob, &key_reader)
            n :: get_mpint(blob, &key_reader)
            public :: crypto.rsa_public_key(n, e) or_return false
            sha512 :: is(algorithm, "rsa-sha2-512")
            if !sha512 && !is(algorithm, "rsa-sha2-256") {
                return false
            }
            if value.count > public.size {
                return false
            }
            // A signature with leading zeros dropped is put back to the modulus's length
            padded : u8[1024]
            for byte, i in value {
                at :: public.size - value.count + i
                if at < padded.count {
                    padded[at] = byte
                }
            }
            whole :: range(padded[0..<1024], 0, public.size)
            if sha512 {
                digest :: crypto.sha512(data)
                return crypto.rsa_pkcs1_verify(&public, .SHA512, digest[0..<64], whole)
            }
            digest :: crypto.sha256(data)
            return crypto.rsa_pkcs1_verify(&public, .SHA256, digest[0..<32], whole)
        }
        case .None => return false
    }
}

/**
 * Whether a signature algorithm's name goes with a kind of key, for a public key offered with it.
 *
 * @param kind The key's kind.
 * @param algorithm The algorithm's name.
 * @return True if a signature by that algorithm can be the key's.
 */
algorithm_fits :: fn(kind: KeyKind, algorithm: u8[]) -> bool {
    return match kind {
        case .Ed25519 => is(algorithm, "ssh-ed25519")
        case .EcdsaP256 => is(algorithm, "ecdsa-sha2-nistp256")
        case .Rsa => is(algorithm, "rsa-sha2-256") || is(algorithm, "rsa-sha2-512")
        case .None => false
    }
}

// ---- Ed25519 keys of this side's

/**
 * An Ed25519 key's public blob.
 *
 * @param public The public key.
 * @return The blob, ED25519_BLOB_BYTES.
 */
ed25519_blob :: fn(public: ptr[crypto.Ed25519PublicKey]) -> u8[ED25519_BLOB_BYTES] {
    blob : u8[ED25519_BLOB_BYTES]
    writer := Writer.{}
    put_text(blob[0..<ED25519_BLOB_BYTES], &writer, "ssh-ed25519")
    put_string(blob[0..<ED25519_BLOB_BYTES], &writer, public[0..<32])
    return blob
}

/**
 * Sign with an Ed25519 key, as SSH sends a signature.
 *
 * @param secret The key.
 * @param data What's signed.
 * @return The signature's blob, ED25519_SIGNATURE_BYTES.
 */
ed25519_signature #constant_time :: fn(secret: ptr[crypto.Ed25519SecretKey], data: u8[]) -> u8[ED25519_SIGNATURE_BYTES] {
    signed :: crypto.ed25519_sign(secret, data)
    blob : u8[ED25519_SIGNATURE_BYTES]
    writer := Writer.{}
    put_text(blob[0..<ED25519_SIGNATURE_BYTES], &writer, "ssh-ed25519")
    put_string(blob[0..<ED25519_SIGNATURE_BYTES], &writer, signed[0..<64])
    return blob
}

// ---- Text forms

/**
 * Write a public key's line, as authorized_keys and known_hosts have them: its kind's name, its blob in base64, and a
 * comment if there's one.
 *
 * @param key The key.
 * @param comment The comment, or empty.
 * @param into Where the line goes, without a line break.
 * @return Its length; 0 if it doesn't fit.
 */
key_line :: fn(key: ptr[PublicKey], comment: string, into: mut u8[]) -> usize {
    writer := Writer.{}
    put_bytes(into, &writer, string_bytes(key_type_name(key.kind)))
    put_u8(into, &writer, 0x20)
    encoded : u8[1500]
    count :: crypto.base64_encode(blob_of(key), encoded[0..<1500]) or_return 0
    put_bytes(into, &writer, range(encoded[0..<1500], 0, count))
    if comment.count > 0 {
        put_u8(into, &writer, 0x20)
        put_bytes(into, &writer, string_bytes(comment))
    }
    return if writer.overflow { cast[usize](0) } else { writer.at }
}

/**
 * Read a public key's line: its kind's name, its blob in base64 (whose name has to be the same), and anything after,
 * a comment. A line with options before the kind, as authorized_keys allows, isn't taken.
 *
 * @param line The line, without its line break; spaces or tabs between the parts.
 * @return The key; null if the line isn't one.
 */
parse_key_line :: fn(line: u8[]) -> PublicKey? {
    words : Word[2]
    count := cast[usize](0)
    start := cast[usize](0)
    in_word := false
    for i in cast[usize](0)..<line.count + 1 {
        blank :: i == line.count || (i < line.count && (line[i] == 0x20 || line[i] == 0x09 || line[i] == 0x0d))
        if blank && in_word {
            if count < words.count {
                words[count] = Word.{start = start, end = i}
            }
            count += 1
            in_word = false
        }
        else if !blank && !in_word {
            start = i
            in_word = true
        }
    }
    if count < 2 {
        return null
    }
    name :: range(line, words[0].start, words[0].end)
    encoded :: range(line, words[1].start, words[1].end)
    blob : u8[KEY_BLOB_BYTES]
    length :: crypto.base64_decode(encoded, blob[0..<KEY_BLOB_BYTES]) or_return null
    key :: parse_public_key(range(blob[0..<KEY_BLOB_BYTES], 0, length)) or_return null
    if !is(name, key_type_name(key.kind)) {
        return null
    }
    return key
}

/** Where a word is in a line. */
Word :: struct {
    start : usize,
    end : usize,
}

/**
 * A key's fingerprint, as OpenSSH shows it: "SHA256:", then the SHA-256 of its blob in base64, without padding.
 *
 * @param blob The key's blob.
 * @return The fingerprint's 50 bytes: "SHA256:" and 43 of base64.
 */
fingerprint :: fn(blob: u8[]) -> u8[50] {
    out : u8[50]
    prefix :: string_bytes("SHA256:")
    for byte, i in prefix {
        if i < 50 {
            out[i] = byte
        }
    }
    digest :: crypto.sha256(blob)
    encoded : u8[44]
    _ = crypto.base64_encode(digest[0..<32], encoded[0..<44])
    for i in cast[usize](0)..<43 {
        out[7 + i] = encoded[i]
    }
    return out
}

// ---- OpenSSH's private keys

/** The magic an openssh-key-v1 key starts with, its 0 byte too. */
OPENSSH_KEY_MAGIC :: "openssh-key-v1\0"
/** The text around one. */
OPENSSH_KEY_BEGIN :: "-----BEGIN OPENSSH PRIVATE KEY-----"
OPENSSH_KEY_END :: "-----END OPENSSH PRIVATE KEY-----"
/** The longest private key text written or read. */
PRIVATE_KEY_TEXT_BYTES :: 1024

/**
 * Write an Ed25519 key as OpenSSH's unencrypted private key text, its base64 in lines of 70.
 *
 * @param secret The key's 32-byte seed.
 * @param comment Its comment, like user@host; at most 100 bytes.
 * @param into Where the text goes, PRIVATE_KEY_TEXT_BYTES is room enough.
 * @return Its length; 0 if it doesn't fit or the comment's too long.
 */
private_key_text #constant_time :: fn(secret: ptr[crypto.Ed25519SecretKey], comment: string, into: mut u8[]) -> usize {
    if comment.count > 100 {
        return 0
    }
    public :: crypto.ed25519_public_key(secret)
    blob :: ed25519_blob(&public)
    binary : u8[600]
    writer := Writer.{}
    put_bytes(binary[0..<600], &writer, string_bytes(OPENSSH_KEY_MAGIC))
    put_text(binary[0..<600], &writer, "none")
    put_text(binary[0..<600], &writer, "none")
    put_text(binary[0..<600], &writer, "")
    put_u32(binary[0..<600], &writer, 1)
    put_string(binary[0..<600], &writer, blob[0..<ED25519_BLOB_BYTES])
    section :: start_string(binary[0..<600], &writer)
    section_start :: writer.at
    check : u8[4]
    random_bytes(check[0..<4])
    put_bytes(binary[0..<600], &writer, check[0..<4])
    put_bytes(binary[0..<600], &writer, check[0..<4])
    put_text(binary[0..<600], &writer, "ssh-ed25519")
    put_string(binary[0..<600], &writer, public[0..<32])
    put_u32(binary[0..<600], &writer, 64)
    for i in cast[usize](0)..<32 {
        put_u8(binary[0..<600], &writer, compiler.declassify(secret[i]))
    }
    put_bytes(binary[0..<600], &writer, public[0..<32])
    put_text(binary[0..<600], &writer, comment)
    // Padding 1, 2, 3, ... to a multiple of 8
    pad := cast[u8](1)
    loop {
        put_u8(binary[0..<600], &writer, pad)
        pad += 1
    }
    while (writer.at - section_start) % 8 != 0
    end_string(binary[0..<600], &writer, section)
    if writer.overflow {
        return 0
    }
    encoded : u8[800]
    count :: crypto.base64_encode(range(binary[0..<600], 0, writer.at), encoded[0..<800]) or_return 0
    text := Writer.{}
    put_bytes(into, &text, string_bytes(OPENSSH_KEY_BEGIN))
    put_u8(into, &text, 0x0a)
    for i in cast[usize](0)..<count {
        if i < encoded.count {
            put_u8(into, &text, encoded[i])
        }
        if (i + 1) % 70 == 0 || i + 1 == count {
            put_u8(into, &text, 0x0a)
        }
    }
    put_bytes(into, &text, string_bytes(OPENSSH_KEY_END))
    put_u8(into, &text, 0x0a)
    // The binary held the secret: wiped
    for &byte in binary {
        byte^ = 0
    }
    return if text.overflow { cast[usize](0) } else { text.at }
}

/**
 * Read OpenSSH's private key text for an unencrypted Ed25519 key.
 *
 * @param text The text: BEGIN and END lines around base64, as private_key_text or ssh-keygen writes it.
 * @return The key's seed; null if it isn't one: encrypted, of another kind, damaged, or its public key not its own.
 */
parse_private_key :: fn(text: u8[]) -> crypto.Ed25519SecretKey? {
    // The base64 between the lines, line breaks left out
    begin :: string_bytes(OPENSSH_KEY_BEGIN)
    end :: string_bytes(OPENSSH_KEY_END)
    start := cast[usize](0)
    found := false
    for i in cast[usize](0)..<text.count {
        if !found && same(range(text, i, i + begin.count), begin) {
            start = i + begin.count
            found = true
        }
    }
    if !found {
        return null
    }
    encoded : u8[PRIVATE_KEY_TEXT_BYTES]
    count := cast[usize](0)
    finished := false
    for i in start..<text.count {
        if !finished && same(range(text, i, i + end.count), end) {
            finished = true
        }
        if !finished && i < text.count && text[i] != 0x0a && text[i] != 0x0d && text[i] != 0x20 {
            if count < encoded.count {
                encoded[count] = text[i]
            }
            count += 1
        }
    }
    if !finished || count > encoded.count {
        return null
    }
    binary : u8[800]
    length :: crypto.base64_decode(range(encoded[0..<PRIVATE_KEY_TEXT_BYTES], 0, count), binary[0..<800]) or_return null
    key :: read_private_key(range(binary[0..<800], 0, length))
    for &byte in binary {
        byte^ = 0
    }
    return key
}

/** Read openssh-key-v1's binary for an Ed25519 key. */
read_private_key #constant_time :: fn(binary: u8[]) -> crypto.Ed25519SecretKey? {
    magic :: string_bytes(OPENSSH_KEY_MAGIC)
    if !same(range(binary, 0, magic.count), magic) {
        return null
    }
    reader := Reader.{at = magic.count, end = binary.count}
    cipher :: get_string(binary, &reader)
    kdf :: get_string(binary, &reader)
    _ = get_string(binary, &reader)
    keys :: get_u32(binary, &reader)
    public_blob :: get_string(binary, &reader)
    section := get_inner(binary, &reader)
    if reader.bad || !is(cipher, "none") || !is(kdf, "none") || keys != 1 {
        return null
    }
    first :: get_u32(binary, &section)
    second :: get_u32(binary, &section)
    kind :: get_string(binary, &section)
    public :: get_string(binary, &section)
    both :: get_string(binary, &section)
    if section.bad || first != second || !is(kind, "ssh-ed25519") || public.count != 32 || both.count != 64 {
        return null
    }
    secret : crypto.Ed25519SecretKey
    for i in cast[usize](0)..<32 {
        if i < both.count {
            secret[i] = both[i]
        }
    }
    // Its public key has to be the one its seed makes, and the one the file names
    made :: crypto.ed25519_public_key(&secret)
    blob :: ed25519_blob(&made)
    if !same(made[0..<32], public) || !same(blob[0..<ED25519_BLOB_BYTES], public_blob) {
        return null
    }
    return secret
}
