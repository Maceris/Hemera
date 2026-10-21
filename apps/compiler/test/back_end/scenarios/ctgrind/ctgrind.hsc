/*
 * std/crypto's constant-time functions with their secrets marked for Valgrind's Memcheck: built with
 * --valgrind-secrets, compiler.secret tells Memcheck the keys, passwords and messages here are undefined,
 * so under valgrind --error-exitcode it reports any branch or address in the machine code that depends
 * on them, short of compiler.declassify (docs/memory.md, Checking the Machine Code). Outside Valgrind, or
 * without the flag, it just runs. main returns 42 if everything gave an answer.
 */
package ctgrind_test

import compiler from "base"
import runtime from "base"
import crypto from "std"

pattern32 :: fn(seed: u8) -> u8[32] {
    bytes : u8[32]
    for i in 0..<32 {
        bytes[i] = cast[u8](i) * 7 + seed
    }
    return bytes
}

pattern200 :: fn(seed: u8) -> u8[200] {
    bytes : u8[200]
    for i in 0..<200 {
        bytes[i] = cast[u8](i) * 13 + seed
    }
    return bytes
}

// Some of a secret's bytes, declassified once worked out, so the work isn't thrown away
Sink :: struct {
    total: u64,
}

sink #constant_time :: fn(into: ptr[mut Sink], secret: crypto.SecretByte[]) {
    sum := compiler.secret(cast[u64](0))
    for byte in secret {
        sum = sum + cast[u64](byte)
    }
    into.total += compiler.declassify(sum)
}

hashes #constant_time :: fn(into: ptr[mut Sink], key: ptr[crypto.Key256], message: crypto.SecretByte[]) {
    sha256 := crypto.sha256_start()
    crypto.sha256_update_secret(&sha256, message)
    sink(into, crypto.sha256_finish_secret(&sha256))
    sha512 := crypto.sha512_start()
    crypto.sha512_update_secret(&sha512, message)
    sink(into, crypto.sha512_finish_secret(&sha512))
    key_bytes : crypto.SecretByte[32]
    for i in 0..<32 {
        key_bytes[i] = cast[crypto.SecretByte](key[i])
    }
    sink(into, crypto.hmac_sha256(key_bytes, u8.[1, 2, 3]))
    sink(into, crypto.hmac_sha512(key_bytes, u8.[1, 2, 3]))
    expanded : crypto.SecretByte[80]
    _ = crypto.hkdf_sha256_expand(crypto.hkdf_sha256_extract(u8.[9, 9], key_bytes), u8.[4], expanded)
    sink(into, expanded)
    _ = crypto.hkdf_sha512_expand(crypto.hkdf_sha512_extract(u8.[9, 9], key_bytes), u8.[4], expanded)
    sink(into, expanded)
    digest : crypto.SecretByte[64]
    blake2b := crypto.blake2b_start_keyed(64, key_bytes) or_return void
    crypto.blake2b_update_secret(&blake2b, message)
    crypto.blake2b_finish_secret(&blake2b, digest)
    sink(into, digest)
    blake3 := crypto.blake3_start_keyed(key_bytes) or_return void
    crypto.blake3_update_secret(&blake3, message)
    crypto.blake3_finish_secret(&blake3, digest)
    sink(into, digest)
    sink(into, crypto.as_secret(u8.[cast[u8](crypto.equal(digest, u8.[1, 2]))]))
}

encryption #constant_time :: fn(into: ptr[mut Sink], key: ptr[crypto.Key256], message: crypto.SecretByte[200]) {
    nonce := cast[crypto.Nonce96](u8.[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
    ciphertext : u8[200]
    tag : crypto.Tag128
    opened : crypto.SecretByte[200]
    _ = crypto.chacha20_poly1305_seal(key, &nonce, message, u8.[7], ciphertext, &tag)
    if crypto.chacha20_poly1305_open(key, &nonce, ciphertext, u8.[7], &tag, opened) {
        sink(into, opened)
    }
    for hardware in bool.[false, true] {
        if !hardware || crypto.aes_hardware() {
            _ = crypto.aes256_gcm_seal_with(key, &nonce, message, u8.[7], ciphertext, &tag, hardware)
            if crypto.aes256_gcm_open_with(key, &nonce, ciphertext, u8.[7], &tag, opened, hardware) {
                sink(into, opened)
            }
        }
    }
    // A forged tag, refused without its comparison leaking where it differed
    tag[3] = tag[3] ~ 1
    if !crypto.chacha20_poly1305_open(key, &nonce, ciphertext, u8.[7], &tag, opened) {
        into.total += 1
    }
}

curves #constant_time :: fn(into: ptr[mut Sink], x_key: ptr[crypto.X25519SecretKey], ed_key: ptr[crypto.Ed25519SecretKey]) {
    public := crypto.x25519_public_key(x_key)
    shared : crypto.SecretByte[32]
    if crypto.x25519(x_key, &public, &shared) {
        sink(into, shared)
    }
    signature := crypto.ed25519_sign(ed_key, u8.[1, 2, 3])
    into.total += cast[u64](signature[0])
    ed_public := crypto.ed25519_public_key(ed_key)
    if crypto.ed25519_verify(&ed_public, u8.[1, 2, 3], &signature) {
        into.total += 1
    }
}

passwords #constant_time :: fn(into: ptr[mut Sink], password: crypto.SecretByte[]) {
    parameters := crypto.Argon2Parameters.{memory_kib = 64, passes = 2, lanes = 2}
    blocks, error := runtime.new_array(crypto.Argon2Block, crypto.argon2_blocks_needed(parameters))
    if error != null {
        return void
    }
    hash : crypto.SecretByte[32]
    if crypto.argon2id(password, u8.[1, 2, 3, 4, 5, 6, 7, 8], parameters, blocks, hash) {
        sink(into, hash)
    }
}

main :: fn() -> int {
    into := Sink.{}
    key := compiler.secret(cast[crypto.Key256](pattern32(1)))
    message := compiler.secret(bit_cast[crypto.SecretByte[200]](pattern200(5)))
    hashes(&into, &key, message)
    encryption(&into, &key, message)
    x_key := compiler.secret(cast[crypto.X25519SecretKey](pattern32(3)))
    ed_key := compiler.secret(cast[crypto.Ed25519SecretKey](pattern32(4)))
    curves(&into, &x_key, &ed_key)
    passwords(&into, message[0..<20])
    if into.total == 0 {
        return 1
    }
    return 42
}
