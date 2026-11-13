package ntp

import compiler from "base"
import crypto from "std"
import random from "std"
import tls from "std"

/*
 * NTS (RFC 8915). Key Establishment first, over TLS 1.3 to the NTS-KE server, port 4460, with ALPN's "ntske/1": the
 * client sends ke_request's records, and the server's records, read with read_ke_response, give cookies, and the NTP
 * server to ask if it's another; the keys are exported from the TLS connection (take_keys). Then NTP over UDP: each
 * request (make_request) carries a unique identifier, a cookie, placeholders asking for more, and an authenticator
 * sealed with the client's key; each answer (read_response) is taken only if it echoes the identifier and its
 * authenticator opens with the server's key, and it brings new cookies, sealed, one for each spent and each asked for.
 *
 *     tls.client(connection, "time.example", anchors, now, protocol = ntp.ALPN)
 *     ... the handshake, then ke_request's bytes written, and the server's read until read_response says Done ...
 *     ntp.take_keys(&session, connection)
 *     count :: ntp.make_request(&session, packet, &pending)
 *     ... sent at t1, answered at t4 ...
 *     answer :: ntp.read_response(&session, &pending, received)
 *     if answer.outcome == .Good { sample :: ntp.sample_of(t1, &answer.reply, t4) }
 *
 * A session's cookies are each used once: a client that runs out, or whose answers stop, establishes keys again.
 */

/** NTS-KE's TCP port. */
NTS_KE_PORT : u16 : 4460
/** NTS-KE's application protocol, offered and agreed by ALPN. */
ALPN :: "ntske/1"
/** The TLS exporter's label NTS's keys come from. */
EXPORTER_LABEL :: "EXPORTER-network-time-security"
/** The next protocol negotiated: NTPv4. */
NEXT_PROTOCOL_NTPV4 : u16 : 0
/** The AEAD algorithm negotiated: AEAD_AES_SIV_CMAC_256 (RFC 5297), its key 32 bytes. */
AEAD_AES_SIV_CMAC_256 : u16 : 15

// NTS-KE's record types (RFC 8915 §4.1), the high bit of the type saying a record's critical
RECORD_END : u16 : 0
RECORD_NEXT_PROTOCOL : u16 : 1
RECORD_ERROR : u16 : 2
RECORD_WARNING : u16 : 3
RECORD_AEAD : u16 : 4
RECORD_COOKIE : u16 : 5
RECORD_SERVER : u16 : 6
RECORD_PORT : u16 : 7
/** A record type's critical bit: a record of an unknown type that has it can't be ignored. */
CRITICAL : u16 : 0x8000

// NTP's extension fields NTS uses (RFC 8915 §5.7)
FIELD_UNIQUE_IDENTIFIER : u16 : 0x0104
FIELD_COOKIE : u16 : 0x0204
FIELD_COOKIE_PLACEHOLDER : u16 : 0x0304
FIELD_AUTHENTICATOR : u16 : 0x0404

/** The most cookies a session keeps, as RFC 8915 has a client keep. */
MAX_COOKIES :: 8
/** The longest cookie kept; a server's are its own business, but tens of bytes to a hundred or so in practice. */
COOKIE_BYTES :: 256
/** The longest NTP server name kept, as the Server record gives it. */
SERVER_BYTES :: 255
/** A request's unique identifier's bytes, and its authenticator's nonce's. */
IDENTIFIER_BYTES :: 32
NONCE_BYTES :: 16
/** The most a request takes: under IPv6's minimum MTU, so it isn't fragmented. */
REQUEST_BYTES :: 1232
/** The longest sealed plaintext an answer's authenticator is opened into. */
PLAINTEXT_BYTES :: 2048
/** The smallest extension field (RFC 7822 §3). */
FIELD_LEAST :: 16
/** A kiss-o'-death's code that says the server can't read the cookie: "NTSN", NTS's NAK. */
KISS_NTS_NAK : u32 : 0x4e54534e

/** A cookie, as the server gave it. */
Cookie :: struct {
    bytes : u8[COOKIE_BYTES],
    count : usize,
}

/** An NTS session: the keys NTS-KE gave, the cookies to spend, and the NTP server to ask. */
Session :: struct {
    /** The client-to-server key, which requests are sealed with, and the server-to-client one answers are. */
    c2s : crypto.Key256,
    s2c : crypto.Key256,
    /** Whether the keys are set. */
    keyed : bool,
    /** The cookies to spend, the last first. */
    cookies : Cookie[MAX_COOKIES],
    cookie_count : usize,
    /** The NTP server to ask, as the Server record named it; empty for the NTS-KE server's own host. */
    server : u8[SERVER_BYTES],
    server_length : usize,
    /** The NTP port to ask: NTP_PORT unless the Port record said another. */
    port : u16,
    /** What NTS-KE agreed: whether NTPv4 and AES-SIV-CMAC-256 were, as they have to be. */
    protocol_agreed : bool,
    aead_agreed : bool,
}

/** What reading NTS-KE's response came to. */
KeOutcome :: enum {
    /** Its End record's read, and it gave what's needed: the session has cookies, waiting for take_keys. */
    Done,
    /** It isn't all there yet: read it again with more. */
    Incomplete,
    /** The server sent an Error record: error says which. */
    Refused,
    /** A record wasn't one, or was a critical one that isn't known. */
    Malformed,
    /** The server didn't agree to NTPv4, or to AES-SIV-CMAC-256. */
    NotAgreed,
    /** It ended without a cookie. */
    NoCookies,
}

/** Reading NTS-KE's response: what it came to, and, Refused, the Error record's code; and how many bytes were read. */
KeReading :: struct {
    outcome : KeOutcome,
    error : u16,
    read : usize,
}

/**
 * Write NTS-KE's request: NTPv4 the next protocol, AES-SIV-CMAC-256 the AEAD, and the end.
 *
 * @param into Where it goes, at least 16 bytes.
 * @return How many bytes it is; 0 if into's too short.
 */
ke_request :: fn(into: mut u8[]) -> usize {
    writer := tls.Writer.{}
    tls.put_u16(into, &writer, CRITICAL | RECORD_NEXT_PROTOCOL)
    tls.put_u16(into, &writer, 2)
    tls.put_u16(into, &writer, NEXT_PROTOCOL_NTPV4)
    tls.put_u16(into, &writer, CRITICAL | RECORD_AEAD)
    tls.put_u16(into, &writer, 2)
    tls.put_u16(into, &writer, AEAD_AES_SIV_CMAC_256)
    tls.put_u16(into, &writer, CRITICAL | RECORD_END)
    tls.put_u16(into, &writer, 0)
    return if writer.overflow { cast[usize](0) } else { writer.at }
}

/**
 * Read NTS-KE's response, as much of it as has arrived, into a session: its cookies, and its NTP server and port.
 *
 * @param response What the server's sent, from its first byte.
 * @param session The session, which its cookies, server and port are written to; set afresh each time.
 * @return What it came to.
 */
read_ke_response :: fn(response: u8[], session: ptr[mut Session]) -> KeReading {
    session.cookie_count = 0
    session.server_length = 0
    session.port = NTP_PORT
    session.protocol_agreed = false
    session.aead_agreed = false
    session.keyed = false
    reader := tls.reader_of(response)
    loop {
        if reader.end - reader.at < 4 {
            return KeReading.{outcome = .Incomplete}
        }
        kind :: tls.get_u16(response, &reader)
        length :: cast[usize](tls.get_u16(response, &reader))
        if reader.end - reader.at < length {
            return KeReading.{outcome = .Incomplete}
        }
        body := take(&reader, length)
        critical :: (kind & CRITICAL) != 0
        record :: kind & ~CRITICAL
        if record == RECORD_END {
            if length != 0 {
                return KeReading.{outcome = .Malformed, read = reader.at}
            }
            if !session.protocol_agreed || !session.aead_agreed {
                return KeReading.{outcome = .NotAgreed, read = reader.at}
            }
            if session.cookie_count == 0 {
                return KeReading.{outcome = .NoCookies, read = reader.at}
            }
            return KeReading.{outcome = .Done, read = reader.at}
        }
        else if record == RECORD_NEXT_PROTOCOL {
            // The server answers with the one protocol it chose, of those asked
            if length != 2 || tls.get_u16(response, &body) != NEXT_PROTOCOL_NTPV4 {
                return KeReading.{outcome = .NotAgreed, read = reader.at}
            }
            session.protocol_agreed = true
        }
        else if record == RECORD_AEAD {
            if length != 2 || tls.get_u16(response, &body) != AEAD_AES_SIV_CMAC_256 {
                return KeReading.{outcome = .NotAgreed, read = reader.at}
            }
            session.aead_agreed = true
        }
        else if record == RECORD_ERROR {
            return KeReading.{outcome = .Refused, error = if length == 2 { tls.get_u16(response, &body) } else { cast[u16](0) },
                read = reader.at}
        }
        else if record == RECORD_COOKIE {
            add_cookie(session, tls.range(response, body.at, body.end))
        }
        else if record == RECORD_SERVER {
            if length == 0 || length > session.server.count {
                return KeReading.{outcome = .Malformed, read = reader.at}
            }
            for byte, i in tls.range(response, body.at, body.end) {
                if i < session.server.count {
                    session.server[i] = byte
                }
            }
            session.server_length = length
        }
        else if record == RECORD_PORT {
            if length != 2 {
                return KeReading.{outcome = .Malformed, read = reader.at}
            }
            session.port = tls.get_u16(response, &body)
        }
        else if record != RECORD_WARNING && critical {
            return KeReading.{outcome = .Malformed, read = reader.at}
        }
    }
}

/**
 * Keep a cookie, if there's room and it fits; one that doesn't is dropped.
 *
 * @param session The session.
 * @param cookie The cookie.
 */
add_cookie :: fn(session: ptr[mut Session], cookie: u8[]) {
    at :: session.cookie_count
    if cookie.count == 0 || cookie.count > COOKIE_BYTES || at >= session.cookies.count {
        return void
    }
    kept :: &session.cookies[at]
    for byte, i in cookie {
        if i < kept.bytes.count {
            kept.bytes[i] = byte
        }
    }
    kept.count = cookie.count
    session.cookie_count = at + 1
}

/**
 * Export a session's keys from its NTS-KE connection, once read_ke_response has said Done.
 *
 * @param session The session.
 * @param connection The TLS connection NTS-KE ran over, connected, which has to have agreed on ALPN's "ntske/1".
 * @return True with the keys set; false if the connection didn't agree on "ntske/1", or can't export.
 */
take_keys :: fn(session: ptr[mut Session], connection: ptr[tls.Connection]) -> bool {
    session.keyed = false
    if !tls.protocol_agreed(connection) {
        return false
    }
    // The context: the next protocol, the AEAD, then 0 for client-to-server or 1 for server-to-client
    c2s_context :: u8.[0, 0, 0, 15, 0]
    s2c_context :: u8.[0, 0, 0, 15, 1]
    c2s : crypto.SecretByte[32]
    s2c : crypto.SecretByte[32]
    if !tls.export_keying_material(connection, EXPORTER_LABEL, c2s_context[0..<5], c2s[0..<32])
        || !tls.export_keying_material(connection, EXPORTER_LABEL, s2c_context[0..<5], s2c[0..<32]) {
        return false
    }
    for i in 0..<32 {
        session.c2s[i] = cast[u8](c2s[i])
        session.s2c[i] = cast[u8](s2c[i])
    }
    session.keyed = true
    return true
}

/** What a request was, to check its answer against. */
Pending :: struct {
    /** Its unique identifier, and its transmit timestamp. */
    identifier : u8[IDENTIFIER_BYTES],
    transmit : u64,
}

/**
 * Make an NTP request with NTS: its header, a unique identifier, the session's last cookie, placeholders asking for
 * as many more as it's short of MAX_COOKIES, and an authenticator over all of it, sealed with the client's key.
 *
 * @param session The session, keyed, with a cookie, which is spent.
 * @param into Where the request goes; REQUEST_BYTES is the most it takes.
 * @param pending Where what it was goes, to check its answer against.
 * @return How many bytes it is; 0 if the session isn't keyed, has no cookie, or into's too short for it.
 */
make_request :: fn(session: ptr[mut Session], into: mut u8[], pending: ptr[mut Pending]) -> usize {
    if !session.keyed || session.cookie_count == 0 || session.cookie_count > session.cookies.count || into.count < HEADER_BYTES {
        return 0
    }
    transmit : u8[8]
    random.fill(transmit[0..<8])
    pending.transmit = get_u64(transmit[0..<8], 0)
    random.fill(pending.identifier[0..<IDENTIFIER_BYTES])
    put_header(into, pending.transmit)
    writer := tls.Writer.{at = HEADER_BYTES}
    put_field(into, &writer, FIELD_UNIQUE_IDENTIFIER, pending.identifier[0..<IDENTIFIER_BYTES], false)
    last :: session.cookie_count - 1
    if last >= session.cookies.count {
        return 0
    }
    session.cookie_count = last
    spent :: &session.cookies[last]
    cookie :: tls.range(spent.bytes, 0, spent.count)
    put_field(into, &writer, FIELD_COOKIE, cookie, false)
    // Placeholders, each the cookie's size, for as many cookies as it's short of, while the request stays small enough
    placeholder :: field_bytes(cookie.count)
    wanted :: MAX_COOKIES - 1 - session.cookie_count
    for asked in 0..<wanted {
        if writer.at + placeholder + authenticator_bytes() > into.count || writer.at + placeholder + authenticator_bytes() > REQUEST_BYTES {
            break
        }
        put_field(into, &writer, FIELD_COOKIE_PLACEHOLDER, cookie, true)
    }
    // The authenticator: a nonce, and the SIV tag over everything before it, with nothing sealed
    associated :: writer.at
    nonce : u8[NONCE_BYTES]
    random.fill(nonce[0..<NONCE_BYTES])
    tag : crypto.Tag128
    empty : u8[1]
    if !crypto.aes_siv_cmac256_seal(&session.c2s, tls.range(into, 0, associated), nonce[0..<NONCE_BYTES],
        crypto.as_secret(empty[0..<0]), &tag, empty[0..<0]) {
        return 0
    }
    tls.put_u16(into, &writer, FIELD_AUTHENTICATOR)
    tls.put_u16(into, &writer, cast[u16](authenticator_bytes()))
    tls.put_u16(into, &writer, NONCE_BYTES)
    tls.put_u16(into, &writer, 16)
    tls.put_bytes(into, &writer, nonce[0..<NONCE_BYTES])
    tls.put_bytes(into, &writer, tag[0..<16])
    return if writer.overflow { cast[usize](0) } else { writer.at }
}

/** An empty authenticator's field's bytes: its header, the two lengths, the nonce and the tag. */
authenticator_bytes :: fn() -> usize {
    return 4 + 4 + NONCE_BYTES + 16
}

/** An extension field's bytes for a body: its header, and the body padded to four bytes and to FIELD_LEAST. */
field_bytes :: fn(body: usize) -> usize {
    padded :: (body + 3) / 4 * 4
    total :: 4 + padded
    return if total < FIELD_LEAST { FIELD_LEAST } else { total }
}

/**
 * Write an extension field: its type, its length, and its body, padded with zeros.
 *
 * @param into Where it goes.
 * @param writer The writer.
 * @param field The field's type.
 * @param body Its body; with zeroed, only its count's used, the body all zeros, as a placeholder's is.
 * @param zeroed Whether the body's zeros.
 */
put_field :: fn(into: mut u8[], writer: ptr[mut tls.Writer], field: u16, body: u8[], zeroed: bool) {
    total :: field_bytes(body.count)
    tls.put_u16(into, writer, field)
    tls.put_u16(into, writer, cast[u16](total))
    for byte in body {
        tls.put_u8(into, writer, if zeroed { cast[u8](0) } else { byte })
    }
    for padding in (4 + body.count)..<total {
        tls.put_u8(into, writer, 0)
    }
}

/** What an answer came to. */
AnswerOutcome :: enum {
    /** It's the answer, authenticated, and its time can be used: reply has it, and its cookies are kept. */
    Good,
    /** It isn't an answer to the request: from no server, to another request, or not the request's identifier. */
    NotAnswer,
    /** It claims to answer, but isn't authenticated: no authenticator, or one that doesn't open. Forged, or damaged. */
    Forged,
    /** NTS's NAK: the server can't read the cookie, so keys are to be established again. */
    Nak,
    /** Authenticated, but its time can't be used: a kiss-o'-death, or a server that isn't synchronized. */
    Unusable,
}

/** An answer: what it came to, and its header. */
Answer :: struct {
    outcome : AnswerOutcome,
    reply : Reply,
}

/**
 * Read an answer to a request: its identifier checked, its authenticator opened with the server's key, and the cookies
 * sealed inside it kept.
 *
 * @param session The session the request was made with, which the answer's cookies are added to.
 * @param pending What the request was.
 * @param packet The answer, as it arrived.
 * @return What it came to; reply is set from Forged on, as the header read.
 */
read_response :: fn(session: ptr[mut Session], pending: ptr[Pending], packet: u8[]) -> Answer {
    reply :: read_header(packet, pending.transmit) or_return Answer.{outcome = .NotAnswer}
    identified := false
    authenticator := cast[usize](0)
    nonce := tls.Reader.{}
    sealed := tls.Reader.{}
    reader := tls.Reader.{at = HEADER_BYTES, end = packet.count}
    loop {
        if reader.end - reader.at < 4 {
            break
        }
        start :: reader.at
        field :: tls.get_u16(packet, &reader)
        length :: cast[usize](tls.get_u16(packet, &reader))
        if length < 4 || length % 4 != 0 || length - 4 > reader.end - reader.at {
            return Answer.{outcome = .NotAnswer, reply = reply}
        }
        body := take(&reader, length - 4)
        if field == FIELD_UNIQUE_IDENTIFIER {
            identified = same(tls.range(packet, body.at, body.end), pending.identifier[0..<IDENTIFIER_BYTES])
        }
        else if field == FIELD_AUTHENTICATOR {
            nonce_length :: cast[usize](tls.get_u16(packet, &body))
            sealed_length :: cast[usize](tls.get_u16(packet, &body))
            nonce = take(&body, nonce_length)
            _ = tls.get_bytes(packet, &body, (nonce_length + 3) / 4 * 4 - nonce_length)
            sealed = take(&body, sealed_length)
            if body.bad || sealed_length < 16 {
                return Answer.{outcome = .Forged, reply = reply}
            }
            authenticator = start
            // Fields after the authenticator aren't covered by it, and are ignored
            break
        }
    }
    while true
    if !identified {
        return Answer.{outcome = .NotAnswer, reply = reply}
    }
    // NTS's NAK may come unauthenticated, as the server couldn't read the cookie, but it echoes the identifier
    if reply.stratum == STRATUM_KISS && reply.reference == KISS_NTS_NAK {
        return Answer.{outcome = .Nak, reply = reply}
    }
    if authenticator == 0 || sealed.end - sealed.at > PLAINTEXT_BYTES + 16 {
        return Answer.{outcome = .Forged, reply = reply}
    }
    tag : crypto.Tag128
    for byte, i in tls.range(packet, sealed.at, sealed.at + 16) {
        if i < 16 {
            tag[i] = byte
        }
    }
    ciphertext :: tls.range(packet, sealed.at + 16, sealed.end)
    opened : crypto.SecretByte[PLAINTEXT_BYTES]
    plaintext :: tls.range_mut(opened, 0, ciphertext.count)
    if !crypto.aes_siv_cmac256_open(&session.s2c, tls.range(packet, 0, authenticator), tls.range(packet, nonce.at, nonce.end), &tag,
        ciphertext, plaintext) {
        return Answer.{outcome = .Forged, reply = reply}
    }
    take_sealed_cookies(session, plaintext)
    return Answer.{outcome = if usable(&reply) { AnswerOutcome.Good } else { AnswerOutcome.Unusable }, reply = reply}
}

/**
 * Keep the cookies an answer sealed: each Cookie field among the extension fields it opened to.
 *
 * @param session The session.
 * @param fields The opened plaintext: extension fields.
 */
take_sealed_cookies #constant_time :: fn(session: ptr[mut Session], fields: crypto.SecretByte[]) {
    // Cookies are the server's to read, not secrets to this side: what's opened is public once it's authenticated
    plain : u8[PLAINTEXT_BYTES]
    for byte, i in fields {
        if i < plain.count {
            plain[i] = compiler.declassify(cast[u8](byte))
        }
    }
    count :: if fields.count < plain.count { fields.count } else { plain.count }
    bytes :: tls.range(plain, 0, count)
    reader := tls.reader_of(bytes)
    loop {
        if reader.end - reader.at < 4 {
            break
        }
        field :: tls.get_u16(bytes, &reader)
        length :: cast[usize](tls.get_u16(bytes, &reader))
        if length < 4 || length - 4 > reader.end - reader.at {
            break
        }
        body := take(&reader, length - 4)
        if field == FIELD_COOKIE {
            add_cookie(session, tls.range(bytes, body.at, body.end))
        }
    }
    while true
}

/** Tell whether two byte views are the same bytes. */
same :: fn(a: u8[], b: u8[]) -> bool {
    if a.count != b.count {
        return false
    }
    for byte, i in a {
        if byte != b[i] {
            return false
        }
    }
    return true
}

/**
 * Take the next bytes a reader has as a reader of their own, the reader moved past them.
 *
 * @param reader The reader.
 * @param length How many bytes.
 * @return A reader of them; a bad one, and the reader made bad, if it has fewer.
 */
take :: fn(reader: ptr[mut tls.Reader], length: usize) -> tls.Reader {
    if reader.bad || length > reader.end - reader.at {
        reader.bad = true
        reader.at = reader.end
        return tls.Reader.{at = reader.end, end = reader.end, bad = true}
    }
    part :: tls.Reader.{at = reader.at, end = reader.at + length}
    reader.at += length
    return part
}
