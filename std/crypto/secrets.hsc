package crypto

import compiler from "base"

/** A byte that's a secret, like a key's or a password's (docs/memory.md, Secrets). */
SecretByte :: distinct alias u8 #secret
/** A true or false that's a secret, like whether a secret number is 0, to choose with but not branch on. */
SecretBool :: distinct alias bool #secret
/** A 64-bit word that's a secret, for helpers that work on one, like a bit-plane of bitsliced AES. */
SecretWord :: distinct alias u64 #secret

/**
 * View public bytes, like a message, as secret ones, for what takes secrets.
 *
 * @param data The bytes. Nothing is copied.
 * @return The same bytes as SecretByte, a view of data's memory that's good as long as data is.
 */
as_secret #constant_time :: fn(data: u8[]) -> SecretByte[] {
    return bit_cast[SecretByte[]](data)
}

/**
 * Compare a secret, like a computed tag, with what was given, in constant time.
 *
 * Every byte is looked at whatever is found, so how long it takes says nothing about where they differ; only the
 * counts, which aren't secret, and the answer are revealed.
 *
 * @param secret The secret, like a tag computed from the message.
 * @param given The public bytes to check it against, like the tag that came with the message.
 * @return Whether they're the same bytes: false when their counts differ, true when both are empty.
 */
equal #constant_time :: fn(secret: SecretByte[], given: u8[]) -> bool {
    if secret.count != given.count {
        return false
    }
    difference := compiler.secret(cast[u8](0))
    for i in 0..<secret.count {
        difference = difference | (cast[u8](secret[i]) ~ given[i])
    }
    return compiler.declassify(difference == 0)
}
