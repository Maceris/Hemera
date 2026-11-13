package crypto

import compiler from "base"

/*
 * OpenSSH's chacha20-poly1305@openssh.com (PROTOCOL.chacha20poly1305): SSH's packets sealed with ChaCha20 and
 * Poly1305, not as RFC 8439 does. The 64-byte key is two: the first 32 bytes encrypt the packet and key Poly1305, the
 * last 32 encrypt the packet's 4-byte length alone, so a reader can learn how long a packet is before it has all of it.
 * The nonce is the packet's sequence number, 8 bytes big-endian (in RFC 8439's terms, 4 zero bytes then those). Block
 * 0 of the main key's stream is Poly1305's key, the packet's bytes start at block 1, and the tag is Poly1305 of the
 * encrypted length and packet together, with no padding or lengths after.
 *
 *     _ = crypto.ssh_chacha_seal(&keys, sequence, packet, sealed, &tag)
 *     length :: crypto.ssh_chacha_length(&keys, sequence, first_four)
 *     if !crypto.ssh_chacha_open(&keys, sequence, sealed, &tag, packet) { ... }
 */

/** chacha20-poly1305@openssh.com's two keys, from the 64 bytes SSH's key exchange derives. */
SshChachaKeys :: struct {
    /** The first 32: the packet's, and Poly1305's. */
    main : Key256,
    /** The last 32: the length's. */
    header : Key256,
}

/**
 * Make the two keys from the 64 bytes.
 *
 * @param key The 64 bytes.
 * @return The keys.
 */
ssh_chacha_keys #constant_time :: fn(key: ptr[SecretByte[64]]) -> SshChachaKeys {
    keys : SshChachaKeys
    for i in cast[usize](0)..<32 {
        keys.main[i] = cast[u8](key[i])
        keys.header[i] = cast[u8](key[32 + i])
    }
    return keys
}

/** The nonce for a sequence number: 4 zero bytes, then it as 8 bytes big-endian. */
ssh_chacha_nonce :: fn(sequence: u32) -> Nonce96 {
    nonce : Nonce96
    for i in cast[usize](0)..<4 {
        nonce[8 + i] = cast[u8](sequence >> (8 * cast[u32](3 - i)))
    }
    return nonce
}

/**
 * Decrypt a packet's length from its first 4 bytes, before the rest has come.
 *
 * @param keys The keys.
 * @param sequence The packet's sequence number.
 * @param encrypted The packet's first 4 bytes, as they came.
 * @return The length, big-endian as SSH sends it: public, as framing needs it, though only the tag says it's genuine.
 */
ssh_chacha_length #constant_time :: fn(keys: ptr[SshChachaKeys], sequence: u32, encrypted: u8[]) -> u32 {
    nonce := ssh_chacha_nonce(sequence)
    block := chacha20_block(&keys.header, 0, &nonce)
    length := cast[u32](0)
    for i in cast[usize](0)..<4 {
        byte :: if i < encrypted.count { encrypted[i] } else { cast[u8](0) }
        length = (length << 8) | cast[u32](compiler.declassify(byte ~ cast[u8](chacha_byte(&block, i))))
    }
    return length
}

/**
 * Seal a packet: its length and the rest encrypted, and the tag.
 *
 * @param keys The keys.
 * @param sequence The packet's sequence number, which must never be used twice with these keys.
 * @param packet The packet, from its 4-byte length on: SSH's binary packet, padded.
 * @param sealed Where the encrypted packet goes, as many bytes as packet.
 * @param tag Where the tag goes.
 * @return True; false, nothing written, if the counts differ or packet has no length.
 */
ssh_chacha_seal #constant_time :: fn(keys: ptr[SshChachaKeys], sequence: u32, packet: SecretByte[], sealed: mut u8[],
    tag: ptr[mut Tag128]) -> bool {

    if packet.count != sealed.count || packet.count < 4 || cast[u64](packet.count) > CHACHA20_POLY1305_MOST {
        return false
    }
    nonce := ssh_chacha_nonce(sequence)
    header := chacha20_block(&keys.header, 0, &nonce)
    for i in cast[usize](0)..<4 {
        sealed[i] = compiler.declassify(cast[u8](packet[i]) ~ cast[u8](chacha_byte(&header, i)))
    }
    ssh_chacha_stream(keys, &nonce, packet[4..<packet.count], sealed[4..<sealed.count])
    computed :: ssh_chacha_tag(keys, &nonce, sealed)
    for i in 0..<16 {
        tag[i] = compiler.declassify(cast[u8](computed[i]))
    }
    return true
}

/**
 * Open a sealed packet: its tag checked first, in constant time, then the packet after its length decrypted.
 *
 * @param keys The keys.
 * @param sequence The packet's sequence number.
 * @param sealed The packet as it came, from its encrypted length on.
 * @param tag The tag that came after it.
 * @param packet Where the packet after its length goes, 4 bytes fewer than sealed.
 * @return True with packet written; false, nothing written, if the tag doesn't match or the counts are wrong.
 */
ssh_chacha_open #constant_time :: fn(keys: ptr[SshChachaKeys], sequence: u32, sealed: u8[], tag: ptr[Tag128],
    packet: mut SecretByte[]) -> bool {

    if sealed.count < 4 || packet.count != sealed.count - 4 || cast[u64](sealed.count) > CHACHA20_POLY1305_MOST {
        return false
    }
    nonce := ssh_chacha_nonce(sequence)
    computed :: ssh_chacha_tag(keys, &nonce, sealed)
    if !equal(computed[0..<16], tag[0..<16]) {
        return false
    }
    decrypted : SecretByte[CHACHA_STREAM]
    at : usize = 0
    body :: sealed[4..<sealed.count]
    loop {
        state := chacha_state(&keys.main, cast[u32](at / 64 + 1), &nonce)
        stream : ChaChaStream
        chacha20_keystream(&state, vectors_wide(), &stream)
        for i in cast[usize](0)..<CHACHA_STREAM {
            if at + i < body.count && at + i < packet.count {
                packet[at + i] = cast[SecretByte](body[at + i] ~ cast[u8](stream[i]))
            }
        }
        at += CHACHA_STREAM
    }
    while at < body.count
    return true
}

/** Encrypt the packet after its length with the main key's stream from block 1, into public bytes. */
ssh_chacha_stream #constant_time :: fn(keys: ptr[SshChachaKeys], nonce: ptr[Nonce96], plaintext: SecretByte[], out: mut u8[]) {
    at : usize = 0
    loop {
        state := chacha_state(&keys.main, cast[u32](at / 64 + 1), nonce)
        stream : ChaChaStream
        chacha20_keystream(&state, vectors_wide(), &stream)
        for i in cast[usize](0)..<CHACHA_STREAM {
            if at + i < plaintext.count && at + i < out.count {
                out[at + i] = compiler.declassify(cast[u8](plaintext[at + i]) ~ cast[u8](stream[i]))
            }
        }
        at += CHACHA_STREAM
    }
    while at < plaintext.count
}

/** Poly1305 of the sealed packet, keyed by block 0 of the main key's stream. */
ssh_chacha_tag #constant_time :: fn(keys: ptr[SshChachaKeys], nonce: ptr[Nonce96], sealed: u8[]) -> SecretByte[16] {
    block := chacha20_block(&keys.main, 0, nonce)
    one_time : Poly1305Key
    for i in cast[usize](0)..<32 {
        one_time[i] = cast[u8](chacha_byte(&block, i))
    }
    poly := poly1305_start(&one_time)
    poly1305_update(&poly, sealed)
    return poly1305_finish(&poly)
}
