package tls

import compiler from "base"
import crypto from "std"
import random from "std"

/*
 * The client's handshake (RFC 8446 §2, §4): a ClientHello offering the three suites, X25519 and P-256 (a key share for
 * X25519 only, so a server that wants P-256 asks again with a HelloRetryRequest), then the server's ServerHello,
 * EncryptedExtensions, Certificate, CertificateVerify and Finished, each checked, and the client's Finished. A server
 * asking for a certificate is given an empty one.
 */

/** The suites offered, in the order they're preferred. */
CLIENT_SUITES :: u16.[0x1301, 0x1302, 0x1303]
/** The schemes offered: those a CertificateVerify may use, then PKCS #1's for certificates. */
CLIENT_SCHEMES :: u16.[SCHEME_ECDSA_P256_SHA256, SCHEME_ECDSA_P384_SHA384, SCHEME_RSA_PSS_SHA256, SCHEME_RSA_PSS_SHA384,
    SCHEME_RSA_PSS_SHA512, SCHEME_ED25519, SCHEME_RSA_PKCS1_SHA256, SCHEME_RSA_PKCS1_SHA384, SCHEME_RSA_PKCS1_SHA512]

/**
 * Start the client's handshake: its X25519 key made, and its ClientHello queued.
 *
 * @param connection The connection, set up as a client.
 */
start_client :: fn(connection: ptr[mut Connection]) {
    bytes : u8[32]
    random.fill(bytes)
    for byte, i in bytes {
        connection.x25519[i] = byte
    }
    random.fill(connection.client_random)
    connection.group = GROUP_X25519
    connection.state = .WaitServerHello
    send_client_hello(connection)
}

/**
 * Set a connection up as a client that's sent a ClientHello it was given, made elsewhere with an X25519 key it's given
 * too, as a recorded handshake's (RFC 8448) is replayed: neither its chain nor its name is checked, and its
 * CertificateVerify may be an RSA key's of any size, as the record's is 1024 bits.
 *
 * @param connection The connection, zeroed or ended.
 * @param hello The ClientHello sent, as a handshake message; its session ID's taken from it.
 * @param x25519 The X25519 secret key its key share was made with.
 */
client_after_hello #constant_time :: fn(connection: ptr[mut Connection], hello: u8[], x25519: ptr[crypto.X25519SecretKey]) {
    reset(connection, .Client)
    connection.verify = false
    connection.small_rsa = true
    connection.x25519 = x25519^
    connection.group = GROUP_X25519
    // Its session ID: past its type, length, version and random
    reader := reader_of(hello)
    _ = get_bytes(hello, &reader, 4 + 2 + 32)
    session := get_vector(hello, &reader, 1)
    connection.session_id_length = session.end - session.at
    for i in 0..<connection.session_id_length {
        if i < connection.session_id.count && session.at + i < hello.count {
            connection.session_id[i] = hello[session.at + i]
        }
    }
    transcript_add(&connection.transcript, hello)
    connection.state = .WaitServerHello
}

/**
 * Tell whether the host's name is an IP address's text, which SNI doesn't carry (RFC 6066 §3).
 *
 * @param host The name.
 * @return True for an IPv4 address's text, or anything with a colon, as IPv6's has.
 */
is_address :: fn(host: u8[]) -> bool {
    if host.count == 0 {
        return true
    }
    all_digits_and_dots := true
    for byte in host {
        if byte == 58 {
            return true
        }
        if !(byte == 46 || (byte >= 48 && byte <= 57)) {
            all_digits_and_dots = false
        }
    }
    return all_digits_and_dots
}

/**
 * Queue the ClientHello: the first, or, after a HelloRetryRequest, the second, the same but for its key share, now
 * P-256's, and the cookie echoed.
 *
 * @param connection The connection.
 */
send_client_hello :: fn(connection: ptr[mut Connection]) {
    into :: connection.building[0..<connection.building.count]
    writer := Writer.{}
    put_u8(into, &writer, CLIENT_HELLO)
    body :: start_vector(into, &writer, 3)
    put_u16(into, &writer, LEGACY_VERSION)
    put_bytes(into, &writer, connection.client_random[0..<32])
    // No legacy session ID: middlebox compatibility mode isn't used
    put_u8(into, &writer, 0)
    suites :: start_vector(into, &writer, 2)
    for suite in CLIENT_SUITES {
        put_u16(into, &writer, suite)
    }
    end_vector(into, &writer, suites, 2)
    put_u8(into, &writer, 1)
    put_u8(into, &writer, 0)
    extensions :: start_vector(into, &writer, 2)
    host :: host_of(connection)
    if !is_address(host) {
        put_u16(into, &writer, EXTENSION_SERVER_NAME)
        server_name :: start_vector(into, &writer, 2)
        list :: start_vector(into, &writer, 2)
        put_u8(into, &writer, 0)
        name :: start_vector(into, &writer, 2)
        put_bytes(into, &writer, host)
        end_vector(into, &writer, name, 2)
        end_vector(into, &writer, list, 2)
        end_vector(into, &writer, server_name, 2)
    }
    put_u16(into, &writer, EXTENSION_SUPPORTED_GROUPS)
    groups :: start_vector(into, &writer, 2)
    groups_list :: start_vector(into, &writer, 2)
    put_u16(into, &writer, GROUP_X25519)
    put_u16(into, &writer, GROUP_P256)
    end_vector(into, &writer, groups_list, 2)
    end_vector(into, &writer, groups, 2)
    put_u16(into, &writer, EXTENSION_SIGNATURE_ALGORITHMS)
    schemes :: start_vector(into, &writer, 2)
    schemes_list :: start_vector(into, &writer, 2)
    for scheme in CLIENT_SCHEMES {
        put_u16(into, &writer, scheme)
    }
    end_vector(into, &writer, schemes_list, 2)
    end_vector(into, &writer, schemes, 2)
    put_u16(into, &writer, EXTENSION_SUPPORTED_VERSIONS)
    versions :: start_vector(into, &writer, 2)
    put_u8(into, &writer, 2)
    put_u16(into, &writer, VERSION_13)
    end_vector(into, &writer, versions, 2)
    if connection.cookie_length > 0 {
        put_u16(into, &writer, EXTENSION_COOKIE)
        cookie :: start_vector(into, &writer, 2)
        cookie_value :: start_vector(into, &writer, 2)
        put_bytes(into, &writer, range(connection.cookie, 0, connection.cookie_length))
        end_vector(into, &writer, cookie_value, 2)
        end_vector(into, &writer, cookie, 2)
    }
    put_u16(into, &writer, EXTENSION_KEY_SHARE)
    share :: start_vector(into, &writer, 2)
    shares :: start_vector(into, &writer, 2)
    put_u16(into, &writer, connection.group)
    key :: start_vector(into, &writer, 2)
    if connection.group == GROUP_X25519 {
        public :: crypto.x25519_public_key(&connection.x25519)
        put_bytes(into, &writer, public[0..<32])
    }
    else {
        public : crypto.P256PublicKey
        _ = crypto.p256_public_key(&connection.p256, &public)
        put_bytes(into, &writer, public[0..<65])
    }
    end_vector(into, &writer, key, 2)
    end_vector(into, &writer, shares, 2)
    end_vector(into, &writer, share, 2)
    end_vector(into, &writer, extensions, 2)
    end_vector(into, &writer, body, 3)
    if writer.overflow {
        fail(connection, ALERT_INTERNAL_ERROR)
        return void
    }
    send_message(connection, range(into, 0, writer.at))
}

/**
 * Act on a handshake message from the server, as the client's state allows.
 *
 * @param connection The connection, a client's.
 * @param kind The message's type.
 * @param message The message, with its header.
 */
client_message :: fn(connection: ptr[mut Connection], kind: u8, message: u8[]) {
    if connection.state == .WaitServerHello && kind == SERVER_HELLO {
        take_server_hello(connection, message)
    }
    else if connection.state == .WaitEncryptedExtensions && kind == ENCRYPTED_EXTENSIONS {
        reader := reader_of(message)
        _ = get_bytes(message, &reader, 4)
        extensions := get_vector(message, &reader, 2)
        if !done(&reader) {
            fail(connection, ALERT_DECODE_ERROR)
            return void
        }
        transcript_add(&connection.transcript, message)
        connection.state = .WaitCertificate
    }
    else if connection.state == .WaitCertificate && kind == CERTIFICATE_REQUEST && !connection.certificate_requested {
        reader := reader_of(message)
        _ = get_bytes(message, &reader, 4)
        context := get_vector(message, &reader, 1)
        connection.request_context_length = context.end - context.at
        for i in 0..<connection.request_context_length {
            if i < connection.request_context.count && context.at + i < message.count {
                connection.request_context[i] = message[context.at + i]
            }
        }
        _ = get_vector(message, &reader, 2)
        if !done(&reader) {
            fail(connection, ALERT_DECODE_ERROR)
            return void
        }
        connection.certificate_requested = true
        transcript_add(&connection.transcript, message)
    }
    else if connection.state == .WaitCertificate && kind == CERTIFICATE {
        take_certificate(connection, message)
    }
    else if connection.state == .WaitCertificateVerify && kind == CERTIFICATE_VERIFY {
        take_certificate_verify(connection, message)
    }
    else if connection.state == .WaitServerFinished && kind == FINISHED {
        take_server_finished(connection, message)
    }
    else if connection.state == .Connected && kind == NEW_SESSION_TICKET {
        // Resumption isn't done: a ticket's passed over
    }
    else if connection.state == .Connected && kind == KEY_UPDATE {
        take_key_update(connection, message)
    }
    else {
        fail(connection, ALERT_UNEXPECTED_MESSAGE)
    }
}

/**
 * Take a ServerHello or a HelloRetryRequest.
 *
 * @param connection The connection.
 * @param message The message.
 */
take_server_hello :: fn(connection: ptr[mut Connection], message: u8[]) {
    reader := reader_of(message)
    _ = get_bytes(message, &reader, 4)
    version :: get_u16(message, &reader)
    server_random :: get_bytes(message, &reader, 32)
    session := get_vector(message, &reader, 1)
    suite :: get_u16(message, &reader)
    compression :: get_u8(message, &reader)
    extensions := get_vector(message, &reader, 2)
    if !done(&reader) || version != LEGACY_VERSION || compression != 0 {
        fail(connection, if reader.bad { ALERT_DECODE_ERROR } else { ALERT_ILLEGAL_PARAMETER })
        return void
    }
    // Its session ID echoes the ClientHello's
    if session.end - session.at != connection.session_id_length {
        fail(connection, ALERT_ILLEGAL_PARAMETER)
        return void
    }
    for i in 0..<connection.session_id_length {
        if i < connection.session_id.count && session.at + i < message.count && message[session.at + i] != connection.session_id[i] {
            fail(connection, ALERT_ILLEGAL_PARAMETER)
            return void
        }
    }
    chosen :: if suite == 0x1301 { Suite.Aes128GcmSha256 } else if suite == 0x1302 { Suite.Aes256GcmSha384 }
        else if suite == 0x1303 { Suite.Chacha20Poly1305Sha256 } else { Suite.None }
    if chosen == .None || (connection.retried && chosen != connection.suite) {
        fail(connection, ALERT_ILLEGAL_PARAMETER)
        return void
    }
    retry := server_random.count == 32
    for byte, i in server_random {
        retry = retry && i < RETRY_RANDOM.count && byte == RETRY_RANDOM[i]
    }
    tls13 := false
    group := cast[u16](0)
    share_at := cast[usize](0)
    share_length := cast[usize](0)
    loop {
        if extensions.at >= extensions.end || extensions.bad {
            break
        }
        kind :: get_u16(message, &extensions)
        data := get_vector(message, &extensions, 2)
        if kind == EXTENSION_SUPPORTED_VERSIONS {
            tls13 = get_u16(message, &data) == VERSION_13 && done(&data)
        }
        else if kind == EXTENSION_KEY_SHARE {
            group = get_u16(message, &data)
            if !retry {
                key := get_vector(message, &data, 2)
                share_at = key.at
                share_length = key.end - key.at
            }
            if !done(&data) {
                fail(connection, ALERT_DECODE_ERROR)
                return void
            }
        }
        else if kind == EXTENSION_COOKIE && retry {
            cookie := get_vector(message, &data, 2)
            connection.cookie_length = cookie.end - cookie.at
            if connection.cookie_length == 0 || connection.cookie_length > connection.cookie.count {
                fail(connection, ALERT_ILLEGAL_PARAMETER)
                return void
            }
            for byte, i in range(message, cookie.at, cookie.end) {
                if i < connection.cookie.count {
                    connection.cookie[i] = byte
                }
            }
        }
    }
    while true
    if extensions.bad || !tls13 {
        fail(connection, if extensions.bad { ALERT_DECODE_ERROR } else { ALERT_PROTOCOL_VERSION })
        return void
    }
    connection.suite = chosen
    if retry {
        // Only once, and only for the group whose share wasn't sent
        if connection.retried || group != GROUP_P256 {
            fail(connection, ALERT_ILLEGAL_PARAMETER)
            return void
        }
        first : u8[HASH_MOST]
        transcript_hash(&connection.transcript, suite_hash(chosen), &first)
        restart_transcript(connection, &first)
        transcript_add(&connection.transcript, message)
        connection.retried = true
        connection.group = GROUP_P256
        make_p256_key(connection)
        send_client_hello(connection)
        return void
    }
    if group != connection.group || share_at + share_length > message.count {
        fail(connection, ALERT_ILLEGAL_PARAMETER)
        return void
    }
    transcript_add(&connection.transcript, message)
    shared : crypto.SecretByte[32]
    agreed := false
    if group == GROUP_X25519 && share_length == 32 {
        public : crypto.X25519PublicKey
        for byte, i in range(message, share_at, share_at + 32) {
            if i < 32 {
                public[i] = byte
            }
        }
        agreed = crypto.x25519(&connection.x25519, &public, &shared)
    }
    else if group == GROUP_P256 && share_length == 65 {
        agreed = crypto.p256_ecdh(&connection.p256, range(message, share_at, share_at + 65), &shared)
    }
    if !agreed {
        fail(connection, ALERT_ILLEGAL_PARAMETER)
        return void
    }
    handshake_secrets(connection, &shared)
    connection.client_handshake_secret = connection.client_secret
    set_read_keys(connection, &connection.server_secret)
    set_write_keys(connection, &connection.client_secret)
    connection.state = .WaitEncryptedExtensions
}

/**
 * Make a P-256 secret key from random bytes, drawn again in the rare case they aren't one.
 *
 * @param connection The connection, whose p256 is set.
 */
make_p256_key :: fn(connection: ptr[mut Connection]) {
    for attempt in 0..<8 {
        bytes : u8[32]
        random.fill(bytes)
        for byte, i in bytes {
            connection.p256[i] = byte
        }
        public : crypto.P256PublicKey
        if crypto.p256_public_key(&connection.p256, &public) {
            return void
        }
    }
}

/**
 * Give the alert a chain's verdict calls for.
 *
 * @param verdict Why it isn't valid.
 * @return The alert's description.
 */
alert_for :: fn(verdict: crypto.X509Verdict) -> u8 {
    return match verdict {
        case .EXPIRED => ALERT_CERTIFICATE_EXPIRED
        case .UNKNOWN_ISSUER => ALERT_UNKNOWN_CA
        case .UNSUPPORTED => ALERT_UNSUPPORTED_CERTIFICATE
        case .MALFORMED => ALERT_BAD_CERTIFICATE
        case .BAD_CHAIN => ALERT_BAD_CERTIFICATE
        case .BAD_SIGNATURE => ALERT_BAD_CERTIFICATE
        case _ => ALERT_CERTIFICATE_UNKNOWN
    }
}

/**
 * Take the server's Certificate: its chain gathered, validated against the anchors and the leaf's name checked against
 * the host's (unless unverified), and the leaf's key kept for the CertificateVerify.
 *
 * @param connection The connection.
 * @param message The message.
 */
take_certificate :: fn(connection: ptr[mut Connection], message: u8[]) {
    reader := reader_of(message)
    _ = get_bytes(message, &reader, 4)
    context := get_vector(message, &reader, 1)
    list := get_vector(message, &reader, 3)
    if !done(&reader) || context.end != context.at {
        fail(connection, if reader.bad { ALERT_DECODE_ERROR } else { ALERT_ILLEGAL_PARAMETER })
        return void
    }
    // The chain's DER, one after another, where the client builds nothing meanwhile
    chain :: connection.building[0..<connection.building.count]
    writer := Writer.{}
    leaf_at := cast[usize](0)
    leaf_length := cast[usize](0)
    count := cast[usize](0)
    loop {
        if list.at >= list.end || list.bad {
            break
        }
        data := get_vector(message, &list, 3)
        _ = get_vector(message, &list, 2)
        if count == 0 {
            leaf_at = writer.at
            leaf_length = data.end - data.at
        }
        put_bytes(chain, &writer, get_bytes(message, &data, data.end - data.at))
        count += 1
    }
    while true
    if list.bad || writer.overflow || count == 0 || leaf_at + leaf_length > chain.count {
        fail(connection, if count == 0 { ALERT_BAD_CERTIFICATE } else { ALERT_DECODE_ERROR })
        return void
    }
    leaf :: crypto.x509_parse(range(chain, leaf_at, leaf_at + leaf_length)) or_else crypto.X509Certificate.{}
    if leaf.der.count == 0 {
        fail(connection, ALERT_BAD_CERTIFICATE)
        return void
    }
    if connection.verify {
        anchors :: view_of(cast[ptr[u8]](cast[uintptr](connection.anchors)), connection.anchors_bytes)
        verdict :: crypto.x509_verify_chain(range(chain, 0, writer.at), anchors, connection.now, .SERVER)
        if verdict != .VALID {
            connection.certificate = verdict
            fail(connection, alert_for(verdict))
            return void
        }
        host :: host_of(connection)
        if host.count == 0 || !crypto.x509_matches_host(&leaf, string_of(&host[0], host.count)) {
            connection.wrong_name = true
            fail(connection, ALERT_BAD_CERTIFICATE)
            return void
        }
    }
    if leaf.key.count > connection.peer_key.count || leaf.key_kind == .UNSUPPORTED {
        fail(connection, ALERT_UNSUPPORTED_CERTIFICATE)
        return void
    }
    connection.peer_kind = leaf.key_kind
    connection.peer_key_length = leaf.key.count
    for byte, i in leaf.key {
        if i < connection.peer_key.count {
            connection.peer_key[i] = byte
        }
    }
    transcript_add(&connection.transcript, message)
    connection.state = .WaitCertificateVerify
}

/**
 * Give the algorithm a CertificateVerify's scheme verifies with, if it goes with the kind of key (§4.2.3).
 *
 * @param scheme The scheme.
 * @param kind The leaf's kind of key.
 * @param salt Where RSA-PSS's salt length goes: its hash's length.
 * @return The algorithm; null if the scheme isn't one a CertificateVerify may use with that key.
 */
scheme_algorithm :: fn(scheme: u16, kind: crypto.X509KeyKind, salt: ptr[mut usize]) -> crypto.X509Signature? {
    if scheme == SCHEME_ECDSA_P256_SHA256 && kind == .P256 {
        return crypto.X509Signature.ECDSA_SHA256
    }
    if scheme == SCHEME_ECDSA_P384_SHA384 && kind == .P384 {
        return crypto.X509Signature.ECDSA_SHA384
    }
    if scheme == SCHEME_ED25519 && kind == .ED25519 {
        return crypto.X509Signature.ED25519
    }
    if kind == .RSA {
        if scheme == SCHEME_RSA_PSS_SHA256 {
            salt^ = 32
            return crypto.X509Signature.RSA_PSS_SHA256
        }
        if scheme == SCHEME_RSA_PSS_SHA384 {
            salt^ = 48
            return crypto.X509Signature.RSA_PSS_SHA384
        }
        if scheme == SCHEME_RSA_PSS_SHA512 {
            salt^ = 64
            return crypto.X509Signature.RSA_PSS_SHA512
        }
    }
    return null
}

/**
 * Take the server's CertificateVerify: its signature, with the leaf's key, over the transcript so far.
 *
 * @param connection The connection.
 * @param message The message.
 */
take_certificate_verify :: fn(connection: ptr[mut Connection], message: u8[]) {
    reader := reader_of(message)
    _ = get_bytes(message, &reader, 4)
    scheme :: get_u16(message, &reader)
    signature := get_vector(message, &reader, 2)
    if !done(&reader) {
        fail(connection, ALERT_DECODE_ERROR)
        return void
    }
    salt := cast[usize](0)
    algorithm :: scheme_algorithm(scheme, connection.peer_kind, &salt) or_else crypto.X509Signature.ECDSA_SHA512
    known :: scheme_algorithm(scheme, connection.peer_kind, &salt) is_some
    if !known {
        fail(connection, ALERT_ILLEGAL_PARAMETER)
        return void
    }
    content : u8[64 + 34 + HASH_MOST]
    length :: verify_content(connection, true, content[0..<content.count])
    key :: range(connection.peer_key, 0, connection.peer_key_length)
    signed :: range(message, signature.at, signature.end)
    verdict := crypto.x509_verify_signature(connection.peer_kind, key, algorithm, salt, range(content, 0, length), signed)
    if verdict == .UNSUPPORTED && connection.small_rsa && connection.peer_kind == .RSA {
        verdict = small_rsa_verdict(key, algorithm, salt, range(content, 0, length), signed)
    }
    if verdict != .VALID {
        fail(connection, ALERT_DECRYPT_ERROR)
        return void
    }
    transcript_add(&connection.transcript, message)
    connection.state = .WaitServerFinished
}

/**
 * Check an RSA-PSS signature with a key of any size, for a recorded handshake replayed (small_rsa).
 *
 * @param key The key, as PKCS #1's RSAPublicKey.
 * @param algorithm RSA_PSS_SHA256, RSA_PSS_SHA384 or RSA_PSS_SHA512.
 * @param salt The salt's length.
 * @param content What's signed.
 * @param signature The signature.
 * @return VALID or BAD_SIGNATURE; UNSUPPORTED for another algorithm or a key that isn't read.
 */
small_rsa_verdict :: fn(key: u8[], algorithm: crypto.X509Signature, salt: usize, content: u8[], signature: u8[]) -> crypto.X509Verdict {
    public :: crypto.rsa_public_key_from_der(key) or_return .UNSUPPORTED
    hash :: if algorithm == .RSA_PSS_SHA256 { crypto.RsaHash.SHA256 } else if algorithm == .RSA_PSS_SHA384 { crypto.RsaHash.SHA384 }
        else if algorithm == .RSA_PSS_SHA512 { crypto.RsaHash.SHA512 } else { return .UNSUPPORTED }
    digest : u8[64]
    crypto.rsa_hash_parts(hash, content, content[0..<0], content[0..<0], &digest)
    size :: crypto.rsa_hash_size(hash)
    return if crypto.rsa_pss_verify(&public, hash, range(digest, 0, size), signature, salt) { crypto.X509Verdict.VALID }
        else { crypto.X509Verdict.BAD_SIGNATURE }
}

/**
 * Take the server's Finished, then send the client's: an empty Certificate first if one was asked for, and move to the
 * application traffic keys.
 *
 * @param connection The connection.
 * @param message The message.
 */
take_server_finished :: fn(connection: ptr[mut Connection], message: u8[]) {
    if !check_finished(connection, &connection.server_secret, message) {
        fail(connection, ALERT_DECRYPT_ERROR)
        return void
    }
    transcript_add(&connection.transcript, message)
    application_secrets(connection)
    set_read_keys(connection, &connection.server_secret)
    if connection.certificate_requested {
        into :: connection.building[0..<connection.building.count]
        writer := Writer.{}
        put_u8(into, &writer, CERTIFICATE)
        body :: start_vector(into, &writer, 3)
        context :: start_vector(into, &writer, 1)
        put_bytes(into, &writer, range(connection.request_context, 0, connection.request_context_length))
        end_vector(into, &writer, context, 1)
        put_u24(into, &writer, 0)
        end_vector(into, &writer, body, 3)
        send_message(connection, range(into, 0, writer.at))
    }
    finished : u8[4 + HASH_MOST]
    length :: make_finished(connection, &connection.client_handshake_secret, finished[0..<finished.count])
    send_message(connection, range(finished, 0, length))
    set_write_keys(connection, &connection.client_secret)
    connection.state = .Connected
}
