package ssh

import compiler from "base"
import crypto from "std"

/*
 * The transport (RFC 4253): packets, sealed with the cipher each way has, and key exchange.
 *
 * A packet is its length, its padding's length, its payload and 4 or more bytes of random padding, to a multiple of 8
 * bytes (16 of what's encrypted, for AES-GCM, whose length is sent in the clear and authenticated as associated data).
 * Key exchange: each side's KEXINIT, the first of the client's names the server has for each; then the client's
 * KEX_INIT and the server's KEX_REPLY, which carries its host key and its signature of the exchange hash; then each
 * side's NEWKEYS, after which it sends, or reads, under the new keys.
 */

/** The exchanges this side offers, the client's markers for ext-info and strict key exchange among them. */
KEX_CLIENT :: "mlkem768x25519-sha256,curve25519-sha256,curve25519-sha256@libssh.org,ext-info-c,kex-strict-c-v00@openssh.com"
KEX_SERVER :: "mlkem768x25519-sha256,curve25519-sha256,curve25519-sha256@libssh.org,kex-strict-s-v00@openssh.com"
HOST_KEY_ALGORITHMS :: "ssh-ed25519"
CIPHERS :: "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com"
/** MACs aren't used with these ciphers, which authenticate themselves, but a name in common has to be there. */
MACS :: "hmac-sha2-256-etm@openssh.com,hmac-sha2-256"
COMPRESSION :: "none"
/** What the server says it takes for users' keys (RFC 8308, server-sig-algs). */
SERVER_SIG_ALGS :: "ssh-ed25519,ecdsa-sha2-nistp256,rsa-sha2-512,rsa-sha2-256"

// ---- KEXINIT

/** Send this side's KEXINIT, and keep it for the exchange hash. */
send_kexinit :: fn(conn: ptr[mut Connection]) {
    if conn.kex_sent {
        return void
    }
    into :: conn.our_kexinit[0..<KEXINIT_BYTES]
    writer := Writer.{}
    put_u8(into, &writer, MSG_KEXINIT)
    cookie : u8[16]
    random_bytes(cookie[0..<16])
    put_bytes(into, &writer, cookie[0..<16])
    kex :: if conn.role == .Client { KEX_CLIENT } else if conn.only_kex == .Hybrid { "mlkem768x25519-sha256,kex-strict-s-v00@openssh.com" }
        else if conn.only_kex == .Curve { "curve25519-sha256,kex-strict-s-v00@openssh.com" } else { KEX_SERVER }
    ciphers :: if conn.only_cipher == .Chacha { "chacha20-poly1305@openssh.com" } else if conn.only_cipher == .Gcm { "aes256-gcm@openssh.com" }
        else { CIPHERS }
    put_text(into, &writer, kex)
    put_text(into, &writer, HOST_KEY_ALGORITHMS)
    put_text(into, &writer, ciphers)
    put_text(into, &writer, ciphers)
    put_text(into, &writer, MACS)
    put_text(into, &writer, MACS)
    put_text(into, &writer, COMPRESSION)
    put_text(into, &writer, COMPRESSION)
    put_text(into, &writer, "")
    put_text(into, &writer, "")
    put_bool(into, &writer, false)
    put_u32(into, &writer, 0)
    conn.our_kexinit_length = writer.at
    conn.kex_sent = true
    conn.exchange_sent = false
    conn.newkeys_sent = false
    conn.newkeys_received = false
    send_packet(conn, range(into, 0, writer.at))
}

/** Start exchanging keys again, if they aren't being already. */
rekey :: fn(conn: ptr[mut Connection]) {
    if conn.first_done && !conn.kex_sent && !conn.ended {
        send_kexinit(conn)
    }
}

/** Whether keys are being exchanged now: sent or received a KEXINIT, and not both NEWKEYS yet. */
exchanging :: fn(conn: ptr[Connection]) -> bool {
    return conn.kex_sent || conn.kex_received
}

/** Take a message of the key exchange's. */
handle_kex :: fn(conn: ptr[mut Connection], message: u8[]) {
    kind :: byte_at(message, 0)
    if kind == MSG_KEXINIT {
        if conn.kex_received {
            fail(conn, DISCONNECT_PROTOCOL_ERROR, "a second KEXINIT")
            return void
        }
        // Strict: the first KEXINIT is the first packet
        if !conn.first_done && conn.into.sequence != 1 && is_strict_offered(conn) {
            fail(conn, DISCONNECT_PROTOCOL_ERROR, "KEXINIT not first")
            return void
        }
        if message.count > KEXINIT_BYTES {
            fail(conn, DISCONNECT_PROTOCOL_ERROR, "a KEXINIT too long")
            return void
        }
        // A server takes one exchange before its client's logged in: each is costly, and a peer that hasn't logged in
        // could ask for them over and over
        if conn.first_done && conn.role == .Server && !conn.authenticated {
            fail(conn, DISCONNECT_PROTOCOL_ERROR, "a key exchange again before logging in")
            return void
        }
        for byte, i in message {
            if i < conn.their_kexinit.count {
                conn.their_kexinit[i] = byte
            }
        }
        conn.their_kexinit_length = message.count
        conn.kex_received = true
        send_kexinit(conn)
        if !negotiate(conn) {
            return void
        }
        if conn.role == .Client {
            send_exchange(conn)
        }
        return void
    }
    if !conn.kex_received {
        fail(conn, DISCONNECT_PROTOCOL_ERROR, "a key exchange message before KEXINIT")
        return void
    }
    if kind == MSG_KEX_INIT && conn.role == .Server && !conn.exchange_sent {
        answer_exchange(conn, message)
        return void
    }
    if kind == MSG_KEX_REPLY && conn.role == .Client && conn.exchange_sent && conn.waiting == .Nothing && !conn.newkeys_sent {
        take_reply(conn, message)
        return void
    }
    // Only once this side has the new keys, and has sent its own NEWKEYS: a client's exchange is sent before it has
    // any, and a NEWKEYS taken then would have it read in the clear
    if kind == MSG_NEWKEYS && conn.exchange_sent && conn.newkeys_sent && !conn.newkeys_received {
        // Read under the new keys from here
        conn.into = conn.next_in
        if conn.strict {
            conn.into.sequence = 0
        }
        conn.newkeys_received = true
        finish_exchange(conn)
        return void
    }
    fail(conn, DISCONNECT_PROTOCOL_ERROR, "a key exchange message out of place")
}

/** Whether this side offered strict key exchange: it always does. */
is_strict_offered :: fn(conn: ptr[Connection]) -> bool {
    return true
}

/** Once both NEWKEYS are done: the exchange over, held messages sent, and after the first, what comes next. */
finish_exchange :: fn(conn: ptr[mut Connection]) {
    if !conn.newkeys_sent || !conn.newkeys_received {
        return void
    }
    first :: !conn.first_done
    conn.kex_sent = false
    conn.kex_received = false
    conn.exchange_sent = false
    conn.first_done = true
    // The exchange's secrets aren't wanted any more
    for i in cast[usize](0)..<conn.shared.count {
        conn.shared[i] = 0
    }
    for i in cast[usize](0)..<32 {
        conn.x25519[i] = 0
    }
    for i in cast[usize](0)..<conn.ml_kem.count {
        conn.ml_kem[i] = 0
    }
    flush_held(conn)
    if first && conn.role == .Client {
        writer := Writer.{}
        put_u8(conn.message[0..<PAYLOAD_BYTES], &writer, MSG_SERVICE_REQUEST)
        put_text(conn.message[0..<PAYLOAD_BYTES], &writer, "ssh-userauth")
        send_message(conn, range(conn.message[0..<PAYLOAD_BYTES], 0, writer.at))
    }
}

/**
 * Negotiate from both KEXINITs: the exchange, the host key's algorithm and each way's cipher; and whether strict key
 * exchange and ext-info are on.
 *
 * @return True; false if nothing's in common, when the connection's ended.
 */
negotiate :: fn(conn: ptr[mut Connection]) -> bool {
    ours :: range(conn.our_kexinit[0..<KEXINIT_BYTES], 0, conn.our_kexinit_length)
    theirs :: range(conn.their_kexinit[0..<KEXINIT_BYTES], 0, conn.their_kexinit_length)
    client_init :: if conn.role == .Client { ours } else { theirs }
    server_init :: if conn.role == .Client { theirs } else { ours }
    if !kexinit_readable(client_init) || !kexinit_readable(server_init) {
        fail(conn, DISCONNECT_PROTOCOL_ERROR, "a KEXINIT that can't be read")
        return false
    }
    their_follows :: kexinit_follows(if conn.role == .Client { server_init } else { client_init })
    chosen : u8[64]
    kex_length :: choose(name_list(client_init, 0), name_list(server_init, 0), chosen[0..<64])
    kex :: range(chosen[0..<64], 0, kex_length)
    conn.exchange = if is(kex, "mlkem768x25519-sha256") { KeyExchange.Hybrid }
        else if is(kex, "curve25519-sha256") || is(kex, "curve25519-sha256@libssh.org") { KeyExchange.Curve }
        else { KeyExchange.None }
    host_length :: choose(name_list(client_init, 1), name_list(server_init, 1), chosen[0..<64])
    host_ok :: is(range(chosen[0..<64], 0, host_length), "ssh-ed25519")
    out_list :: if conn.role == .Client { cast[usize](2) } else { cast[usize](3) }
    in_list :: if conn.role == .Client { cast[usize](3) } else { cast[usize](2) }
    conn.cipher_out = cipher_named(range(chosen[0..<64], 0, choose(name_list(client_init, out_list), name_list(server_init, out_list), chosen[0..<64])))
    conn.cipher_in = cipher_named(range(chosen[0..<64], 0, choose(name_list(client_init, in_list), name_list(server_init, in_list), chosen[0..<64])))
    compression :: choose(name_list(client_init, 6), name_list(server_init, 6), chosen[0..<64]) > 0 && choose(name_list(client_init, 7), name_list(server_init, 7), chosen[0..<64]) > 0
    if conn.exchange == .None || !host_ok || conn.cipher_out == .None || conn.cipher_in == .None || !compression {
        fail(conn, DISCONNECT_KEY_EXCHANGE_FAILED, "no algorithms in common")
        return false
    }
    if !conn.first_done {
        conn.strict = has_name(name_list(client_init, 0), string_bytes("kex-strict-c-v00@openssh.com"))
            && has_name(name_list(server_init, 0), string_bytes("kex-strict-s-v00@openssh.com"))
        // Required: a peer without it is open to Terrapin's prefix truncation
        if !conn.strict {
            fail(conn, DISCONNECT_KEY_EXCHANGE_FAILED, "strict key exchange is required")
            return false
        }
        conn.peer_wants_ext_info = conn.role == .Server && has_name(name_list(client_init, 0), string_bytes("ext-info-c"))
    }
    // A guessed first exchange packet that guessed wrong is passed over
    if their_follows {
        theirs_init :: if conn.role == .Client { server_init } else { client_init }
        first_kex : u8[64]
        first_host : u8[64]
        kex_named :: range(first_kex[0..<64], 0, first_name(name_list(theirs_init, 0), first_kex[0..<64]))
        host_named :: range(first_host[0..<64], 0, first_name(name_list(theirs_init, 1), first_host[0..<64]))
        conn.skip_guess = !same(kex_named, kex) || !is(host_named, "ssh-ed25519")
    }
    return true
}

/** Whether a KEXINIT's ten name-lists, boolean and reserved word can be read. */
kexinit_readable :: fn(init: u8[]) -> bool {
    reader := Reader.{at = 17, end = init.count}
    for i in 0..<10 {
        _ = get_string(init, &reader)
    }
    _ = get_bool(init, &reader)
    _ = get_u32(init, &reader)
    return !reader.bad
}

/** A KEXINIT's name-list at a position, 0 to 9. */
name_list :: fn(init: u8[], position: usize) -> u8[] {
    reader := Reader.{at = 17, end = init.count}
    for i in cast[usize](0)..<position {
        _ = get_string(init, &reader)
    }
    return get_string(init, &reader)
}

/** Whether a KEXINIT says a guessed exchange packet follows it. */
kexinit_follows :: fn(init: u8[]) -> bool {
    reader := Reader.{at = 17, end = init.count}
    for i in 0..<10 {
        _ = get_string(init, &reader)
    }
    return get_bool(init, &reader)
}

/** A name-list's first name, copied; its length. */
first_name :: fn(list: u8[], into: mut u8[]) -> usize {
    count := cast[usize](0)
    for byte in list {
        if byte == 0x2c {
            break
        }
        if count < into.count {
            into[count] = byte
        }
        count += 1
    }
    return if count <= into.count { count } else { cast[usize](0) }
}

/** A cipher by its name; None for one this side doesn't have. */
cipher_named :: fn(name: u8[]) -> Cipher {
    if is(name, "chacha20-poly1305@openssh.com") {
        return .Chacha
    }
    if is(name, "aes256-gcm@openssh.com") {
        return .Gcm
    }
    return .None
}

// ---- The exchange

/** A client's: make its ephemeral keys and send KEX_INIT (KEX_ECDH_INIT or KEX_HYBRID_INIT, both 30). */
send_exchange #constant_time :: fn(conn: ptr[mut Connection]) {
    secret : crypto.SecretByte[32]
    random_secret(secret[0..<32])
    for i in cast[usize](0)..<32 {
        conn.x25519[i] = cast[u8](secret[i])
    }
    curve_public :: crypto.x25519_public_key(&conn.x25519)
    length := cast[usize](0)
    if conn.exchange == .Hybrid {
        d : crypto.SecretByte[32]
        z : crypto.SecretByte[32]
        random_secret(d[0..<32])
        random_secret(z[0..<32])
        public : crypto.MlKem768PublicKey
        crypto.ml_kem_768_key_pair(&d, &z, &public, &conn.ml_kem)
        // C_INIT: the ML-KEM public key, then X25519's
        for i in cast[usize](0)..<crypto.ML_KEM_768_PUBLIC_KEY_BYTES {
            conn.client_share[i] = public[i]
        }
        for i in cast[usize](0)..<32 {
            conn.client_share[crypto.ML_KEM_768_PUBLIC_KEY_BYTES + i] = curve_public[i]
        }
        length = crypto.ML_KEM_768_PUBLIC_KEY_BYTES + 32
    }
    else {
        for i in cast[usize](0)..<32 {
            conn.client_share[i] = curve_public[i]
        }
        length = 32
    }
    conn.client_share_length = length
    writer := Writer.{}
    put_u8(conn.message[0..<PAYLOAD_BYTES], &writer, MSG_KEX_INIT)
    put_string(conn.message[0..<PAYLOAD_BYTES], &writer, range(conn.client_share[0..<1216], 0, length))
    send_packet(conn, range(conn.message[0..<PAYLOAD_BYTES], 0, writer.at))
    conn.exchange_sent = true
}

/** A server's: take the client's KEX_INIT, work out K and H, and send KEX_REPLY and NEWKEYS. */
answer_exchange #constant_time :: fn(conn: ptr[mut Connection], message: u8[]) {
    reader := Reader.{at = 1, end = message.count}
    share :: get_string(message, &reader)
    expected :: if conn.exchange == .Hybrid { cast[usize](crypto.ML_KEM_768_PUBLIC_KEY_BYTES) + 32 } else { cast[usize](32) }
    if !done(&reader) || share.count != expected {
        fail(conn, DISCONNECT_KEY_EXCHANGE_FAILED, "a client's share of the wrong size")
        return void
    }
    for byte, i in share {
        if i < conn.client_share.count {
            conn.client_share[i] = byte
        }
    }
    conn.client_share_length = share.count
    secret : crypto.SecretByte[32]
    random_secret(secret[0..<32])
    for i in cast[usize](0)..<32 {
        conn.x25519[i] = cast[u8](secret[i])
    }
    curve_public :: crypto.x25519_public_key(&conn.x25519)
    their_curve : crypto.X25519PublicKey
    for i in cast[usize](0)..<32 {
        their_curve[i] = byte_at(share, expected - 32 + i)
    }
    curve_shared : crypto.SecretByte[32]
    if !crypto.x25519(&conn.x25519, &their_curve, &curve_shared) {
        fail(conn, DISCONNECT_KEY_EXCHANGE_FAILED, "an X25519 share of low order")
        return void
    }
    if conn.exchange == .Hybrid {
        public : crypto.MlKem768PublicKey
        for i in cast[usize](0)..<crypto.ML_KEM_768_PUBLIC_KEY_BYTES {
            public[i] = byte_at(share, i)
        }
        m : crypto.SecretByte[32]
        random_secret(m[0..<32])
        ciphertext : crypto.MlKem768Ciphertext
        kem_shared : crypto.SecretByte[32]
        if !crypto.ml_kem_768_encapsulate(&public, &m, &ciphertext, &kem_shared) {
            fail(conn, DISCONNECT_KEY_EXCHANGE_FAILED, "an ML-KEM public key that isn't one")
            return void
        }
        for i in cast[usize](0)..<crypto.ML_KEM_768_CIPHERTEXT_BYTES {
            conn.server_share[i] = ciphertext[i]
        }
        for i in cast[usize](0)..<32 {
            conn.server_share[crypto.ML_KEM_768_CIPHERTEXT_BYTES + i] = curve_public[i]
        }
        conn.server_share_length = crypto.ML_KEM_768_CIPHERTEXT_BYTES + 32
        hybrid_shared(conn, &kem_shared, &curve_shared)
    }
    else {
        for i in cast[usize](0)..<32 {
            conn.server_share[i] = curve_public[i]
        }
        conn.server_share_length = 32
        curve_shared_mpint(conn, &curve_shared)
    }
    host_blob :: blob_of(&conn.host_key)
    exchange_hash(conn, host_blob)
    signature :: ed25519_signature(&conn.host_secret, conn.exchange_hash[0..<32])
    writer := Writer.{}
    put_u8(conn.message[0..<PAYLOAD_BYTES], &writer, MSG_KEX_REPLY)
    put_string(conn.message[0..<PAYLOAD_BYTES], &writer, host_blob)
    put_string(conn.message[0..<PAYLOAD_BYTES], &writer, range(conn.server_share[0..<1120], 0, conn.server_share_length))
    put_string(conn.message[0..<PAYLOAD_BYTES], &writer, signature[0..<ED25519_SIGNATURE_BYTES])
    send_packet(conn, range(conn.message[0..<PAYLOAD_BYTES], 0, writer.at))
    conn.exchange_sent = true
    derive_keys(conn)
    send_newkeys(conn)
}

/** A client's: take the server's KEX_REPLY, work out K and H, check the host key's signature, and ask about the key. */
take_reply #constant_time :: fn(conn: ptr[mut Connection], message: u8[]) {
    reader := Reader.{at = 1, end = message.count}
    host_blob :: get_string(message, &reader)
    share :: get_string(message, &reader)
    signature :: get_string(message, &reader)
    expected :: if conn.exchange == .Hybrid { cast[usize](crypto.ML_KEM_768_CIPHERTEXT_BYTES) + 32 } else { cast[usize](32) }
    if !done(&reader) || share.count != expected {
        fail(conn, DISCONNECT_KEY_EXCHANGE_FAILED, "a server's reply that can't be read")
        return void
    }
    host :: parse_public_key(host_blob) or_else PublicKey.{}
    if host.kind != .Ed25519 {
        fail(conn, DISCONNECT_KEY_EXCHANGE_FAILED, "a host key that isn't Ed25519")
        return void
    }
    // Once trusted, a rekey's host key has to be the same one
    if conn.first_done && !same(host_blob, blob_of(&conn.host_key)) {
        fail(conn, DISCONNECT_HOST_KEY_NOT_VERIFIABLE, "the host key changed")
        return void
    }
    conn.host_key = host
    for byte, i in share {
        if i < conn.server_share.count {
            conn.server_share[i] = byte
        }
    }
    conn.server_share_length = share.count
    their_curve : crypto.X25519PublicKey
    for i in cast[usize](0)..<32 {
        their_curve[i] = byte_at(share, expected - 32 + i)
    }
    curve_shared : crypto.SecretByte[32]
    if !crypto.x25519(&conn.x25519, &their_curve, &curve_shared) {
        fail(conn, DISCONNECT_KEY_EXCHANGE_FAILED, "an X25519 share of low order")
        return void
    }
    if conn.exchange == .Hybrid {
        ciphertext : crypto.MlKem768Ciphertext
        for i in cast[usize](0)..<crypto.ML_KEM_768_CIPHERTEXT_BYTES {
            ciphertext[i] = byte_at(share, i)
        }
        kem_shared : crypto.SecretByte[32]
        if !crypto.ml_kem_768_decapsulate(&conn.ml_kem, &ciphertext, &kem_shared) {
            fail(conn, DISCONNECT_KEY_EXCHANGE_FAILED, "ML-KEM's decapsulation failed")
            return void
        }
        hybrid_shared(conn, &kem_shared, &curve_shared)
    }
    else {
        curve_shared_mpint(conn, &curve_shared)
    }
    exchange_hash(conn, host_blob)
    if !verify_signature(&conn.host_key, conn.exchange_hash[0..<32], signature) {
        fail(conn, DISCONNECT_KEY_EXCHANGE_FAILED, "the host key's signature doesn't match")
        return void
    }
    derive_keys(conn)
    // A rekey's host key is the one trusted already
    if conn.first_done {
        send_newkeys(conn)
        return void
    }
    conn.waiting = .Trust
    event(conn, .HostKey)
}

/**
 * A client's answer about the server's host key: trusted, NEWKEYS is sent and the connection goes on; otherwise it's
 * ended.
 *
 * @param conn The connection, its HostKey event taken.
 * @param trusted Whether the key is the server's, as known hosts say, or the user agreed.
 */
trust_host_key :: fn(conn: ptr[mut Connection], trusted: bool) {
    if conn.waiting != .Trust {
        return void
    }
    conn.waiting = .Nothing
    if !trusted {
        disconnect(conn, DISCONNECT_HOST_KEY_NOT_VERIFIABLE, "the host key isn't trusted")
        return void
    }
    send_newkeys(conn)
    process(conn)
}

/** Send NEWKEYS, and send under the new keys from here. */
send_newkeys :: fn(conn: ptr[mut Connection]) {
    writer := Writer.{}
    put_u8(conn.message[0..<PAYLOAD_BYTES], &writer, MSG_NEWKEYS)
    send_packet(conn, range(conn.message[0..<PAYLOAD_BYTES], 0, writer.at))
    conn.out = conn.next_out
    if conn.strict {
        conn.out.sequence = 0
    }
    // A server's EXT_INFO is the first packet under the first keys (RFC 8308, 2.4)
    if conn.role == .Server && !conn.first_done && conn.peer_wants_ext_info {
        send_ext_info(conn)
    }
    conn.newkeys_sent = true
    finish_exchange(conn)
}

/** mlkem768x25519-sha256's K: SHA-256 of ML-KEM's secret then X25519's, as a string. */
hybrid_shared #constant_time :: fn(conn: ptr[mut Connection], kem: ptr[crypto.SecretByte[32]], curve: ptr[crypto.SecretByte[32]]) {
    hasher := crypto.sha256_start()
    crypto.sha256_update_secret(&hasher, kem[0..<32])
    crypto.sha256_update_secret(&hasher, curve[0..<32])
    digest :: crypto.sha256_finish_secret(&hasher)
    conn.shared[0] = 0
    conn.shared[1] = 0
    conn.shared[2] = 0
    conn.shared[3] = 32
    for i in cast[usize](0)..<32 {
        conn.shared[4 + i] = digest[i]
    }
    conn.shared_length = 36
}

/**
 * curve25519-sha256's K: X25519's secret as an mpint (RFC 8731, 3.1). How many leading zero bytes it has, and whether
 * its top bit is set, are declassified, as the encoding has to know; that's a few bits of a value hashed into keys,
 * as every implementation of it gives away.
 */
curve_shared_mpint #constant_time :: fn(conn: ptr[mut Connection], curve: ptr[crypto.SecretByte[32]]) {
    start := cast[usize](0)
    leading := true
    for i in cast[usize](0)..<32 {
        if leading && compiler.declassify(cast[u8](curve[i]) == 0) {
            start = i + 1
        }
        else {
            leading = false
        }
    }
    digits :: 32 - start
    sign :: digits > 0 && compiler.declassify(cast[u8](curve[start % 32]) & 0x80 != 0)
    length :: digits + (if sign { cast[usize](1) } else { cast[usize](0) })
    conn.shared[0] = 0
    conn.shared[1] = 0
    conn.shared[2] = 0
    conn.shared[3] = cast[crypto.SecretByte](cast[u8](length))
    at := cast[usize](4)
    if sign {
        conn.shared[4] = 0
        at = 5
    }
    for i in start..<32 {
        if at < conn.shared.count {
            conn.shared[at] = curve[i]
        }
        at += 1
    }
    conn.shared_length = 4 + length
}

/** Hash a string into SHA-256: its length, then it. */
hash_string :: fn(hasher: ptr[mut crypto.Sha256], bytes: u8[]) {
    length : u8[4]
    for i in cast[usize](0)..<4 {
        length[i] = cast[u8](bytes.count >> (8 * (3 - i)))
    }
    crypto.sha256_update(hasher, length[0..<4])
    crypto.sha256_update(hasher, bytes)
}

/**
 * Work out the exchange hash H (RFC 4253, 8; RFC 8731, 3.1; the hybrid's draft): of both versions, both KEXINITs,
 * the host key, both shares and K. The first is the session's identifier.
 */
exchange_hash #constant_time :: fn(conn: ptr[mut Connection], host_blob: u8[]) {
    ours :: string_bytes(VERSION)
    theirs :: range(conn.peer_version[0..<256], 0, conn.peer_version_length)
    our_init :: range(conn.our_kexinit[0..<KEXINIT_BYTES], 0, conn.our_kexinit_length)
    their_init :: range(conn.their_kexinit[0..<KEXINIT_BYTES], 0, conn.their_kexinit_length)
    client :: conn.role == .Client
    hasher := crypto.sha256_start()
    hash_string(&hasher, if client { ours } else { theirs })
    hash_string(&hasher, if client { theirs } else { ours })
    hash_string(&hasher, if client { our_init } else { their_init })
    hash_string(&hasher, if client { their_init } else { our_init })
    hash_string(&hasher, host_blob)
    hash_string(&hasher, range(conn.client_share[0..<1216], 0, conn.client_share_length))
    hash_string(&hasher, range(conn.server_share[0..<1120], 0, conn.server_share_length))
    crypto.sha256_update_secret(&hasher, range(conn.shared[0..<40], 0, conn.shared_length))
    digest :: crypto.sha256_finish_secret(&hasher)
    // H is public: it's signed, and sent as the session's identifier in authentication
    for i in cast[usize](0)..<32 {
        conn.exchange_hash[i] = compiler.declassify(cast[u8](digest[i]))
    }
    if !conn.first_done {
        conn.session_id = conn.exchange_hash
    }
}

/**
 * Derive a key (RFC 4253, 7.2): SHA-256 of K, H, a letter and the session's identifier, extended by SHA-256 of K, H
 * and what's made so far, to as many bytes as wanted.
 */
derive #constant_time :: fn(conn: ptr[Connection], letter: u8, out: mut crypto.SecretByte[]) {
    k :: range(conn.shared[0..<40], 0, conn.shared_length)
    made : crypto.SecretByte[64]
    hasher := crypto.sha256_start()
    crypto.sha256_update_secret(&hasher, k)
    crypto.sha256_update(&hasher, conn.exchange_hash[0..<32])
    letters : u8[1]
    letters[0] = letter
    crypto.sha256_update(&hasher, letters[0..<1])
    crypto.sha256_update(&hasher, conn.session_id[0..<32])
    first :: crypto.sha256_finish_secret(&hasher)
    for i in cast[usize](0)..<32 {
        made[i] = first[i]
    }
    more := crypto.sha256_start()
    crypto.sha256_update_secret(&more, k)
    crypto.sha256_update(&more, conn.exchange_hash[0..<32])
    crypto.sha256_update_secret(&more, made[0..<32])
    second :: crypto.sha256_finish_secret(&more)
    for i in cast[usize](0)..<32 {
        made[32 + i] = second[i]
    }
    for i in cast[usize](0)..<out.count {
        if i < 64 {
            out[i] = made[i]
        }
    }
}

/** Derive each way's keys, for its cipher, into next_out and next_in. */
derive_keys :: fn(conn: ptr[mut Connection]) {
    client :: conn.role == .Client
    // Client to server: IV A, key C; server to client: IV B, key D
    conn.next_out = direction_keys(conn, conn.cipher_out, if client { cast[u8](0x41) } else { cast[u8](0x42) },
        if client { cast[u8](0x43) } else { cast[u8](0x44) })
    conn.next_in = direction_keys(conn, conn.cipher_in, if client { cast[u8](0x42) } else { cast[u8](0x41) },
        if client { cast[u8](0x44) } else { cast[u8](0x43) })
}

/** One way's keys for a cipher. */
direction_keys #constant_time :: fn(conn: ptr[Connection], cipher: Cipher, iv_letter: u8, key_letter: u8) -> Direction {
    keys := Direction.{cipher = cipher}
    if cipher == .Chacha {
        both : crypto.SecretByte[64]
        derive(conn, key_letter, both[0..<64])
        keys.chacha = crypto.ssh_chacha_keys(&both)
    }
    else {
        key : crypto.SecretByte[32]
        derive(conn, key_letter, key[0..<32])
        for i in cast[usize](0)..<32 {
            keys.gcm_key[i] = cast[u8](key[i])
        }
        iv : crypto.SecretByte[12]
        derive(conn, iv_letter, iv[0..<12])
        // The IV is public, as GCM's nonces are
        for i in cast[usize](0)..<12 {
            keys.gcm_nonce[i] = compiler.declassify(cast[u8](iv[i]))
        }
    }
    return keys
}

// ---- Packets

/**
 * Send a message: as a packet now, or, if keys are being exchanged and it isn't the exchange's, held until they are.
 *
 * @param conn The connection.
 * @param message Its payload.
 */
send_message :: fn(conn: ptr[mut Connection], message: u8[]) {
    kind :: if message.count > 0 { message[0] } else { cast[u8](0) }
    transport :: kind < 50 && kind != MSG_SERVICE_REQUEST && kind != MSG_SERVICE_ACCEPT
    if conn.first_done && exchanging(conn) && !transport {
        if conn.held_count + 4 + message.count > conn.held.count {
            conn.ended = true
            conn.ended_reason = DISCONNECT_BY_APPLICATION
            return void
        }
        writer := Writer.{at = conn.held_count}
        put_string(conn.held[0..<HELD_BYTES], &writer, message)
        conn.held_count = writer.at
        return void
    }
    send_packet(conn, message)
}

/** Send what was held while keys were exchanged. */
flush_held :: fn(conn: ptr[mut Connection]) {
    reader := Reader.{at = 0, end = conn.held_count}
    loop {
        message :: get_string(conn.held[0..<HELD_BYTES], &reader)
        if reader.bad {
            break
        }
        send_packet(conn, message)
    }
    while reader.at < reader.end
    conn.held_count = 0
}

/**
 * Seal a payload into a packet on the output, under the keys sent with now.
 *
 * @param conn The connection; ended if the output's full, as its caller isn't sending.
 * @param payload The payload.
 */
send_packet #constant_time :: fn(conn: ptr[mut Connection], payload: u8[]) {
    if conn.ended {
        return void
    }
    cipher :: conn.out.cipher
    block :: if cipher == .Gcm { cast[usize](16) } else { cast[usize](8) }
    // What the block counts: length and all in the clear, or with a cipher that keeps the length apart, all but it
    base :: if cipher == .None { 5 + payload.count } else { 1 + payload.count }
    pad := block - base % block
    if pad < 4 {
        pad += block
    }
    packet_length :: 1 + payload.count + pad
    tag_length :: if cipher == .None { cast[usize](0) } else { cast[usize](16) }
    total :: 4 + packet_length + tag_length
    if payload.count > CHANNEL_PACKET + 64 && payload.count > KEXINIT_BYTES || packet_length + 4 > conn.sealing.count
        || conn.outgoing_count + total > conn.outgoing.count {
        conn.ended = true
        conn.ended_reason = DISCONNECT_BY_APPLICATION
        return void
    }
    // The packet in the clear: length, padding's length, payload, padding
    padding : u8[32]
    random_bytes(padding[0..<32])
    plain :: range_mut(conn.sealing[0..<PAYLOAD_BYTES], 0, 4 + packet_length)
    for i in cast[usize](0)..<4 {
        if i < plain.count {
            plain[i] = cast[crypto.SecretByte](cast[u8](packet_length >> (8 * (3 - i))))
        }
    }
    if 4 < plain.count {
        plain[4] = cast[crypto.SecretByte](cast[u8](pad))
    }
    for byte, i in payload {
        if 5 + i < plain.count {
            plain[5 + i] = cast[crypto.SecretByte](byte)
        }
    }
    for i in cast[usize](0)..<pad {
        to :: 5 + payload.count + i
        if to < plain.count {
            plain[to] = cast[crypto.SecretByte](byte_at(padding[0..<32], i % 32))
        }
    }
    at :: conn.outgoing_count
    out :: range_mut(conn.outgoing[0..<OUTGOING_BYTES], at, at + total)
    if cipher == .None {
        for byte, i in plain {
            if i < out.count {
                out[i] = compiler.declassify(cast[u8](byte))
            }
        }
    }
    else if cipher == .Chacha {
        tag : crypto.Tag128
        _ = crypto.ssh_chacha_seal(&conn.out.chacha, conn.out.sequence, plain, range_mut(out, 0, 4 + packet_length), &tag)
        for i in cast[usize](0)..<16 {
            to :: 4 + packet_length + i
            if to < out.count {
                out[to] = tag[i]
            }
        }
    }
    else {
        for i in cast[usize](0)..<4 {
            if i < out.count && i < plain.count {
                out[i] = compiler.declassify(cast[u8](plain[i]))
            }
        }
        tag : crypto.Tag128
        _ = crypto.aes256_gcm_seal(&conn.out.gcm_key, &conn.out.gcm_nonce, range(plain, 4, 4 + packet_length), range(out, 0, 4),
            range_mut(out, 4, 4 + packet_length), &tag)
        for i in cast[usize](0)..<16 {
            to :: 4 + packet_length + i
            if to < out.count {
                out[to] = tag[i]
            }
        }
        next_nonce(&conn.out.gcm_nonce)
    }
    for i in cast[usize](0)..<plain.count {
        plain[i] = 0
    }
    conn.outgoing_count += total
    conn.out.sequence += 1
    conn.out.bytes += cast[u64](total)
    if conn.first_done && conn.out.bytes > REKEY_BYTES && !exchanging(conn) {
        send_kexinit(conn)
    }
}

/** AES-GCM's nonce for the next packet: its last 8 bytes counted up, big-endian. */
next_nonce :: fn(nonce: ptr[mut crypto.Nonce96]) {
    with {
        i := cast[usize](11)
    }
    loop {
        nonce[i] = nonce[i] + 1
        if nonce[i] != 0 {
            return void
        }
        i -= 1
    }
    while i >= 4
}

/**
 * Open the next packet, if it's all arrived, into payload.
 *
 * @return Its payload's length; null if more must arrive, or it's damaged or forged, when the connection's ended.
 */
next_packet #constant_time :: fn(conn: ptr[mut Connection]) -> usize? {
    cipher :: conn.into.cipher
    if conn.incoming_count < 4 {
        return null
    }
    arrived :: range(conn.incoming[0..<INCOMING_BYTES], 0, conn.incoming_count)
    length := cast[usize](0)
    if cipher == .Chacha {
        length = cast[usize](crypto.ssh_chacha_length(&conn.into.chacha, conn.into.sequence, range(arrived, 0, 4)))
    }
    else {
        for i in cast[usize](0)..<4 {
            length = (length << 8) | cast[usize](byte_at(arrived, i))
        }
    }
    block :: if cipher == .Gcm { cast[usize](16) } else { cast[usize](8) }
    aligned :: if cipher == .None { (length + 4) % block == 0 } else { length % block == 0 }
    if length < 8 || length > MAX_PACKET || !aligned {
        fail(conn, DISCONNECT_PROTOCOL_ERROR, "a packet length that can't be")
        return null
    }
    tag_length :: if cipher == .None { cast[usize](0) } else { cast[usize](16) }
    total :: 4 + length + tag_length
    if conn.incoming_count < total {
        return null
    }
    opened :: range_mut(conn.sealing[0..<PAYLOAD_BYTES], 0, length)
    if cipher == .None {
        for i in cast[usize](0)..<length {
            if i < opened.count {
                opened[i] = cast[crypto.SecretByte](byte_at(arrived, 4 + i))
            }
        }
    }
    else if cipher == .Chacha {
        tag : crypto.Tag128
        for i in cast[usize](0)..<16 {
            tag[i] = byte_at(arrived, 4 + length + i)
        }
        if !crypto.ssh_chacha_open(&conn.into.chacha, conn.into.sequence, range(arrived, 0, 4 + length), &tag, opened) {
            fail(conn, DISCONNECT_MAC_ERROR, "a packet that isn't authentic")
            return null
        }
    }
    else {
        tag : crypto.Tag128
        for i in cast[usize](0)..<16 {
            tag[i] = byte_at(arrived, 4 + length + i)
        }
        if !crypto.aes256_gcm_open(&conn.into.gcm_key, &conn.into.gcm_nonce, range(arrived, 4, 4 + length), range(arrived, 0, 4),
            &tag, opened) {
            fail(conn, DISCONNECT_MAC_ERROR, "a packet that isn't authentic")
            return null
        }
        next_nonce(&conn.into.gcm_nonce)
    }
    conn.into.sequence += 1
    conn.into.bytes += cast[u64](total)
    // What's in it is taken as the protocol says: public from here, wiped once it's been
    pad :: if opened.count > 0 { cast[usize](compiler.declassify(cast[u8](opened[0]))) } else { cast[usize](0) }
    if pad < 4 || pad + 1 > length {
        fail(conn, DISCONNECT_PROTOCOL_ERROR, "padding that can't be")
        return null
    }
    payload_length :: length - 1 - pad
    for i in cast[usize](0)..<payload_length {
        if i < conn.payload.count && 1 + i < opened.count {
            conn.payload[i] = compiler.declassify(cast[u8](opened[1 + i]))
        }
    }
    for i in cast[usize](0)..<opened.count {
        opened[i] = 0
    }
    drop_incoming(conn, total)
    if conn.first_done && conn.into.bytes > REKEY_BYTES && !exchanging(conn) {
        send_kexinit(conn)
    }
    return payload_length
}
