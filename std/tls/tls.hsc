package tls

import compiler from "base"
import crypto from "std"

/*
 * A TLS connection: its state, the records that arrive and leave, and what the caller reads and writes. The handshake's
 * messages are the client's (client.hsc) and the server's (server.hsc); the key schedule is schedule.hsc's.
 *
 *     connection :: runtime.new(tls.Connection)
 *     tls.client(connection, "example.com", anchors, now)
 *     loop {
 *         send(tls.output(connection))            // what's to go out, then tls.sent(connection, count)
 *         tls.received(connection, arrived)       // what came in
 *     } while !tls.connected(connection) && !tls.ended(connection)
 *     _ = tls.write(connection, request)
 */

// ---- Sizes

/** The most plaintext a record carries (RFC 8446 §5.1). */
RECORD_PLAINTEXT :: 16384
/** The most ciphertext a record carries: its plaintext, its content type, padding and the tag (§5.2). */
RECORD_CIPHERTEXT :: 16384 + 256
/** A record's header: its type, legacy version and length. */
RECORD_HEADER :: 5
/** What arrives waiting to be taken: room for two of the largest records. */
INCOMING_BYTES :: 2 * (RECORD_HEADER + RECORD_CIPHERTEXT)
/** What waits to be sent: room for a server's first flight with a long chain, in several records. */
OUTGOING_BYTES :: 98304
/** The largest handshake message taken, with its header: room for a long certificate chain. */
MESSAGE_BYTES :: 65536 + 4
/** The most plaintext waiting to be read. */
PLAINTEXT_BYTES :: RECORD_PLAINTEXT
/** The longest host name kept, for SNI and the certificate's check. */
HOST_BYTES :: 255
/** The most bytes of the peer's leaf key kept: an RSA key of 8192 bits, as DER. */
KEY_BYTES :: 1100

// ---- Wire values

/** Records' content types (RFC 8446 §5.1). */
CONTENT_CHANGE_CIPHER_SPEC : u8 : 20
CONTENT_ALERT : u8 : 21
CONTENT_HANDSHAKE : u8 : 22
CONTENT_APPLICATION_DATA : u8 : 23

/** Handshake messages' types (§4). */
CLIENT_HELLO : u8 : 1
SERVER_HELLO : u8 : 2
NEW_SESSION_TICKET : u8 : 4
ENCRYPTED_EXTENSIONS : u8 : 8
CERTIFICATE : u8 : 11
CERTIFICATE_REQUEST : u8 : 13
CERTIFICATE_VERIFY : u8 : 15
FINISHED : u8 : 20
KEY_UPDATE : u8 : 24
MESSAGE_HASH : u8 : 254

/** Extensions (§4.2). */
EXTENSION_SERVER_NAME : u16 : 0
EXTENSION_SUPPORTED_GROUPS : u16 : 10
EXTENSION_SIGNATURE_ALGORITHMS : u16 : 13
EXTENSION_SUPPORTED_VERSIONS : u16 : 43
EXTENSION_COOKIE : u16 : 44
EXTENSION_KEY_SHARE : u16 : 51
/** Application-Layer Protocol Negotiation (RFC 7301). */
EXTENSION_ALPN : u16 : 16

/** TLS 1.3's version, and the legacy one records and hellos say. */
VERSION_13 : u16 : 0x0304
LEGACY_VERSION : u16 : 0x0303

/** The groups (§4.2.7). */
GROUP_X25519 : u16 : 0x001d
GROUP_P256 : u16 : 0x0017

/** The signature schemes (§4.2.3). */
SCHEME_ECDSA_P256_SHA256 : u16 : 0x0403
SCHEME_ECDSA_P384_SHA384 : u16 : 0x0503
SCHEME_RSA_PSS_SHA256 : u16 : 0x0804
SCHEME_RSA_PSS_SHA384 : u16 : 0x0805
SCHEME_RSA_PSS_SHA512 : u16 : 0x0806
SCHEME_ED25519 : u16 : 0x0807
/** PKCS #1 v1.5's, offered for certificates' signatures only, never a CertificateVerify's. */
SCHEME_RSA_PKCS1_SHA256 : u16 : 0x0401
SCHEME_RSA_PKCS1_SHA384 : u16 : 0x0501
SCHEME_RSA_PKCS1_SHA512 : u16 : 0x0601

/** Alerts' descriptions (§6). */
ALERT_CLOSE_NOTIFY : u8 : 0
ALERT_UNEXPECTED_MESSAGE : u8 : 10
ALERT_BAD_RECORD_MAC : u8 : 20
ALERT_RECORD_OVERFLOW : u8 : 22
ALERT_HANDSHAKE_FAILURE : u8 : 40
ALERT_BAD_CERTIFICATE : u8 : 42
ALERT_UNSUPPORTED_CERTIFICATE : u8 : 43
ALERT_CERTIFICATE_EXPIRED : u8 : 45
ALERT_CERTIFICATE_UNKNOWN : u8 : 46
ALERT_ILLEGAL_PARAMETER : u8 : 47
ALERT_UNKNOWN_CA : u8 : 48
ALERT_DECODE_ERROR : u8 : 50
ALERT_DECRYPT_ERROR : u8 : 51
ALERT_PROTOCOL_VERSION : u8 : 70
ALERT_INTERNAL_ERROR : u8 : 80
ALERT_USER_CANCELED : u8 : 90
ALERT_MISSING_EXTENSION : u8 : 109
ALERT_UNSUPPORTED_EXTENSION : u8 : 110
ALERT_NO_APPLICATION_PROTOCOL : u8 : 120

/** The longest application protocol's name ALPN offers or takes: RFC 7301 allows 255, names in use are short. */
PROTOCOL_BYTES :: 64

/** ServerHello's random when it's a HelloRetryRequest: SHA-256 of "HelloRetryRequest" (§4.1.3). */
RETRY_RANDOM :: u8.[0xcf, 0x21, 0xad, 0x74, 0xe5, 0x9a, 0x61, 0x11, 0xbe, 0x1d, 0x8c, 0x02, 0x1e, 0x65, 0xb8, 0x91,
    0xc2, 0xa2, 0x11, 0x16, 0x7a, 0xbb, 0x8c, 0x5e, 0x07, 0x9e, 0x09, 0xe2, 0xc8, 0xa8, 0x33, 0x9c]

// ---- What a connection is

/** The cipher suites (§B.4). */
Suite :: enum #backed_by(u16) {
    None = 0,
    Aes128GcmSha256 = 0x1301,
    Aes256GcmSha384 = 0x1302,
    Chacha20Poly1305Sha256 = 0x1303,
}

/**
 * Give a suite's hash.
 *
 * @param suite The suite.
 * @return SHA-384 for AES-256-GCM's, SHA-256 for the others.
 */
suite_hash :: fn(suite: Suite) -> Hash {
    return if suite == .Aes256GcmSha384 { Hash.Sha384 } else { Hash.Sha256 }
}

/**
 * Give a suite's key length.
 *
 * @param suite The suite.
 * @return 16 for AES-128-GCM's, 32 for the others.
 */
key_length :: fn(suite: Suite) -> usize {
    return if suite == .Aes128GcmSha256 { cast[usize](16) } else { cast[usize](32) }
}

/** Which side a connection is. */
Role :: enum {
    Client,
    Server,
}

/** Where a connection's handshake is. */
State :: enum {
    /** Not started: neither client nor server has set it up. */
    Idle,
    /** A client waiting for the ServerHello, or a HelloRetryRequest's. */
    WaitServerHello,
    /** A client waiting for the EncryptedExtensions. */
    WaitEncryptedExtensions,
    /** A client waiting for a CertificateRequest or the server's Certificate. */
    WaitCertificate,
    /** A client waiting for the server's CertificateVerify. */
    WaitCertificateVerify,
    /** A client waiting for the server's Finished. */
    WaitServerFinished,
    /** A server waiting for the ClientHello, or the second after its HelloRetryRequest. */
    WaitClientHello,
    /** A server waiting for the client's Finished. */
    WaitClientFinished,
    /** Connected: application data goes both ways. */
    Connected,
    /** Ended: closed or failed, as ending says. */
    Ended,
}

/** How a connection ended. */
Ending :: enum {
    /** It hasn't. */
    None,
    /** The peer closed it with close_notify. */
    Closed,
    /** The peer sent an alert; alert says which. */
    PeerAlert,
    /** This side found something wrong, and sent an alert; alert says which, and certificate why, for a certificate. */
    Refused,
    /** The caller closed it. */
    LocalClose,
}

/** What a server proves itself with: its certificate chain and the leaf's key, which is secret by its type. */
Identity :: struct {
    /** The chain: DER certificates one after another, the leaf first. */
    chain : rawptr,
    chain_bytes : usize,
    /** The leaf's kind of key: P256 or ED25519. */
    kind : crypto.X509KeyKind,
    /** Its key, P-256's or Ed25519's, as kind says. */
    p256 : crypto.P256SecretKey,
    ed25519 : crypto.Ed25519SecretKey,
}

/**
 * Make an identity from a chain and its leaf's key.
 *
 * @param kind The leaf's kind of key: P256 or ED25519.
 * @param chain The chain, DER certificates one after another, the leaf first; the caller's, unchanged and in place for as
 *     long as a connection serves with the identity, as the identity points at it rather than copying it.
 * @param key The leaf's secret key, 32 bytes: P-256's scalar, big-endian, or Ed25519's seed. Fewer leave the rest zero.
 * @return The identity.
 */
identity_of #constant_time :: fn(kind: crypto.X509KeyKind, chain: u8[], key: u8[]) -> Identity {
    made := Identity.{kind = kind, chain_bytes = chain.count}
    if chain.count > 0 {
        made.chain = cast[rawptr](&chain[0])
    }
    for byte, i in key {
        if i < 32 {
            made.p256[i] = byte
            made.ed25519[i] = byte
        }
    }
    return made
}

/** A TLS connection:the caller's, zeroed or ended, before client or server; some 300 KiB, so on the heap. */
Connection :: struct {
    role : Role,
    state : State,
    ending : Ending,
    /** The alert that ended it, sent or received. */
    alert : u8,
    /** For a certificate refused: why, as validating found. */
    certificate : crypto.X509Verdict,
    /** For a certificate refused: whether it was its name that didn't match. */
    wrong_name : bool,

    // What it's set up with
    /** The host's name, its first host_length bytes: the client's SNI, checked against the certificate. */
    host : u8[HOST_BYTES],
    host_length : usize,
    /** Whether the server's chain and name are checked: false only through client_unverified. */
    verify : bool,
    /**
     * The trust anchors, DER certificates one after another, the caller's for the connection's life: their address, kept
     * as a number, as the connection outlives the call it's given in.
     */
    anchors : u64,
    anchors_bytes : usize,
    /** The time certificates are checked at, in seconds since 1970 UTC. */
    now : i64,
    /** A server's identity. */
    identity : Identity,
    /** A server's only suite, or None for any; and its only group, or 0 for either. */
    only_suite : Suite,
    only_group : u16,
    /** The application protocol, by ALPN: the one a client offers, or a server speaks; protocol_length 0 for none. */
    protocol : u8[PROTOCOL_BYTES],
    protocol_length : usize,
    /** Whether both sides agreed on it: the server echoed the client's, or took it. */
    protocol_agreed : bool,

    // The handshake
    suite : Suite,
    transcript : Transcript,
    /** The groups' secret keys made, and which has a share sent: the first ClientHello's X25519, a retry's P-256. */
    x25519 : crypto.X25519SecretKey,
    p256 : crypto.P256SecretKey,
    group : u16,
    /** Whether a HelloRetryRequest's been sent or taken. */
    retried : bool,
    /** A HelloRetryRequest's cookie, echoed in the second ClientHello. */
    cookie : u8[512],
    cookie_length : usize,
    /** The ClientHello's legacy_session_id, echoed by the server. */
    session_id : u8[32],
    session_id_length : usize,
    /** Whether the server asked for the client's certificate, and the context it gave. */
    certificate_requested : bool,
    request_context : u8[255],
    request_context_length : usize,
    /** The scheme the server signs its CertificateVerify with, as the client's signature_algorithms allow. */
    scheme : u16,
    /** The peer's leaf key, as X509Certificate.key holds it, its first key_length bytes. */
    peer_kind : crypto.X509KeyKind,
    peer_key : u8[KEY_BYTES],
    peer_key_length : usize,
    /** The hellos' randoms. */
    client_random : u8[32],
    server_random : u8[32],
    /** Whether a server's random and X25519 key were given (server_with_keys), rather than drawn. */
    fixed_keys : bool,
    /**
     * Whether an RSA key under crypto.X509_FEWEST_RSA_BITS is taken for a CertificateVerify: only for a recorded
     * handshake replayed (client_after_hello), as RFC 8448's key is 1024 bits.
     */
    small_rsa : bool,
    handshake_secret : Secret,
    master_secret : Secret,
    /** exporter_master_secret (RFC 8446 §7.5), which export_keying_material derives from. */
    exporter_secret : Secret,
    /** Whether the handshake finished, so exporter_secret is the connection's, even once it's closed. */
    handshake_done : bool,
    /** The client's handshake traffic secret, kept past the application secrets' replacing client_secret. */
    client_handshake_secret : Secret,
    client_secret : Secret,
    server_secret : Secret,

    // Records
    read : TrafficKeys,
    write : TrafficKeys,
    read_encrypted : bool,
    write_encrypted : bool,
    /** How many times the keys read with have changed, so a message spanning a change is found. */
    read_changes : u64,
    /** The traffic secrets read and written with, for KeyUpdate. */
    read_secret : Secret,
    write_secret : Secret,
    incoming : u8[INCOMING_BYTES],
    incoming_count : usize,
    outgoing : u8[OUTGOING_BYTES],
    outgoing_count : usize,
    message : u8[MESSAGE_BYTES],
    message_count : usize,
    plaintext : u8[PLAINTEXT_BYTES],
    plaintext_start : usize,
    plaintext_count : usize,
    /** Where a record's inner plaintext is built and opened. */
    inner : u8[RECORD_PLAINTEXT + 1],
    opened : crypto.SecretByte[RECORD_CIPHERTEXT],
    /** Where a handshake message this side sends is built. */
    building : u8[MESSAGE_BYTES],
    /** Whether close_notify's been sent. */
    closed_sent : bool,
}

// ---- What the caller does

/**
 * Set a connection up as a client of a host, its certificate checked, and queue its ClientHello.
 *
 * @param connection The connection, zeroed or ended.
 * @param host The server's DNS name, sent as SNI, which its certificate has to match; or an IP address's text, which
 *     isn't sent but is matched. At most HOST_BYTES.
 * @param anchors The trust anchors: DER certificates one after another (crypto.pem_certificates makes them from PEM),
 *     the caller's, unchanged, for the connection's life.
 * @param now The time to check certificates at, in seconds since 1970 UTC.
 * @param protocol The application protocol offered by ALPN (RFC 7301), at most PROTOCOL_BYTES, like "ntske/1"; empty for
 *     none. A server that takes another is refused; one that answers none is talked to, and protocol_agreed says so.
 */
client :: fn(connection: ptr[mut Connection], host: string, anchors: u8[], now: i64, protocol: string = "") {
    reset(connection, .Client)
    set_host(connection, host)
    set_protocol(connection, protocol)
    connection.verify = true
    connection.anchors = cast[u64](cast[uintptr](anchors.data))
    connection.anchors_bytes = anchors.count
    connection.now = now
    start_client(connection)
}

/**
 * Set a connection up as a client that doesn't check the server's certificate chain nor its name, and queue its
 * ClientHello. The server's CertificateVerify and Finished are still checked, so it's talking to whoever holds the
 * certificate's key, whoever that is: for tests, and a peer known some other way.
 *
 * @param connection The connection, zeroed or ended.
 * @param host The name sent as SNI; may be empty, when none is sent.
 * @param protocol The application protocol offered by ALPN, as client takes it; empty for none.
 */
client_unverified :: fn(connection: ptr[mut Connection], host: string, protocol: string = "") {
    reset(connection, .Client)
    set_host(connection, host)
    set_protocol(connection, protocol)
    connection.verify = false
    start_client(connection)
}

/**
 * Set a connection up as a server, waiting for a ClientHello.
 *
 * @param connection The connection, zeroed or ended.
 * @param identity The server's chain and key; its chain's bytes are the caller's, unchanged, for the connection's life.
 * @param only_suite The one suite it takes, or None for any of the three, the client's first offered.
 * @param only_group The one group it takes, GROUP_X25519 or GROUP_P256, asking for it with a HelloRetryRequest if the
 *     client's key share is another's; or 0 for either, X25519 first.
 * @param protocol The application protocol it speaks, by ALPN, at most PROTOCOL_BYTES; empty for none. A client that
 *     offers others but not it is refused with no_application_protocol; one that offers none is served, and
 *     protocol_agreed says so.
 */
server :: fn(connection: ptr[mut Connection], identity: ptr[Identity], only_suite: Suite = .None, only_group: u16 = 0,
    protocol: string = "") {
    reset(connection, .Server)
    set_protocol(connection, protocol)
    connection.identity = identity^
    connection.only_suite = only_suite
    connection.only_group = only_group
    connection.state = .WaitClientHello
}

/**
 * Move the keys written with on (RFC 8446 §4.6.3): a KeyUpdate sent with the keys now, and the next keys after it.
 *
 * @param connection The connection, connected.
 * @param ask Whether the peer's asked to move its own on too, which it then does with a KeyUpdate of its own.
 */
update_keys :: fn(connection: ptr[mut Connection], ask: bool) {
    if connection.state != .Connected || connection.closed_sent {
        return void
    }
    update :: u8.[KEY_UPDATE, 0, 0, 1, if ask { cast[u8](1) } else { cast[u8](0) }]
    write_record(connection, CONTENT_HANDSHAKE, update[0..<5])
    next := next_traffic_secret(suite_hash(connection.suite), &connection.write_secret)
    set_write_keys(connection, &next)
}

/**
 * Take bytes that arrived, as many as there's room for, and act on every whole record among them.
 *
 * @param connection The connection.
 * @param bytes What arrived from the peer.
 * @return How many were taken; the rest are to be given again later, after output's sent or plaintext's read.
 */
received :: fn(connection: ptr[mut Connection], bytes: u8[]) -> usize {
    room :: connection.incoming.count - connection.incoming_count
    taken :: if bytes.count < room { bytes.count } else { room }
    for byte, i in range(bytes, 0, taken) {
        at :: connection.incoming_count + i
        if at < connection.incoming.count {
            connection.incoming[at] = byte
        }
    }
    connection.incoming_count += taken
    take_records(connection)
    return taken
}

/**
 * Give what's waiting to be sent to the peer.
 *
 * @param connection The connection.
 * @return The bytes, a view of the connection's, good until it's next used; empty when there's nothing.
 */
output :: fn(connection: ptr[Connection]) -> u8[] {
    return range(connection.outgoing, 0, connection.outgoing_count)
}

/**
 * Say how much of output's been sent, which is dropped from it.
 *
 * @param connection The connection.
 * @param count How many bytes, at most output's count.
 */
sent :: fn(connection: ptr[mut Connection], count: usize) {
    taken :: if count < connection.outgoing_count { count } else { connection.outgoing_count }
    remove_front(&connection.outgoing, &connection.outgoing_count, taken)
}

/**
 * Tell whether the handshake's done, so application data goes both ways.
 *
 * @param connection The connection.
 * @return True once connected, until it ends.
 */
connected :: fn(connection: ptr[Connection]) -> bool {
    return connection.state == .Connected
}

/**
 * Tell whether the two sides agreed on the application protocol by ALPN: the one this side offered or speaks.
 *
 * @param connection The connection, connected.
 * @return True if they did; false if the peer offered or answered none, or neither side gave one.
 */
protocol_agreed :: fn(connection: ptr[Connection]) -> bool {
    return connection.protocol_agreed
}

/**
 * Export keying material (RFC 8446 §7.5, RFC 5705): TLS-Exporter(label, context, output.count), keys a protocol over
 * the connection derives from it, as NTS (RFC 8915) does.
 *
 * @param connection The connection: connected, or closed cleanly after its handshake finished, by close_notify either
 *     way, as an NTS-KE server closes it once it's answered.
 * @param label The exporter's label, like "EXPORTER-network-time-security", at most 249 bytes.
 * @param context The context value, hashed; empty for an empty one, which TLS 1.3 doesn't tell from none.
 * @param output Where the material goes, every byte, at most 255 times the suite's hash's length.
 * @return False, output untouched, if the handshake didn't finish, the connection failed (an alert either way), or
 *     output is too long.
 */
export_keying_material #constant_time :: fn(connection: ptr[Connection], label: string, context: u8[], output: mut crypto.SecretByte[])
    -> bool {

    hash :: suite_hash(connection.suite)
    usable :: connection.handshake_done && (connection.state == .Connected
        || (connection.state == .Ended && (connection.ending == .Closed || connection.ending == .LocalClose)))
    if !usable || label.count > 249 || output.count > 255 * hash_length(hash) {
        return false
    }
    secret := derive_empty(hash, &connection.exporter_secret, label)
    hashed : u8[HASH_MOST]
    hash_of(hash, context, &hashed)
    expand_label(hash, &secret, "exporter", range(hashed, 0, hash_length(hash)), output)
    return true
}

/**
 * Tell whether the connection's ended, and why: ending, alert, certificate and wrong_name say.
 *
 * @param connection The connection.
 * @return True if it's closed or failed; what was read before is still read, and output may still have its alert.
 */
ended :: fn(connection: ptr[Connection]) -> bool {
    return connection.state == .Ended
}

/**
 * Encrypt application data, as records, for output.
 *
 * @param connection The connection, connected.
 * @param data What's written.
 * @return How much was taken: all of it, or less if output hasn't room for more, until it's sent; 0 if it isn't
 *     connected.
 */
write :: fn(connection: ptr[mut Connection], data: u8[]) -> usize {
    if connection.state != .Connected || connection.closed_sent {
        return 0
    }
    done := cast[usize](0)
    loop {
        if done >= data.count {
            break
        }
        left :: data.count - done
        chunk :: if left < RECORD_PLAINTEXT { left } else { cast[usize](RECORD_PLAINTEXT) }
        // A record's header, its content type and its tag beside the data
        if connection.outgoing.count - connection.outgoing_count < chunk + RECORD_HEADER + 1 + 16 {
            break
        }
        write_record(connection, CONTENT_APPLICATION_DATA, range(data, done, done + chunk))
        done += chunk
    }
    while true
    return done
}

/**
 * Read application data that's arrived.
 *
 * @param connection The connection.
 * @param into Where it goes.
 * @return How many bytes; 0 when there's none waiting, as when the peer's closed, or nothing's arrived yet.
 */
read :: fn(connection: ptr[mut Connection], into: mut u8[]) -> usize {
    count := if into.count < connection.plaintext_count { into.count } else { connection.plaintext_count }
    for i in 0..<count {
        at :: connection.plaintext_start + i
        if at < connection.plaintext.count && i < into.count {
            into[i] = connection.plaintext[at]
        }
    }
    connection.plaintext_start += count
    connection.plaintext_count -= count
    if connection.plaintext_count == 0 {
        connection.plaintext_start = 0
    }
    // Records waiting for room to be opened into
    if count > 0 {
        take_records(connection)
    }
    return count
}

/**
 * Close the connection: close_notify queued for output, and nothing written after.
 *
 * @param connection The connection.
 */
close :: fn(connection: ptr[mut Connection]) {
    if connection.closed_sent || connection.state == .Idle {
        return void
    }
    send_alert(connection, ALERT_CLOSE_NOTIFY)
    if connection.state != .Ended {
        connection.state = .Ended
        connection.ending = .LocalClose
    }
}

// ---- Within

/** Leave a connection as new, of a role; its large buffers keep what they held, past their counts. */
reset :: fn(connection: ptr[mut Connection], role: Role) {
    connection.role = role
    connection.state = .Idle
    connection.ending = .None
    connection.alert = 0
    connection.handshake_done = false
    connection.certificate = .VALID
    connection.wrong_name = false
    connection.host_length = 0
    connection.verify = false
    connection.anchors = 0
    connection.anchors_bytes = 0
    connection.suite = .None
    connection.transcript = transcript_start()
    connection.group = 0
    connection.retried = false
    connection.cookie_length = 0
    connection.session_id_length = 0
    connection.certificate_requested = false
    connection.request_context_length = 0
    connection.scheme = 0
    connection.peer_kind = .UNSUPPORTED
    connection.peer_key_length = 0
    connection.read = TrafficKeys.{}
    connection.write = TrafficKeys.{}
    connection.read_encrypted = false
    connection.write_encrypted = false
    connection.incoming_count = 0
    connection.outgoing_count = 0
    connection.message_count = 0
    connection.plaintext_start = 0
    connection.plaintext_count = 0
    connection.closed_sent = false
    connection.fixed_keys = false
    connection.small_rsa = false
    connection.only_suite = .None
    connection.only_group = 0
    connection.protocol_length = 0
    connection.protocol_agreed = false
}

/** Keep the application protocol offered or spoken; one longer than PROTOCOL_BYTES is none, as it can't be kept whole. */
set_protocol :: fn(connection: ptr[mut Connection], protocol: string) {
    bytes :: string_bytes(protocol)
    if bytes.count > connection.protocol.count {
        connection.protocol_length = 0
        return void
    }
    for byte, i in bytes {
        if i < connection.protocol.count {
            connection.protocol[i] = byte
        }
    }
    connection.protocol_length = bytes.count
}

/** The application protocol offered or spoken, as kept. */
protocol_of :: fn(connection: ptr[Connection]) -> u8[] {
    return range(connection.protocol, 0, connection.protocol_length)
}

/** Tell whether a name is the application protocol offered or spoken. */
is_protocol :: fn(connection: ptr[Connection], name: u8[]) -> bool {
    mine :: protocol_of(connection)
    if mine.count == 0 || name.count != mine.count {
        return false
    }
    for byte, i in name {
        if byte != mine[i] {
            return false
        }
    }
    return true
}

/** Keep the host's name, as much as fits. */
set_host :: fn(connection: ptr[mut Connection], host: string) {
    bytes :: string_bytes(host)
    count :: if bytes.count < connection.host.count { bytes.count } else { connection.host.count }
    for byte, i in range(bytes, 0, count) {
        if i < connection.host.count {
            connection.host[i] = byte
        }
    }
    connection.host_length = count
}

/** The host's name, as kept. */
host_of :: fn(connection: ptr[Connection]) -> u8[] {
    return range(connection.host, 0, connection.host_length)
}

/** Drop a buffer's first bytes, moving the rest down. */
remove_front :: fn[N: usize](buffer: ptr[mut u8[N]], count: ptr[mut usize], taken: usize) {
    if taken == 0 {
        return void
    }
    left :: count^ - taken
    for i in 0..<left {
        if i < buffer.count && i + taken < buffer.count {
            buffer[i] = buffer[i + taken]
        }
    }
    count^ = left
}

/**
 * End the connection, sending a fatal alert.
 *
 * @param connection The connection.
 * @param description The alert's description.
 */
fail :: fn(connection: ptr[mut Connection], description: u8) {
    if connection.state == .Ended {
        return void
    }
    send_alert(connection, description)
    connection.state = .Ended
    connection.ending = .Refused
    connection.alert = description
}

/** Queue an alert: close_notify as a warning, the rest fatal. */
send_alert :: fn(connection: ptr[mut Connection], description: u8) {
    level :: if description == ALERT_CLOSE_NOTIFY { cast[u8](1) } else { cast[u8](2) }
    alert :: u8.[level, description]
    write_record(connection, CONTENT_ALERT, alert[0..<2])
    if description == ALERT_CLOSE_NOTIFY {
        connection.closed_sent = true
    }
}

/**
 * Queue a record for output: in the clear before keys are set, sealed after (RFC 8446 §5.2). Content past what output
 * has room for is dropped, and the connection failed.
 *
 * @param connection The connection.
 * @param kind The content type.
 * @param content The content, at most RECORD_PLAINTEXT bytes.
 */
write_record :: fn(connection: ptr[mut Connection], kind: u8, content: u8[]) {
    sealed :: connection.write_encrypted
    length :: if sealed { content.count + 1 + 16 } else { content.count }
    if content.count > RECORD_PLAINTEXT || connection.outgoing.count - connection.outgoing_count < RECORD_HEADER + length {
        // Nothing more can go out: the connection can't go on
        connection.state = .Ended
        connection.ending = .Refused
        connection.alert = ALERT_INTERNAL_ERROR
        return void
    }
    at :: connection.outgoing_count
    // The first ClientHello says TLS 1.0, as middleboxes expect (§5.1)
    version :: if !sealed && kind == CONTENT_HANDSHAKE && content.count > 0 && content[0] == CLIENT_HELLO && !connection.retried {
        cast[u16](0x0301) } else { LEGACY_VERSION }
    header :: u8.[if sealed { CONTENT_APPLICATION_DATA } else { kind }, cast[u8](version >> 8), cast[u8](version),
        cast[u8](length >> 8), cast[u8](length)]
    for byte, i in header {
        if at + i < connection.outgoing.count {
            connection.outgoing[at + i] = byte
        }
    }
    if !sealed {
        for byte, i in content {
            position :: at + RECORD_HEADER + i
            if position < connection.outgoing.count {
                connection.outgoing[position] = byte
            }
        }
        connection.outgoing_count += RECORD_HEADER + length
        return void
    }
    for byte, i in content {
        if i < connection.inner.count {
            connection.inner[i] = byte
        }
    }
    connection.inner[content.count] = kind
    inner :: connection.inner[0..<content.count + 1]
    start :: at + RECORD_HEADER
    ciphertext :: range_mut(connection.outgoing, start, start + content.count + 1)
    tag : crypto.Tag128
    if !seal(connection.suite, &connection.write, crypto.as_secret(inner), header[0..<5], ciphertext, &tag) {
        connection.state = .Ended
        connection.ending = .Refused
        connection.alert = ALERT_INTERNAL_ERROR
        return void
    }
    for byte, i in tag {
        position :: start + content.count + 1 + i
        if position < connection.outgoing.count {
            connection.outgoing[position] = byte
        }
    }
    connection.outgoing_count += RECORD_HEADER + length
    connection.write.sequence += 1
}

/**
 * Give a record's nonce: the IV with the sequence number XORed into its last 8 bytes (§5.3).
 *
 * @param keys The direction's keys.
 * @return The nonce.
 */
nonce_of :: fn(keys: ptr[TrafficKeys]) -> crypto.Nonce96 {
    nonce : crypto.Nonce96
    for i in 0..<12 {
        nonce[i] = keys.iv[i]
    }
    for i in cast[u64](0)..<8 {
        nonce[4 + i] = nonce[4 + i] ~ cast[u8](keys.sequence >> (8 * (7 - i)))
    }
    return nonce
}

/**
 * Seal a record's inner plaintext with the suite's AEAD.
 *
 * @return False if the AEAD wouldn't.
 */
seal #constant_time :: fn(suite: Suite, keys: ptr[TrafficKeys], plaintext: crypto.SecretByte[], associated: u8[], ciphertext: mut u8[],
    tag: ptr[mut crypto.Tag128]) -> bool {

    nonce :: nonce_of(keys)
    if suite == .Aes128GcmSha256 {
        key : crypto.Key128
        for i in 0..<16 {
            key[i] = keys.key[i]
        }
        return crypto.aes128_gcm_seal(&key, &nonce, plaintext, associated, ciphertext, tag)
    }
    key : crypto.Key256
    for i in 0..<32 {
        key[i] = keys.key[i]
    }
    if suite == .Aes256GcmSha384 {
        return crypto.aes256_gcm_seal(&key, &nonce, plaintext, associated, ciphertext, tag)
    }
    return crypto.chacha20_poly1305_seal(&key, &nonce, plaintext, associated, ciphertext, tag)
}

/**
 * Open a record with the suite's AEAD.
 *
 * @return False if its tag doesn't match.
 */
open #constant_time :: fn(suite: Suite, keys: ptr[TrafficKeys], ciphertext: u8[], associated: u8[], tag: ptr[crypto.Tag128],
    plaintext: mut crypto.SecretByte[]) -> bool {

    nonce :: nonce_of(keys)
    if suite == .Aes128GcmSha256 {
        key : crypto.Key128
        for i in 0..<16 {
            key[i] = keys.key[i]
        }
        return crypto.aes128_gcm_open(&key, &nonce, ciphertext, associated, tag, plaintext)
    }
    key : crypto.Key256
    for i in 0..<32 {
        key[i] = keys.key[i]
    }
    if suite == .Aes256GcmSha384 {
        return crypto.aes256_gcm_open(&key, &nonce, ciphertext, associated, tag, plaintext)
    }
    return crypto.chacha20_poly1305_open(&key, &nonce, ciphertext, associated, tag, plaintext)
}

/**
 * Act on every whole record waiting, until one can't be taken yet or the connection ends.
 *
 * @param connection The connection.
 */
take_records :: fn(connection: ptr[mut Connection]) {
    loop {
        if connection.state == .Ended || connection.incoming_count < RECORD_HEADER {
            return void
        }
        kind :: connection.incoming[0]
        length :: (cast[usize](connection.incoming[3]) << 8) | cast[usize](connection.incoming[4])
        if length > RECORD_CIPHERTEXT {
            fail(connection, ALERT_RECORD_OVERFLOW)
            return void
        }
        if connection.incoming_count < RECORD_HEADER + length {
            return void
        }
        // Application data's opened only once there's room for what it holds
        if connection.read_encrypted && kind == CONTENT_APPLICATION_DATA
            && connection.plaintext.count - connection.plaintext_start - connection.plaintext_count < length {
            if connection.plaintext_count > 0 {
                return void
            }
        }
        take_record(connection, kind, length)
        remove_front(&connection.incoming, &connection.incoming_count, RECORD_HEADER + length)
    }
}

/**
 * Act on one record, at the start of incoming.
 *
 * @param connection The connection.
 * @param kind Its content type.
 * @param length Its length, past its header.
 */
take_record :: fn(connection: ptr[mut Connection], kind: u8, length: usize) {
    record :: range(connection.incoming, RECORD_HEADER, RECORD_HEADER + length)
    // A ChangeCipherSpec of 1 in the clear, during the handshake, as middlebox compatibility sends (§5)
    if kind == CONTENT_CHANGE_CIPHER_SPEC {
        if record.count == 1 && record[0] == 1 && connection.state != .Connected {
            return void
        }
        fail(connection, ALERT_UNEXPECTED_MESSAGE)
        return void
    }
    if !connection.read_encrypted {
        if kind == CONTENT_HANDSHAKE {
            take_handshake_bytes(connection, record)
        }
        else if kind == CONTENT_ALERT {
            take_alert(connection, record)
        }
        else {
            fail(connection, ALERT_UNEXPECTED_MESSAGE)
        }
        return void
    }
    if kind != CONTENT_APPLICATION_DATA || length < 17 {
        fail(connection, if length < 17 { ALERT_DECODE_ERROR } else { ALERT_UNEXPECTED_MESSAGE })
        return void
    }
    header :: connection.incoming[0..<RECORD_HEADER]
    body :: length - 16
    tag : crypto.Tag128
    for byte, i in range(record, body, body + 16) {
        if i < 16 {
            tag[i] = byte
        }
    }
    opened :: range_mut(connection.opened, 0, body)
    if !open(connection.suite, &connection.read, range(record, 0, body), header, &tag, opened) {
        fail(connection, ALERT_BAD_RECORD_MAC)
        return void
    }
    connection.read.sequence += 1
    // The content type's the last byte that isn't padding (§5.4)
    end := body
    loop {
        last :: end - 1
        if end == 0 || last >= connection.opened.count || compiler.declassify(cast[u8](connection.opened[last])) != 0 {
            break
        }
        end -= 1
    }
    while true
    if end == 0 || end - 1 > RECORD_PLAINTEXT {
        fail(connection, if end == 0 { ALERT_UNEXPECTED_MESSAGE } else { ALERT_RECORD_OVERFLOW })
        return void
    }
    inner_kind :: compiler.declassify(cast[u8](connection.opened[end - 1]))
    for i in 0..<end - 1 {
        if i < connection.inner.count {
            connection.inner[i] = compiler.declassify(cast[u8](connection.opened[i]))
        }
    }
    content :: connection.inner[0..<end - 1]
    if inner_kind == CONTENT_HANDSHAKE {
        take_handshake_bytes(connection, content)
    }
    else if inner_kind == CONTENT_ALERT {
        take_alert(connection, content)
    }
    else if inner_kind == CONTENT_APPLICATION_DATA {
        if connection.state != .Connected {
            fail(connection, ALERT_UNEXPECTED_MESSAGE)
            return void
        }
        // Moved down to the start, then appended
        if connection.plaintext_start > 0 {
            for i in 0..<connection.plaintext_count {
                if i < connection.plaintext.count && connection.plaintext_start + i < connection.plaintext.count {
                    connection.plaintext[i] = connection.plaintext[connection.plaintext_start + i]
                }
            }
            connection.plaintext_start = 0
        }
        for byte in content {
            if connection.plaintext_count < connection.plaintext.count {
                connection.plaintext[connection.plaintext_count] = byte
                connection.plaintext_count += 1
            }
        }
    }
    else {
        fail(connection, ALERT_UNEXPECTED_MESSAGE)
    }
}

/**
 * Take an alert: close_notify ends the connection as closed, user_canceled is passed over, and any other ends it as
 * failed by the peer.
 *
 * @param connection The connection.
 * @param alert The alert's two bytes.
 */
take_alert :: fn(connection: ptr[mut Connection], alert: u8[]) {
    if alert.count != 2 {
        fail(connection, ALERT_DECODE_ERROR)
        return void
    }
    description :: alert[1]
    if description == ALERT_USER_CANCELED {
        return void
    }
    connection.state = .Ended
    connection.alert = description
    connection.ending = if description == ALERT_CLOSE_NOTIFY { Ending.Closed } else { Ending.PeerAlert }
}

/**
 * Take handshake bytes: each whole message among what's gathered is acted on, in order.
 *
 * @param connection The connection.
 * @param bytes A record's handshake bytes.
 */
take_handshake_bytes :: fn(connection: ptr[mut Connection], bytes: u8[]) {
    if bytes.count == 0 {
        fail(connection, ALERT_UNEXPECTED_MESSAGE)
        return void
    }
    for byte in bytes {
        if connection.message_count >= connection.message.count {
            fail(connection, ALERT_RECORD_OVERFLOW)
            return void
        }
        connection.message[connection.message_count] = byte
        connection.message_count += 1
    }
    loop {
        if connection.state == .Ended || connection.message_count < 4 {
            return void
        }
        length :: (cast[usize](connection.message[1]) << 16) | (cast[usize](connection.message[2]) << 8) | cast[usize](connection.message[3])
        if 4 + length > connection.message.count {
            fail(connection, ALERT_RECORD_OVERFLOW)
            return void
        }
        if connection.message_count < 4 + length {
            return void
        }
        before :: connection.read_changes
        take_message(connection, connection.message[0], 4 + length)
        remove_front(&connection.message, &connection.message_count, 4 + length)
        // A message mustn't span a change of keys (§5.1)
        if before != connection.read_changes && connection.message_count > 0 {
            fail(connection, ALERT_UNEXPECTED_MESSAGE)
            return void
        }
    }
}

/**
 * Act on a whole handshake message, at the start of message: the client's or the server's, as the role is.
 *
 * @param connection The connection.
 * @param kind Its type.
 * @param length Its length, with its header.
 */
take_message :: fn(connection: ptr[mut Connection], kind: u8, length: usize) {
    message :: range(connection.message, 0, length)
    if connection.role == .Client {
        client_message(connection, kind, message)
    }
    else {
        server_message(connection, kind, message)
    }
}

/**
 * Queue a handshake message for output, and add it to the transcript.
 *
 * @param connection The connection.
 * @param message The message, from its type, as many records as it takes.
 */
send_message :: fn(connection: ptr[mut Connection], message: u8[]) {
    transcript_add(&connection.transcript, message)
    at := cast[usize](0)
    loop {
        if at >= message.count || connection.state == .Ended {
            break
        }
        left :: message.count - at
        chunk :: if left < RECORD_PLAINTEXT { left } else { cast[usize](RECORD_PLAINTEXT) }
        write_record(connection, CONTENT_HANDSHAKE, range(message, at, at + chunk))
        at += chunk
    }
    while true
}

/**
 * Set the keys records are read with from a traffic secret.
 *
 * @param connection The connection, its suite chosen.
 * @param secret The traffic secret.
 */
set_read_keys #constant_time :: fn(connection: ptr[mut Connection], secret: ptr[Secret]) {
    connection.read = traffic_keys(suite_hash(connection.suite), key_length(connection.suite), secret)
    connection.read_secret = secret^
    connection.read_encrypted = true
    connection.read_changes += 1
}

/**
 * Set the keys records are written with from a traffic secret.
 *
 * @param connection The connection, its suite chosen.
 * @param secret The traffic secret.
 */
set_write_keys #constant_time :: fn(connection: ptr[mut Connection], secret: ptr[Secret]) {
    connection.write = traffic_keys(suite_hash(connection.suite), key_length(connection.suite), secret)
    connection.write_secret = secret^
    connection.write_encrypted = true
}

/**
 * Take a KeyUpdate (§4.6.3): the keys read with move on, and, if it asks, this side's own KeyUpdate goes out, the keys
 * written with moving on after it.
 *
 * @param connection The connection, connected.
 * @param message The message.
 */
take_key_update :: fn(connection: ptr[mut Connection], message: u8[]) {
    if message.count != 5 || (message[4] != 0 && message[4] != 1) {
        fail(connection, ALERT_DECODE_ERROR)
        return void
    }
    hash :: suite_hash(connection.suite)
    next := next_traffic_secret(hash, &connection.read_secret)
    set_read_keys(connection, &next)
    if message[4] == 1 {
        update :: u8.[KEY_UPDATE, 0, 0, 1, 0]
        // Not part of the transcript, which the handshake's over with
        write_record(connection, CONTENT_HANDSHAKE, update[0..<5])
        written := next_traffic_secret(hash, &connection.write_secret)
        set_write_keys(connection, &written)
    }
}

/**
 * The handshake's secrets once a shared secret's agreed (§7.1): the handshake secret, the master secret, and the
 * handshake traffic secrets, from the transcript up to the ServerHello.
 *
 * @param connection The connection, its suite chosen and the ServerHello in its transcript.
 * @param shared The shared secret, 32 bytes.
 */
handshake_secrets #constant_time :: fn(connection: ptr[mut Connection], shared: ptr[crypto.SecretByte[32]]) {
    hash :: suite_hash(connection.suite)
    length :: hash_length(hash)
    zeros : Secret
    zero_input : crypto.SecretByte[HASH_MOST]
    early :: extract(hash, &zeros, range(zero_input, 0, length))
    derived :: derive_empty(hash, &early, "derived")
    connection.handshake_secret = extract(hash, &derived, shared[0..<32])
    transcript : u8[HASH_MOST]
    transcript_hash(&connection.transcript, hash, &transcript)
    connection.client_secret = derive_secret(hash, &connection.handshake_secret, "c hs traffic", &transcript)
    connection.server_secret = derive_secret(hash, &connection.handshake_secret, "s hs traffic", &transcript)
    master_salt :: derive_empty(hash, &connection.handshake_secret, "derived")
    connection.master_secret = extract(hash, &master_salt, range(zero_input, 0, length))
}

/**
 * The application traffic secrets (§7.1), from the transcript up to the server's Finished, in client_secret and
 * server_secret, in place of the handshake's.
 *
 * @param connection The connection, the server's Finished in its transcript.
 */
application_secrets :: fn(connection: ptr[mut Connection]) {
    hash :: suite_hash(connection.suite)
    transcript : u8[HASH_MOST]
    transcript_hash(&connection.transcript, hash, &transcript)
    connection.client_secret = derive_secret(hash, &connection.master_secret, "c ap traffic", &transcript)
    connection.server_secret = derive_secret(hash, &connection.master_secret, "s ap traffic", &transcript)
    connection.exporter_secret = derive_secret(hash, &connection.master_secret, "exp master", &transcript)
}

/**
 * Make a Finished: verify_data with a side's handshake traffic secret over the transcript so far.
 *
 * @param connection The connection.
 * @param secret The sending side's handshake traffic secret.
 * @param into Where the message goes.
 * @return Its length.
 */
make_finished #constant_time :: fn(connection: ptr[mut Connection], secret: ptr[Secret], into: mut u8[]) -> usize {
    hash :: suite_hash(connection.suite)
    length :: hash_length(hash)
    transcript : u8[HASH_MOST]
    transcript_hash(&connection.transcript, hash, &transcript)
    data :: finished_data(hash, secret, &transcript)
    writer := Writer.{}
    put_u8(into, &writer, FINISHED)
    put_u24(into, &writer, length)
    for byte in range(data, 0, length) {
        put_u8(into, &writer, compiler.declassify(cast[u8](byte)))
    }
    return writer.at
}

/**
 * Check a Finished from the peer against the transcript so far.
 *
 * @param connection The connection.
 * @param secret The sending side's handshake traffic secret.
 * @param message The Finished.
 * @return True if its verify_data is right.
 */
check_finished #constant_time :: fn(connection: ptr[mut Connection], secret: ptr[Secret], message: u8[]) -> bool {
    hash :: suite_hash(connection.suite)
    length :: hash_length(hash)
    if message.count != 4 + length {
        return false
    }
    transcript : u8[HASH_MOST]
    transcript_hash(&connection.transcript, hash, &transcript)
    data :: finished_data(hash, secret, &transcript)
    return crypto.equal(range(data, 0, length), range(message, 4, 4 + length))
}

/**
 * Restart the transcript after a HelloRetryRequest (§4.4.1): the first ClientHello's hash, as a message_hash message,
 * in its place.
 *
 * @param connection The connection, its suite chosen.
 * @param first_hello_hash The first ClientHello's hash, its first hash_length bytes.
 */
restart_transcript :: fn(connection: ptr[mut Connection], first_hello_hash: ptr[u8[HASH_MOST]]) {
    hash :: suite_hash(connection.suite)
    length :: hash_length(hash)
    connection.transcript = transcript_start()
    header :: u8.[MESSAGE_HASH, 0, 0, cast[u8](length)]
    transcript_add(&connection.transcript, header[0..<4])
    transcript_add(&connection.transcript, range(first_hello_hash^, 0, length))
}

/**
 * The content a CertificateVerify signs (§4.4.3): 64 spaces, the context string, a zero, and the transcript hash.
 *
 * @param connection The connection, the Certificate in its transcript.
 * @param server Whether it's the server's.
 * @param into Where it goes: at least 64 + 34 + 48 bytes.
 * @return Its length.
 */
verify_content :: fn(connection: ptr[mut Connection], server: bool, into: mut u8[]) -> usize {
    writer := Writer.{}
    for i in 0..<64 {
        put_u8(into, &writer, 0x20)
    }
    put_bytes(into, &writer, string_bytes(if server { "TLS 1.3, server CertificateVerify" } else { "TLS 1.3, client CertificateVerify" }))
    put_u8(into, &writer, 0)
    hash :: suite_hash(connection.suite)
    transcript : u8[HASH_MOST]
    transcript_hash(&connection.transcript, hash, &transcript)
    put_bytes(into, &writer, range(transcript, 0, hash_length(hash)))
    return writer.at
}
