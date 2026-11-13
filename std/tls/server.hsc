package tls

import compiler from "base"
import crypto from "std"
import random from "std"

/*
 * The server's handshake (RFC 8446 §2, §4): a ClientHello taken, its suite, group and signature scheme chosen, or a
 * HelloRetryRequest asking for a group it named but gave no key share for; then the ServerHello, EncryptedExtensions,
 * Certificate, CertificateVerify and Finished, and the client's Finished checked. The suite's the client's first that's
 * offered here; the group X25519 if it has a share, then P-256's.
 */

/**
 * Give a server's ServerHello a fixed random and X25519 key, as a recorded handshake's (RFC 8448) is replayed, rather
 * than drawn.
 *
 * @param connection The connection, set up as a server, before the ClientHello arrives.
 * @param server_random The random.
 * @param x25519 The X25519 secret key.
 */
server_with_keys #constant_time :: fn(connection: ptr[mut Connection], server_random: ptr[u8[32]], x25519: ptr[crypto.X25519SecretKey]) {
    connection.fixed_keys = true
    connection.server_random = server_random^
    connection.x25519 = x25519^
}

/**
 * Act on a handshake message from the client, as the server's state allows.
 *
 * @param connection The connection, a server's.
 * @param kind The message's type.
 * @param message The message, with its header.
 */
server_message :: fn(connection: ptr[mut Connection], kind: u8, message: u8[]) {
    if connection.state == .WaitClientHello && kind == CLIENT_HELLO {
        take_client_hello(connection, message)
    }
    else if connection.state == .WaitClientFinished && kind == FINISHED {
        if !check_finished(connection, &connection.client_handshake_secret, message) {
            fail(connection, ALERT_DECRYPT_ERROR)
            return void
        }
        transcript_add(&connection.transcript, message)
        set_read_keys(connection, &connection.client_secret)
        connection.state = .Connected
        connection.handshake_done = true
    }
    else if connection.state == .Connected && kind == KEY_UPDATE {
        take_key_update(connection, message)
    }
    else {
        fail(connection, ALERT_UNEXPECTED_MESSAGE)
    }
}

/** What a ClientHello offers, as take_client_hello reads it. */
Offer :: struct {
    tls13 : bool,
    suite : Suite,
    x25519_group : bool,
    p256_group : bool,
    /** Where its key shares are in the message, and their lengths; 0 for none. */
    x25519_at : usize,
    x25519_length : usize,
    p256_at : usize,
    p256_length : usize,
    ecdsa_p256 : bool,
    ed25519 : bool,
    /** Whether it offers application protocols by ALPN, and the one this server speaks among them. */
    protocols : bool,
    protocol : bool,
}

/**
 * Read what a ClientHello offers.
 *
 * @param connection The connection, whose session ID is kept.
 * @param message The message.
 * @return What it offers; null if it's malformed.
 */
read_offer :: fn(connection: ptr[mut Connection], message: u8[]) -> Offer? {
    offer := Offer.{}
    reader := reader_of(message)
    _ = get_bytes(message, &reader, 4)
    _ = get_u16(message, &reader)
    _ = get_bytes(message, &reader, 32)
    session := get_vector(message, &reader, 1)
    if session.end - session.at > 32 {
        return null
    }
    connection.session_id_length = session.end - session.at
    for i in 0..<connection.session_id_length {
        if i < connection.session_id.count && session.at + i < message.count {
            connection.session_id[i] = message[session.at + i]
        }
    }
    suites := get_vector(message, &reader, 2)
    loop {
        if suites.at >= suites.end || suites.bad {
            break
        }
        suite :: get_u16(message, &suites)
        if offer.suite == .None {
            known :: if suite == 0x1301 { Suite.Aes128GcmSha256 } else if suite == 0x1302 { Suite.Aes256GcmSha384 }
                else if suite == 0x1303 { Suite.Chacha20Poly1305Sha256 } else { Suite.None }
            if connection.only_suite == .None || known == connection.only_suite {
                offer.suite = known
            }
        }
    }
    while true
    compressions := get_vector(message, &reader, 1)
    null_compression := false
    loop {
        if compressions.at >= compressions.end || compressions.bad {
            break
        }
        null_compression = null_compression || get_u8(message, &compressions) == 0
    }
    while true
    extensions := get_vector(message, &reader, 2)
    if !done(&reader) || !null_compression || suites.bad {
        return null
    }
    loop {
        if extensions.at >= extensions.end || extensions.bad {
            break
        }
        kind :: get_u16(message, &extensions)
        data := get_vector(message, &extensions, 2)
        if kind == EXTENSION_SUPPORTED_VERSIONS {
            versions := get_vector(message, &data, 1)
            loop {
                if versions.at >= versions.end || versions.bad {
                    break
                }
                offer.tls13 = offer.tls13 || get_u16(message, &versions) == VERSION_13
            }
            while true
        }
        else if kind == EXTENSION_SUPPORTED_GROUPS {
            groups := get_vector(message, &data, 2)
            loop {
                if groups.at >= groups.end || groups.bad {
                    break
                }
                group :: get_u16(message, &groups)
                offer.x25519_group = offer.x25519_group || group == GROUP_X25519
                offer.p256_group = offer.p256_group || group == GROUP_P256
            }
            while true
        }
        else if kind == EXTENSION_KEY_SHARE {
            shares := get_vector(message, &data, 2)
            loop {
                if shares.at >= shares.end || shares.bad {
                    break
                }
                group :: get_u16(message, &shares)
                key := get_vector(message, &shares, 2)
                if group == GROUP_X25519 && offer.x25519_length == 0 {
                    offer.x25519_at = key.at
                    offer.x25519_length = key.end - key.at
                }
                else if group == GROUP_P256 && offer.p256_length == 0 {
                    offer.p256_at = key.at
                    offer.p256_length = key.end - key.at
                }
            }
            while true
            if shares.bad {
                return null
            }
        }
        else if kind == EXTENSION_ALPN {
            offer.protocols = true
            names := get_vector(message, &data, 2)
            loop {
                if names.at >= names.end || names.bad {
                    break
                }
                name := get_vector(message, &names, 1)
                offer.protocol = offer.protocol || (!name.bad && is_protocol(connection, range(message, name.at, name.end)))
            }
            while true
            if names.bad {
                return null
            }
        }
        else if kind == EXTENSION_SIGNATURE_ALGORITHMS {
            schemes := get_vector(message, &data, 2)
            loop {
                if schemes.at >= schemes.end || schemes.bad {
                    break
                }
                scheme :: get_u16(message, &schemes)
                offer.ecdsa_p256 = offer.ecdsa_p256 || scheme == SCHEME_ECDSA_P256_SHA256
                offer.ed25519 = offer.ed25519 || scheme == SCHEME_ED25519
            }
            while true
        }
    }
    while true
    if extensions.bad {
        return null
    }
    return offer
}

/**
 * Take a ClientHello: answer it with a HelloRetryRequest if it has no key share the server takes but names a group it
 * does, or with the server's flight.
 *
 * @param connection The connection.
 * @param message The message.
 */
take_client_hello :: fn(connection: ptr[mut Connection], message: u8[]) {
    offer :: read_offer(connection, message) or_else Offer.{suite = .None}
    if offer.suite == .None && !offer.tls13 && !offer.x25519_group {
        fail(connection, ALERT_DECODE_ERROR)
        return void
    }
    if !offer.tls13 {
        fail(connection, ALERT_PROTOCOL_VERSION)
        return void
    }
    if offer.suite == .None || (connection.retried && offer.suite != connection.suite) {
        fail(connection, if connection.retried { ALERT_ILLEGAL_PARAMETER } else { ALERT_HANDSHAKE_FAILURE })
        return void
    }
    // A client offering application protocols, but not this server's, isn't served (RFC 7301 §3.2)
    if connection.protocol_length > 0 && offer.protocols && !offer.protocol {
        fail(connection, ALERT_NO_APPLICATION_PROTOCOL)
        return void
    }
    connection.protocol_agreed = connection.protocol_length > 0 && offer.protocol
    connection.suite = offer.suite
    connection.scheme = if connection.identity.kind == .P256 && offer.ecdsa_p256 { SCHEME_ECDSA_P256_SHA256 }
        else if connection.identity.kind == .ED25519 && offer.ed25519 { SCHEME_ED25519 } else { cast[u16](0) }
    if connection.scheme == 0 {
        fail(connection, ALERT_HANDSHAKE_FAILURE)
        return void
    }
    // A share of a group taken here, X25519's first; or else a group named, asked for again
    takes_x25519 :: connection.only_group == 0 || connection.only_group == GROUP_X25519
    takes_p256 :: connection.only_group == 0 || connection.only_group == GROUP_P256
    group := cast[u16](0)
    if offer.x25519_length == 32 && takes_x25519 {
        group = GROUP_X25519
    }
    else if offer.p256_length == 65 && takes_p256 {
        group = GROUP_P256
    }
    if group == 0 {
        named :: if offer.x25519_group && takes_x25519 { GROUP_X25519 } else if offer.p256_group && takes_p256 { GROUP_P256 }
            else { cast[u16](0) }
        if connection.retried || named == 0 {
            fail(connection, if connection.retried { ALERT_ILLEGAL_PARAMETER } else { ALERT_HANDSHAKE_FAILURE })
            return void
        }
        retry(connection, message, named)
        return void
    }
    if connection.retried && group != connection.group {
        fail(connection, ALERT_ILLEGAL_PARAMETER)
        return void
    }
    connection.group = group
    transcript_add(&connection.transcript, message)
    shared : crypto.SecretByte[32]
    public : u8[65]
    public_length := cast[usize](0)
    agreed := false
    if group == GROUP_X25519 {
        if !connection.fixed_keys {
            bytes : u8[32]
            random.fill(bytes)
            for byte, i in bytes {
                connection.x25519[i] = byte
            }
        }
        made :: crypto.x25519_public_key(&connection.x25519)
        for byte, i in made {
            public[i] = byte
        }
        public_length = 32
        theirs : crypto.X25519PublicKey
        for byte, i in range(message, offer.x25519_at, offer.x25519_at + 32) {
            if i < 32 {
                theirs[i] = byte
            }
        }
        agreed = crypto.x25519(&connection.x25519, &theirs, &shared)
    }
    else {
        make_p256_key(connection)
        made : crypto.P256PublicKey
        _ = crypto.p256_public_key(&connection.p256, &made)
        for byte, i in made {
            public[i] = byte
        }
        public_length = 65
        agreed = crypto.p256_ecdh(&connection.p256, range(message, offer.p256_at, offer.p256_at + 65), &shared)
    }
    if !agreed {
        fail(connection, ALERT_ILLEGAL_PARAMETER)
        return void
    }
    if !connection.fixed_keys {
        random.fill(connection.server_random)
    }
    send_server_hello(connection, connection.server_random[0..<32], group, public[0..<public_length])
    // Middlebox compatibility: a ChangeCipherSpec after the first ServerHello, for a client that sent a session ID
    if connection.session_id_length > 0 && !connection.retried {
        change :: u8.[1]
        write_record(connection, CONTENT_CHANGE_CIPHER_SPEC, change[0..<1])
    }
    handshake_secrets(connection, &shared)
    connection.client_handshake_secret = connection.client_secret
    set_write_keys(connection, &connection.server_secret)
    set_read_keys(connection, &connection.client_secret)
    send_flight(connection)
}

/**
 * Ask again, with a HelloRetryRequest naming a group (§4.1.4): the transcript restarted from the ClientHello's hash.
 *
 * @param connection The connection, its suite chosen.
 * @param message The first ClientHello.
 * @param group The group asked for.
 */
retry :: fn(connection: ptr[mut Connection], message: u8[], group: u16) {
    transcript_add(&connection.transcript, message)
    first : u8[HASH_MOST]
    transcript_hash(&connection.transcript, suite_hash(connection.suite), &first)
    restart_transcript(connection, &first)
    connection.retried = true
    connection.group = group
    send_server_hello(connection, RETRY_RANDOM[0..<32], group, string_bytes(""))
    if connection.session_id_length > 0 {
        change :: u8.[1]
        write_record(connection, CONTENT_CHANGE_CIPHER_SPEC, change[0..<1])
    }
}

/**
 * Queue a ServerHello, or a HelloRetryRequest when its random is RETRY_RANDOM and it has no key: its key share, then
 * its supported_versions, as RFC 8448's are.
 *
 * @param connection The connection, its suite chosen.
 * @param server_random The random.
 * @param group The group.
 * @param public The server's key share; empty for a HelloRetryRequest, which names the group only.
 */
send_server_hello :: fn(connection: ptr[mut Connection], server_random: u8[], group: u16, public: u8[]) {
    into :: connection.building[0..<connection.building.count]
    writer := Writer.{}
    put_u8(into, &writer, SERVER_HELLO)
    body :: start_vector(into, &writer, 3)
    put_u16(into, &writer, LEGACY_VERSION)
    put_bytes(into, &writer, server_random)
    session :: start_vector(into, &writer, 1)
    put_bytes(into, &writer, range(connection.session_id, 0, connection.session_id_length))
    end_vector(into, &writer, session, 1)
    put_u16(into, &writer, cast[u16](connection.suite))
    put_u8(into, &writer, 0)
    extensions :: start_vector(into, &writer, 2)
    put_u16(into, &writer, EXTENSION_KEY_SHARE)
    share :: start_vector(into, &writer, 2)
    put_u16(into, &writer, group)
    if public.count > 0 {
        key :: start_vector(into, &writer, 2)
        put_bytes(into, &writer, public)
        end_vector(into, &writer, key, 2)
    }
    end_vector(into, &writer, share, 2)
    put_u16(into, &writer, EXTENSION_SUPPORTED_VERSIONS)
    versions :: start_vector(into, &writer, 2)
    put_u16(into, &writer, VERSION_13)
    end_vector(into, &writer, versions, 2)
    end_vector(into, &writer, extensions, 2)
    end_vector(into, &writer, body, 3)
    send_message(connection, range(into, 0, writer.at))
}

/**
 * Give where a DER element in bytes ends: its tag, its length's bytes, and its contents.
 *
 * @param bytes The bytes, from the element's tag.
 * @return Its whole length; 0 if it isn't one, or runs past them.
 */
der_length :: fn(bytes: u8[]) -> usize {
    if bytes.count < 2 {
        return 0
    }
    first :: bytes[1]
    if first < 0x80 {
        return if 2 + cast[usize](first) <= bytes.count { 2 + cast[usize](first) } else { cast[usize](0) }
    }
    size :: cast[usize](first & 0x7f)
    if size == 0 || size > 3 || 2 + size > bytes.count {
        return 0
    }
    length := cast[usize](0)
    for i in 0..<size {
        length = (length << 8) | cast[usize](bytes[2 + i])
    }
    total :: 2 + size + length
    return if total <= bytes.count { total } else { cast[usize](0) }
}

/**
 * Write an ECDSA signature's (r, s) as an ECDSA-Sig-Value's DER, as TLS sends it.
 *
 * @param into Where it goes.
 * @param writer The writer.
 * @param pair r then s, 32 bytes each.
 */
put_ecdsa_der :: fn(into: mut u8[], writer: ptr[mut Writer], pair: u8[]) {
    put_u8(into, writer, 0x30)
    sequence :: start_vector(into, writer, 1)
    for half in 0..<2 {
        part :: range(pair, cast[usize](half) * 32, cast[usize](half) * 32 + 32)
        first := cast[usize](0)
        loop {
            if first >= 31 || first >= part.count || part[first] != 0 {
                break
            }
            first += 1
        }
        while true
        put_u8(into, writer, 0x02)
        integer :: start_vector(into, writer, 1)
        // A leading zero keeps it positive
        if first < part.count && part[first] >= 0x80 {
            put_u8(into, writer, 0)
        }
        put_bytes(into, writer, range(part, first, part.count))
        end_vector(into, writer, integer, 1)
    }
    end_vector(into, writer, sequence, 1)
}

/**
 * Queue the server's flight after its ServerHello: EncryptedExtensions, Certificate, CertificateVerify and Finished, and
 * move to the application traffic keys to write with.
 *
 * @param connection The connection, its handshake keys set.
 */
send_flight :: fn(connection: ptr[mut Connection]) {
    into :: connection.building[0..<connection.building.count]
    // EncryptedExtensions: ALPN's answer, if they agreed
    writer := Writer.{}
    put_u8(into, &writer, ENCRYPTED_EXTENSIONS)
    encrypted :: start_vector(into, &writer, 3)
    extensions :: start_vector(into, &writer, 2)
    if connection.protocol_agreed {
        put_u16(into, &writer, EXTENSION_ALPN)
        alpn :: start_vector(into, &writer, 2)
        names :: start_vector(into, &writer, 2)
        name :: start_vector(into, &writer, 1)
        put_bytes(into, &writer, protocol_of(connection))
        end_vector(into, &writer, name, 1)
        end_vector(into, &writer, names, 2)
        end_vector(into, &writer, alpn, 2)
    }
    end_vector(into, &writer, extensions, 2)
    end_vector(into, &writer, encrypted, 3)
    send_message(connection, range(into, 0, writer.at))
    writer = Writer.{}
    put_u8(into, &writer, CERTIFICATE)
    body :: start_vector(into, &writer, 3)
    put_u8(into, &writer, 0)
    list :: start_vector(into, &writer, 3)
    chain :: view_of(cast[ptr[u8]](connection.identity.chain), connection.identity.chain_bytes)
    // A server proves itself with a certificate: an identity without one can't serve
    if chain.count == 0 {
        fail(connection, ALERT_INTERNAL_ERROR)
        return void
    }
    at := cast[usize](0)
    loop {
        if at >= chain.count {
            break
        }
        length :: der_length(chain[at..<chain.count])
        if length == 0 {
            fail(connection, ALERT_INTERNAL_ERROR)
            return void
        }
        entry :: start_vector(into, &writer, 3)
        put_bytes(into, &writer, range(chain, at, at + length))
        end_vector(into, &writer, entry, 3)
        put_u16(into, &writer, 0)
        at += length
    }
    while true
    end_vector(into, &writer, list, 3)
    end_vector(into, &writer, body, 3)
    if writer.overflow {
        fail(connection, ALERT_INTERNAL_ERROR)
        return void
    }
    send_message(connection, range(into, 0, writer.at))
    // CertificateVerify, over the transcript through the Certificate
    content : u8[64 + 34 + HASH_MOST]
    length :: verify_content(connection, true, content[0..<content.count])
    writer = Writer.{}
    put_u8(into, &writer, CERTIFICATE_VERIFY)
    verify_body :: start_vector(into, &writer, 3)
    put_u16(into, &writer, connection.scheme)
    signature :: start_vector(into, &writer, 2)
    if connection.scheme == SCHEME_ECDSA_P256_SHA256 {
        digest :: crypto.sha256(range(content, 0, length))
        extra : crypto.SecretByte[32]
        bytes : u8[32]
        random.fill(bytes)
        for byte, i in bytes {
            extra[i] = cast[crypto.SecretByte](byte)
        }
        none : crypto.P256Signature
        signed :: crypto.p256_ecdsa_sign(&connection.identity.p256, digest[0..<32], extra[0..<32]) or_else none
        put_ecdsa_der(into, &writer, signed[0..<64])
    }
    else {
        signed :: crypto.ed25519_sign(&connection.identity.ed25519, range(content, 0, length))
        put_bytes(into, &writer, signed[0..<64])
    }
    end_vector(into, &writer, signature, 2)
    end_vector(into, &writer, verify_body, 3)
    send_message(connection, range(into, 0, writer.at))
    finished : u8[4 + HASH_MOST]
    finished_length :: make_finished(connection, &connection.server_secret, finished[0..<finished.count])
    send_message(connection, range(finished, 0, finished_length))
    application_secrets(connection)
    set_write_keys(connection, &connection.server_secret)
    connection.state = .WaitClientFinished
}
