/*
 * std/crypto's ML-KEM-768 (FIPS 203) against NIST's ACVP vectors and Project Wycheproof's (vectors.hsc, made by
 * make_vectors.py): key pairs from their seeds, encapsulations from their messages, decapsulations, implicit
 * rejection of changed ciphertexts among them, and the checks of public and secret keys. Run with hemera --test.
 */
package ml_kem_test

import compiler from "base"
import crypto from "std"
import testing from "std"

/** Room for the longest value, a secret key's 2400 bytes. */
Bytes :: struct {
    bytes : u8[2400],
    count : usize,
}

/** A hex digit's value. */
nibble :: fn(c: char) -> u8 {
    value :: cast[u8](c)
    return if value >= 0x61 { value - 0x61 + 10 } else { value - 0x30 }
}

/** Hex's bytes. */
hex :: fn(text: string) -> Bytes {
    out := Bytes.{}
    for c, i in text {
        at :: i / 2
        if at < out.bytes.count {
            out.bytes[at] = out.bytes[at] * 16 + nibble(c)
        }
    }
    out.count = text.count / 2
    return out
}

/** Whether bytes are what hex says. */
same :: fn(bytes: u8[], text: string) -> bool {
    expected :: hex(text)
    if bytes.count != expected.count {
        return false
    }
    for byte, i in bytes {
        if i < expected.bytes.count && byte != expected.bytes[i] {
            return false
        }
    }
    return true
}

/** Secret bytes made public, to compare. */
plain #constant_time :: fn(secret: crypto.SecretByte[]) -> u8[32] {
    out : u8[32]
    for byte, i in secret {
        if i < 32 {
            out[i] = compiler.declassify(cast[u8](byte))
        }
    }
    return out
}

/** 32 secret bytes from hex. */
seed #constant_time :: fn(text: string, from: usize) -> crypto.SecretByte[32] {
    bytes :: hex(text)
    out : crypto.SecretByte[32]
    for i in cast[usize](0)..<32 {
        if from + i < bytes.bytes.count {
            out[i] = cast[crypto.SecretByte](bytes.bytes[from + i])
        }
    }
    return out
}

/** A public key from hex. */
public_of :: fn(text: string) -> crypto.MlKem768PublicKey {
    bytes :: hex(text)
    key : crypto.MlKem768PublicKey
    for i in 0..<crypto.ML_KEM_768_PUBLIC_KEY_BYTES {
        key[i] = bytes.bytes[i]
    }
    return key
}

/** A secret key from hex. */
secret_of #constant_time :: fn(text: string) -> crypto.MlKem768SecretKey {
    bytes :: hex(text)
    key : crypto.MlKem768SecretKey
    for i in 0..<crypto.ML_KEM_768_SECRET_KEY_BYTES {
        key[i] = bytes.bytes[i]
    }
    return key
}

/** A ciphertext from hex. */
ciphertext_of :: fn(text: string) -> crypto.MlKem768Ciphertext {
    bytes :: hex(text)
    c : crypto.MlKem768Ciphertext
    for i in 0..<crypto.ML_KEM_768_CIPHERTEXT_BYTES {
        c[i] = bytes.bytes[i]
    }
    return c
}

/** A secret key's bytes, made public, to compare. */
secret_bytes #constant_time :: fn(key: ptr[crypto.MlKem768SecretKey]) -> Bytes {
    out := Bytes.{count = crypto.ML_KEM_768_SECRET_KEY_BYTES}
    for i in 0..<crypto.ML_KEM_768_SECRET_KEY_BYTES {
        out.bytes[i] = compiler.declassify(key[i])
    }
    return out
}

makes_key_pairs #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    for each, i in KEY_PAIRS {
        d := seed(each.d, 0)
        z := seed(each.z, 0)
        public : crypto.MlKem768PublicKey
        secret : crypto.MlKem768SecretKey
        crypto.ml_kem_768_key_pair(&d, &z, &public, &secret)
        made :: secret_bytes(&secret)
        if !same(public[0..<crypto.ML_KEM_768_PUBLIC_KEY_BYTES], each.ek) || !same(made.bytes[0..<made.count % (made.bytes.count + 1)], each.dk) {
            testing.note(t, "case %", i)
            testing.fail(t, "ACVP key pair differs")
        }
    }
    return .Ok
}

encapsulates #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    for each, i in ENCAPSULATIONS {
        public := public_of(each.ek)
        m := seed(each.m, 0)
        c : crypto.MlKem768Ciphertext
        shared : crypto.SecretByte[32]
        testing.expect(t, crypto.ml_kem_768_encapsulate(&public, &m, &c, &shared), "encapsulates")
        key :: plain(shared[0..<32])
        if !same(c[0..<crypto.ML_KEM_768_CIPHERTEXT_BYTES], each.c) || !same(key[0..<32], each.k) {
            testing.note(t, "case %", i)
            testing.fail(t, "ACVP encapsulation differs")
        }
    }
    return .Ok
}

/** Decapsulates, the changed ciphertexts among them to J(z ‖ c), implicit rejection's secret. */
decapsulates #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    for each, i in DECAPSULATIONS {
        secret := secret_of(each.dk)
        c := ciphertext_of(each.c)
        shared : crypto.SecretByte[32]
        testing.expect(t, crypto.ml_kem_768_decapsulate(&secret, &c, &shared), "decapsulates")
        key :: plain(shared[0..<32])
        if !same(key[0..<32], each.k) {
            testing.note(t, "case %", i)
            testing.fail(t, "ACVP decapsulation differs")
        }
    }
    return .Ok
}

/** Public keys with a coefficient of q or more are refused; so are secret keys whose hash of their public key's wrong. */
checks_keys #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    for each, i in PUBLIC_KEY_CHECKS {
        public := public_of(each.key)
        if crypto.ml_kem_768_check_public_key(&public) != each.passes {
            testing.note(t, "case %", i)
            testing.fail(t, "ACVP public key check differs")
        }
    }
    for each, i in SECRET_KEY_CHECKS {
        secret := secret_of(each.key)
        c : crypto.MlKem768Ciphertext
        shared : crypto.SecretByte[32]
        if crypto.ml_kem_768_decapsulate(&secret, &c, &shared) != each.passes {
            testing.note(t, "case %", i)
            testing.fail(t, "ACVP secret key check differs")
        }
    }
    return .Ok
}

/** Wycheproof's: a key pair from the seed, the public key as expected, and the ciphertext decapsulated to K. */
passes_wycheproof #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    for each, i in WYCHEPROOF {
        d := seed(each.seed, 0)
        z := seed(each.seed, 32)
        public : crypto.MlKem768PublicKey
        secret : crypto.MlKem768SecretKey
        crypto.ml_kem_768_key_pair(&d, &z, &public, &secret)
        c := ciphertext_of(each.c)
        shared : crypto.SecretByte[32]
        _ = crypto.ml_kem_768_decapsulate(&secret, &c, &shared)
        key :: plain(shared[0..<32])
        if !same(public[0..<crypto.ML_KEM_768_PUBLIC_KEY_BYTES], each.ek) || !same(key[0..<32], each.k) {
            testing.note(t, "case %", i)
            testing.fail(t, "Wycheproof case differs")
        }
    }
    return .Ok
}

/** Both sides agree, for keys and messages made at random. */
agrees #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    d : crypto.SecretByte[32]
    z : crypto.SecretByte[32]
    m : crypto.SecretByte[32]
    for i in 0..<32 {
        d[i] = cast[crypto.SecretByte](cast[u8](testing.draw_below(source, 256)))
        z[i] = cast[crypto.SecretByte](cast[u8](testing.draw_below(source, 256)))
        m[i] = cast[crypto.SecretByte](cast[u8](testing.draw_below(source, 256)))
    }
    public : crypto.MlKem768PublicKey
    secret : crypto.MlKem768SecretKey
    crypto.ml_kem_768_key_pair(&d, &z, &public, &secret)
    c : crypto.MlKem768Ciphertext
    sent : crypto.SecretByte[32]
    testing.expect(t, crypto.ml_kem_768_encapsulate(&public, &m, &c, &sent), "encapsulates")
    got : crypto.SecretByte[32]
    testing.expect(t, crypto.ml_kem_768_decapsulate(&secret, &c, &got), "decapsulates")
    a :: plain(sent[0..<32])
    b :: plain(got[0..<32])
    testing.expect(t, a == b, "the same secret both sides")
    // A changed ciphertext gives another secret
    at :: cast[usize](testing.draw_below(source, crypto.ML_KEM_768_CIPHERTEXT_BYTES))
    if at < crypto.ML_KEM_768_CIPHERTEXT_BYTES {
        c[at] = c[at] ~ 1
    }
    other : crypto.SecretByte[32]
    _ = crypto.ml_kem_768_decapsulate(&secret, &c, &other)
    rejected :: plain(other[0..<32])
    testing.expect(t, rejected != a, "a changed ciphertext's secret isn't the one sent")
    return .Ok
}
