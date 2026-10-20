package crypto

import compiler from "base"

// A byte that's a secret, like a key's or a password's (docs/memory.md, Secrets).
SecretByte :: distinct alias u8 #secret
// A true or false that's a secret, like whether a secret number is 0, to choose with but not branch on.
SecretBool :: distinct alias bool #secret

// Public bytes, like a message, seen as secret ones, for what takes secrets.
as_secret #constant_time :: fn(data: u8[]) -> SecretByte[] {
    return bit_cast[SecretByte[]](data)
}

/*
 * Whether a secret, like a computed tag, matches what was given, looking at every byte whatever it
 * finds, so how long it takes says nothing about where they differ. False when their counts differ.
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
