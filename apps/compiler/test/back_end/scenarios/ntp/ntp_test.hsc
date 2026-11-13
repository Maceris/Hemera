package ntp_test

import runtime from "base"
import crypto from "std"
import ntp from "std"
import random from "std"
import testing from "std"
import tls from "std"

/*
 * std/ntp: NTP's timestamps and its offset and delay; NTS-KE's request and the reading of its response; and NTP
 * requests with NTS answered by a server played here, which checks the client's authenticator and seals its answer and
 * new cookies, each answer then taken or refused: forged, changed, for another request, a NAK, an unsynchronized
 * server; and bytes made at random read without harm.
 */

/** A second, in nanoseconds. */
SECOND : i64 : 1_000_000_000

timestamps_and_samples #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect_eq(t, ntp.timestamp_of(0), cast[u64](2208988800) << 32, "1970 is NTP's 2208988800 seconds")
    testing.expect_eq(t, ntp.timestamp_of(SECOND / 2) & 0xffffffff, cast[u64](0x80000000), "half a second is half the fraction")
    // Across era 0's end, 2036-02-07T06:28:16Z, 2085978496 seconds after 1970
    end :: cast[i64](2085978496) * SECOND
    testing.expect_eq(t, ntp.timestamp_of(end) >> 32, cast[u64](0), "era 1 starts its seconds at 0")
    testing.expect_eq(t, ntp.difference(ntp.timestamp_of(end - SECOND), ntp.timestamp_of(end + SECOND)), 2 * SECOND,
        "a difference across the era's end")
    testing.expect_eq(t, ntp.difference(ntp.timestamp_of(end + SECOND), ntp.timestamp_of(end - SECOND)), -2 * SECOND,
        "and back")
    // A client 5 s behind: it sends at 1000 s, the server has it at 1005.1 and answers at 1005.2, it arrives at 1000.3
    reply := ntp.Reply.{stratum = 2, received = ntp.timestamp_of(1005 * SECOND + SECOND / 10),
        transmitted = ntp.timestamp_of(1005 * SECOND + SECOND / 5)}
    sample :: ntp.sample_of(1000 * SECOND, &reply, 1000 * SECOND + 3 * SECOND / 10)
    testing.expect(t, near(sample.offset, 5 * SECOND), "the offset is 5 s")
    testing.expect(t, near(sample.delay, SECOND / 5), "the delay 0.2 s")
    return .Ok
}

/** Tell whether two times are within a microsecond, as timestamps round to their fraction. */
near :: fn(a: i64, b: i64) -> bool {
    return a - b < 1000 && b - a < 1000
}

key_establishment #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    request : u8[64]
    count :: ntp.ke_request(request[0..<request.count])
    expected :: u8.[0x80, 1, 0, 2, 0, 0, 0x80, 4, 0, 2, 0, 15, 0x80, 0, 0, 0]
    testing.expect(t, ntp.same(tls.range(request, 0, count), expected[0..<16]), "the request: NTPv4, AES-SIV-CMAC-256, the end")
    session := ntp.Session.{}
    // A server's answer: the protocol and the AEAD, a warning and an unknown record that isn't critical, two cookies, a
    // server and a port, and the end
    answer :: u8.[0x80, 1, 0, 2, 0, 0, 0x80, 4, 0, 2, 0, 15, 0, 3, 0, 2, 0, 1, 0, 42, 0, 1, 9, 0, 5, 0, 4, 1, 2, 3, 4,
        0, 5, 0, 3, 7, 8, 9, 0x80, 6, 0, 4, 0x74, 0x69, 0x6d, 0x65, 0x80, 7, 0, 2, 0x10, 0x00, 0x80, 0, 0, 0]
    whole :: answer[0..<answer.count]
    done :: ntp.read_ke_response(whole, &session)
    testing.expect(t, done.outcome == .Done && done.read == whole.count, "it's read whole")
    testing.expect_eq(t, session.cookie_count, 2, "two cookies")
    testing.expect(t, session.cookies[0].count == 4 && session.cookies[1].count == 3 && session.cookies[1].bytes[2] == 9, "as sent")
    testing.expect(t, ntp.same(tls.range(session.server, 0, session.server_length), string_bytes("time")), "the server")
    testing.expect_eq(t, session.port, cast[u16](0x1000), "the port")
    // Cut anywhere before its end, it's incomplete
    incomplete := true
    for cut in 0..<whole.count {
        cut_session := ntp.Session.{}
        incomplete = incomplete && ntp.read_ke_response(whole[0..<cut], &cut_session).outcome == .Incomplete
    }
    testing.expect(t, incomplete, "each part of it is incomplete")
    expect_ke(t, u8.[0x80, 2, 0, 2, 0, 1, 0x80, 0, 0, 0], .Refused, "an Error record")
    expect_ke(t, u8.[0x80, 1, 0, 2, 0, 0, 0x80, 4, 0, 2, 0, 16, 0, 5, 0, 1, 1, 0x80, 0, 0, 0], .NotAgreed, "another AEAD")
    expect_ke(t, u8.[0x80, 1, 0, 0, 0x80, 4, 0, 2, 0, 15, 0, 5, 0, 1, 1, 0x80, 0, 0, 0], .NotAgreed, "no protocol")
    expect_ke(t, u8.[0x80, 1, 0, 2, 0, 0, 0x80, 4, 0, 2, 0, 15, 0x80, 0, 0, 0], .NoCookies, "no cookie")
    expect_ke(t, u8.[0x80, 1, 0, 2, 0, 0, 0x80, 4, 0, 2, 0, 15, 0, 5, 0, 1, 1, 0x80, 99, 0, 0, 0x80, 0, 0, 0], .Malformed,
        "an unknown critical record")
    expect_ke(t, u8.[0, 5, 0, 1, 1, 0x80, 0, 0, 0], .NotAgreed, "nothing agreed")
    return .Ok
}

/** Check what reading a response comes to. */
expect_ke :: fn(t: ptr[mut testing.T], response: u8[], outcome: ntp.KeOutcome, what: string) {
    session := ntp.Session.{}
    reading :: ntp.read_ke_response(response, &session)
    testing.expect(t, reading.outcome == outcome, what)
}

// ---- A server, played here

/** The server's keys: c2s, which requests are sealed with, and s2c, which answers are. */
KEYS :: u8.[
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
    0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe, 0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef,
    0xf0, 0xe1, 0xd2, 0xc3, 0xb4, 0xa5, 0x96, 0x87, 0x78, 0x69, 0x5a, 0x4b, 0x3c, 0x2d, 0x1e, 0x0f,
    0x0f, 0x1e, 0x2d, 0x3c, 0x4b, 0x5a, 0x69, 0x78, 0x87, 0x96, 0xa5, 0xb4, 0xc3, 0xd2, 0xe1, 0xf0,
]

/** A session keyed with KEYS and one cookie of 40 bytes. */
keyed_session :: fn() -> ptr[mut ntp.Session] {
    session :: runtime.new(ntp.Session)
    for i in 0..<32 {
        session.c2s[i] = KEYS[i]
        session.s2c[i] = KEYS[32 + i]
    }
    session.keyed = true
    cookie : u8[40]
    for &byte, i in cookie {
        byte^ = cast[u8](i)
    }
    ntp.add_cookie(session, cookie[0..<40])
    return session
}

/** What the server found in a request. */
Found :: struct {
    /** Whether its authenticator opened with c2s. */
    authentic : bool,
    /** Where its identifier is, and how many cookies it asks for: the one it spent and each placeholder. */
    identifier_at : usize,
    asked : usize,
    transmit : u64,
}

/** Read a request as a server does. */
read_request :: fn(request: u8[]) -> Found {
    found := Found.{transmit = ntp.get_u64(request, 40)}
    reader := tls.Reader.{at = ntp.HEADER_BYTES, end = request.count}
    loop {
        if reader.end - reader.at < 4 {
            break
        }
        start :: reader.at
        field :: tls.get_u16(request, &reader)
        length :: cast[usize](tls.get_u16(request, &reader))
        body := ntp.take(&reader, length - 4)
        if field == ntp.FIELD_UNIQUE_IDENTIFIER {
            found.identifier_at = body.at
        }
        else if field == ntp.FIELD_COOKIE || field == ntp.FIELD_COOKIE_PLACEHOLDER {
            found.asked += 1
        }
        else if field == ntp.FIELD_AUTHENTICATOR {
            nonce_length :: cast[usize](tls.get_u16(request, &body))
            _ = tls.get_u16(request, &body)
            nonce :: tls.get_bytes(request, &body, nonce_length)
            tag : crypto.Tag128
            for byte, i in tls.get_bytes(request, &body, 16) {
                if i < 16 {
                    tag[i] = byte
                }
            }
            key : crypto.Key256
            for i in 0..<32 {
                key[i] = KEYS[i]
            }
            empty : crypto.SecretByte[1]
            none : u8[1]
            found.authentic = crypto.aes_siv_cmac256_open(&key, tls.range(request, 0, start), nonce, &tag, none[0..<0], empty[0..<0])
        }
        if reader.bad {
            break
        }
    }
    while true
    return found
}

/** How the server's answer is made: honest, or wrong in a way. */
Making :: enum {
    Honest,
    /** Sealed with another key. */
    OtherKey,
    /** With no authenticator. */
    Unsealed,
    /** With another identifier. */
    OtherIdentifier,
    /** NTS's NAK, unauthenticated. */
    Nak,
    /** Its leap indicator saying it isn't synchronized. */
    Unsynchronized,
}

/**
 * Answer a request as a server does: received at 1005.1 s and answered at 1005.2 s, with as many cookies as it asked
 * for, of 48 bytes each, sealed.
 *
 * @return The answer's length in into.
 */
answer :: fn(request: u8[], found: ptr[Found], into: mut u8[], making: Making) -> usize {
    writer := tls.Writer.{}
    for byte in tls.range(request, 0, ntp.HEADER_BYTES) {
        tls.put_u8(into, &writer, byte)
    }
    leap :: if making == .Unsynchronized { cast[u8](3) } else { cast[u8](0) }
    header :: tls.range_mut(into, 0, ntp.HEADER_BYTES)
    if header.count == ntp.HEADER_BYTES {
        header[0] = (leap << 6) | (4 << 3) | 4
        header[1] = if making == .Nak { cast[u8](0) } else { cast[u8](2) }
        reference :: if making == .Nak { u8.[0x4e, 0x54, 0x53, 0x4e] } else { u8.[10, 0, 0, 1] }
        for i in 0..<4 {
            header[12 + i] = reference[i]
        }
        ntp.put_u64(header, 24, found.transmit)
        ntp.put_u64(header, 32, ntp.timestamp_of(1005 * SECOND + SECOND / 10))
        ntp.put_u64(header, 40, ntp.timestamp_of(1005 * SECOND + SECOND / 5))
    }
    identifier :: tls.range(request, found.identifier_at, found.identifier_at + ntp.IDENTIFIER_BYTES)
    other : u8[32]
    ntp.put_field(into, &writer, ntp.FIELD_UNIQUE_IDENTIFIER, if making == .OtherIdentifier { other[0..<32] } else { identifier }, false)
    if making == .Nak || making == .Unsealed {
        return writer.at
    }
    // The cookies, sealed
    fields : u8[1024]
    sealed_writer := tls.Writer.{}
    for i in 0..<found.asked {
        cookie : u8[48]
        for &byte in cookie {
            byte^ = cast[u8](0xc0 + i)
        }
        ntp.put_field(fields[0..<fields.count], &sealed_writer, ntp.FIELD_COOKIE, cookie[0..<48], false)
    }
    plaintext :: tls.range(fields, 0, sealed_writer.at)
    key : crypto.Key256
    for i in 0..<32 {
        key[i] = if making == .OtherKey { KEYS[i] } else { KEYS[32 + i] }
    }
    nonce : u8[16]
    random.fill(nonce[0..<16])
    tag : crypto.Tag128
    ciphertext : u8[1024]
    associated :: writer.at
    _ = crypto.aes_siv_cmac256_seal(&key, tls.range(into, 0, associated), nonce[0..<16], crypto.as_secret(plaintext), &tag,
        tls.range_mut(ciphertext, 0, plaintext.count))
    tls.put_u16(into, &writer, ntp.FIELD_AUTHENTICATOR)
    tls.put_u16(into, &writer, cast[u16](4 + 4 + 16 + 16 + plaintext.count))
    tls.put_u16(into, &writer, 16)
    tls.put_u16(into, &writer, cast[u16](16 + plaintext.count))
    tls.put_bytes(into, &writer, nonce[0..<16])
    tls.put_bytes(into, &writer, tag[0..<16])
    tls.put_bytes(into, &writer, tls.range(ciphertext, 0, plaintext.count))
    return writer.at
}

/**
 * Make a request with a session, answer it as making says, and read the answer.
 *
 * @param session The session, which spends a cookie and keeps what the answer gives.
 * @param making How the answer's made.
 * @param change Which byte of the answer to change on its way, or past its end for none.
 * @return What the answer came to.
 */
exchange :: fn(t: ptr[mut testing.T], session: ptr[mut ntp.Session], making: Making, change: usize = 100000) -> ntp.Answer {
    request : u8[ntp.REQUEST_BYTES]
    pending := ntp.Pending.{}
    count :: ntp.make_request(session, request[0..<request.count], &pending)
    sent :: tls.range(request, 0, count)
    found := read_request(sent)
    testing.expect(t, count > 0 && found.authentic, "the server finds the request authentic")
    reply : u8[2048]
    length :: answer(sent, &found, reply[0..<reply.count], making)
    if change < length && change < reply.count {
        reply[change] = reply[change] ~ 1
    }
    return ntp.read_response(session, &pending, tls.range(reply, 0, length))
}

authenticated_requests #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    session :: keyed_session()
    defer runtime.free(session)
    good :: exchange(t, session, .Honest)
    testing.expect(t, good.outcome == .Good, "an honest answer's taken")
    testing.expect_eq(t, session.cookie_count, ntp.MAX_COOKIES, "and its cookies fill the session: the one spent and seven asked for")
    testing.expect(t, session.cookies[0].count == 48 && session.cookies[7].bytes[0] == 0xc7, "as the server sealed them")
    sample :: ntp.sample_of(1000 * SECOND, &good.reply, 1000 * SECOND + 3 * SECOND / 10)
    testing.expect(t, near(sample.offset, 5 * SECOND), "its time")
    testing.expect(t, exchange(t, session, .OtherKey).outcome == .Forged, "one sealed with another key is forged")
    testing.expect(t, exchange(t, session, .Unsealed).outcome == .Forged, "one with no authenticator is")
    testing.expect(t, exchange(t, session, .Honest, change = 1).outcome == .Forged, "one whose header changed on its way is")
    testing.expect(t, exchange(t, session, .Honest, change = 130).outcome == .Forged, "one whose cookies changed is")
    testing.expect(t, exchange(t, session, .OtherIdentifier).outcome == .NotAnswer, "one to another identifier isn't an answer")
    testing.expect(t, exchange(t, session, .Honest, change = 30).outcome == .NotAnswer, "nor one to another origin")
    testing.expect(t, exchange(t, session, .Nak).outcome == .Nak, "a NAK, unauthenticated, says to establish keys again")
    testing.expect(t, exchange(t, session, .Unsynchronized).outcome == .Unusable, "an unsynchronized server's time isn't used")
    // Each request spends a cookie; none refused gave any
    testing.expect_eq(t, session.cookie_count, ntp.MAX_COOKIES - 7 + 8 - 1, "refused answers give no cookies")
    return .Ok
}

/** A session without cookies or keys makes no request. */
no_request_without_a_cookie #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    session := ntp.Session.{}
    request : u8[ntp.REQUEST_BYTES]
    pending := ntp.Pending.{}
    testing.expect_eq(t, ntp.make_request(&session, request[0..<request.count], &pending), 0, "no keys, no request")
    keyed :: keyed_session()
    defer runtime.free(keyed)
    _ = ntp.make_request(keyed, request[0..<request.count], &pending)
    testing.expect_eq(t, ntp.make_request(keyed, request[0..<request.count], &pending), 0, "its only cookie spent, no more")
    return .Ok
}

/** Bytes made at random, as an NTS-KE response or an answer, are read without harm. */
takes_any_bytes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    return testing.check_property(t, any_bytes)
}

any_bytes : testing.Property : fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    bytes :: testing.draw_bytes(source, 600)
    session :: keyed_session()
    defer runtime.free(session)
    _ = ntp.read_ke_response(bytes, session)
    pending := ntp.Pending.{transmit = if bytes.count >= 32 { ntp.get_u64(bytes, 24) } else { cast[u64](0) }}
    _ = ntp.read_response(session, &pending, bytes)
    return .Ok
}
