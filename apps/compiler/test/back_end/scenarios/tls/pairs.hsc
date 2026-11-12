package tls_test

import runtime from "base"
import crypto from "std"
import testing from "std"
import tls from "std"

/*
 * A client and a server of std/tls's, in memory: each suite, P-256's and Ed25519's certificates, P-256 asked for with
 * a HelloRetryRequest, application data both ways, KeyUpdate, close_notify; and chains refused for each reason, a
 * record changed on its way refused, and bytes made at random taken without harm.
 */

/** A client and a server, and the chain and anchors they're given, on the heap, as connections keep pointers to them. */
Pair :: struct {
    client : tls.Connection,
    server : tls.Connection,
    chain : u8[4096],
    chain_bytes : usize,
    anchors : u8[1024],
    anchors_bytes : usize,
}

/**
 * Make a pair: the server with a chain and key, the client checking tls.test against ROOT.
 *
 * @param chain The server's chain.
 * @param kind Its leaf's kind of key: P256 or ED25519.
 * @param key Its leaf's secret key, 32 bytes.
 * @param only_suite The server's only suite, or None.
 * @param only_group The server's only group, or 0.
 * @return The pair, the caller's to free, the client's ClientHello waiting.
 */
make_pair :: fn(chain: u8[], kind: crypto.X509KeyKind, key: u8[], only_suite: tls.Suite = .None, only_group: u16 = 0) -> ptr[mut Pair] {
    pair :: runtime.new(Pair)
    for byte, i in chain {
        if i < pair.chain.count {
            pair.chain[i] = byte
        }
    }
    pair.chain_bytes = chain.count
    for byte, i in ROOT {
        if i < pair.anchors.count {
            pair.anchors[i] = byte
        }
    }
    pair.anchors_bytes = ROOT.count
    identity :: tls.identity_of(kind, tls.range(pair.chain, 0, pair.chain_bytes), key)
    tls.server(&pair.server, &identity, only_suite, only_group)
    tls.client(&pair.client, "tls.test", tls.range(pair.anchors, 0, pair.anchors_bytes), NOW)
    return pair
}

/**
 * Move what each side has for the other across, until neither has more, or a side's ended.
 *
 * @param pair The pair.
 */
pump :: fn(pair: ptr[mut Pair]) {
    for round in 0..<64 {
        moved := false
        out :: tls.output(&pair.client)
        if out.count > 0 {
            taken :: tls.received(&pair.server, out)
            tls.sent(&pair.client, taken)
            moved = moved || taken > 0
        }
        back :: tls.output(&pair.server)
        if back.count > 0 {
            taken :: tls.received(&pair.client, back)
            tls.sent(&pair.server, taken)
            moved = moved || taken > 0
        }
        if !moved {
            return void
        }
    }
}

/**
 * Check data goes both ways: the client's to the server, and back.
 *
 * @param t The test's state.
 * @param pair The pair, connected.
 * @param what What the check's of, for its failures.
 */
exchange :: fn(t: ptr[mut testing.T], pair: ptr[mut Pair], what: string) {
    asked :: "GET / HTTP/1.1"
    testing.note(t, "%", what)
    testing.expect_eq(t, tls.write(&pair.client, string_bytes(asked)), asked.count, "the client writes")
    pump(pair)
    got : u8[64]
    count :: tls.read(&pair.server, got[0..<got.count])
    testing.expect(t, count <= got.count && string_of(&got[0], count) == asked, "the server reads it")
    answer :: "HTTP/1.1 200 OK"
    _ = tls.write(&pair.server, string_bytes(answer))
    pump(pair)
    back :: tls.read(&pair.client, got[0..<got.count])
    testing.expect(t, back <= got.count && string_of(&got[0], back) == answer, "the client reads the answer")
    testing.end_note(t)
}

connects_with_each_suite #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    for suite in tls.Suite.[.Aes128GcmSha256, .Aes256GcmSha384, .Chacha20Poly1305Sha256] {
        pair :: make_pair(P256_CHAIN[0..<P256_CHAIN.count], .P256, P256_KEY[0..<32], suite)
        pump(pair)
        testing.note(t, "% : client % %, server % %", suite, pair.client.state, pair.client.alert, pair.server.state, pair.server.alert)
        testing.expect(t, tls.connected(&pair.client) && tls.connected(&pair.server), "both connect")
        testing.expect(t, pair.client.suite == suite, "with the server's suite")
        testing.end_note(t)
        exchange(t, pair, "data each way")
        runtime.free(pair)
    }
    return .Ok
}

connects_with_ed25519_and_after_a_retry #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    signed :: make_pair(ED25519_CHAIN[0..<ED25519_CHAIN.count], .ED25519, ED25519_KEY[0..<32])
    pump(signed)
    testing.note(t, "client % %, server % %", signed.client.state, signed.client.alert, signed.server.state, signed.server.alert)
    testing.expect(t, tls.connected(&signed.client) && tls.connected(&signed.server), "an Ed25519 certificate's server")
    testing.end_note(t)
    exchange(t, signed, "after Ed25519")
    runtime.free(signed)
    retried :: make_pair(P256_CHAIN[0..<P256_CHAIN.count], .P256, P256_KEY[0..<32], .None, tls.GROUP_P256)
    pump(retried)
    testing.note(t, "client % %, server % %", retried.client.state, retried.client.alert, retried.server.state, retried.server.alert)
    testing.expect(t, tls.connected(&retried.client) && tls.connected(&retried.server), "a server taking P-256 only")
    testing.expect(t, retried.client.retried && retried.client.group == tls.GROUP_P256, "after its HelloRetryRequest")
    testing.end_note(t)
    exchange(t, retried, "after a retry")
    runtime.free(retried)
    return .Ok
}

/**
 * Check a client refuses a server's chain, and the server hears why.
 *
 * @param t The test's state.
 * @param chain The server's chain.
 * @param key Its leaf's P-256 key.
 * @param alert The alert expected.
 * @param what What's wrong with it.
 * @return The client's connection's verdict and whether its name was wrong, as copied.
 */
refused :: fn(t: ptr[mut testing.T], chain: u8[], key: u8[], alert: u8, what: string) -> (crypto.X509Verdict, bool) {
    pair :: make_pair(chain, .P256, key)
    defer runtime.free(pair)
    pump(pair)
    testing.note(t, "%: client % % %, server % %", what, pair.client.ending, pair.client.alert, pair.client.certificate,
        pair.server.ending, pair.server.alert)
    testing.expect(t, tls.ended(&pair.client) && pair.client.ending == .Refused && pair.client.alert == alert, "the client refuses it")
    testing.expect(t, tls.ended(&pair.server) && pair.server.ending == .PeerAlert && pair.server.alert == alert, "the server hears why")
    testing.end_note(t)
    return pair.client.certificate, pair.client.wrong_name
}

refuses_bad_chains #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    expired, expired_name :: refused(t, EXPIRED_CHAIN[0..<EXPIRED_CHAIN.count], EXPIRED_KEY[0..<32], tls.ALERT_CERTIFICATE_EXPIRED, "expired")
    testing.expect(t, expired == .EXPIRED && !expired_name, "an expired leaf")
    wrong, wrong_name :: refused(t, WRONG_NAME_CHAIN[0..<WRONG_NAME_CHAIN.count], WRONG_NAME_KEY[0..<32], tls.ALERT_BAD_CERTIFICATE, "wrong name")
    testing.expect(t, wrong == .VALID && wrong_name, "a valid chain for another name")
    stranger, stranger_name :: refused(t, STRANGER_CHAIN[0..<STRANGER_CHAIN.count], STRANGER_KEY[0..<32], tls.ALERT_UNKNOWN_CA, "unknown root")
    testing.expect(t, stranger == .UNKNOWN_ISSUER && !stranger_name, "a chain from a root not trusted")
    // A chain whose leaf's key isn't the one the server signs with: its CertificateVerify doesn't verify
    mismatched, mismatched_name :: refused(t, P256_CHAIN[0..<P256_CHAIN.count], EXPIRED_KEY[0..<32], tls.ALERT_DECRYPT_ERROR, "another key")
    testing.expect(t, mismatched == .VALID && !mismatched_name, "a CertificateVerify by another key")
    return .Ok
}

refuses_a_changed_record #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    pair :: make_pair(P256_CHAIN[0..<P256_CHAIN.count], .P256, P256_KEY[0..<32])
    defer runtime.free(pair)
    pump(pair)
    testing.require(t, tls.connected(&pair.server), "connected")?
    _ = tls.write(&pair.client, string_bytes("changed on its way"))
    out :: tls.output(&pair.client)
    copy : u8[256]
    for byte, i in out {
        if i < copy.count {
            copy[i] = byte
        }
    }
    count :: if out.count < copy.count { out.count } else { copy.count }
    tls.sent(&pair.client, out.count)
    if count > 10 {
        copy[10] = copy[10] ~ 1
    }
    _ = tls.received(&pair.server, tls.range(copy, 0, count))
    testing.expect(t, tls.ended(&pair.server) && pair.server.ending == .Refused && pair.server.alert == tls.ALERT_BAD_RECORD_MAC,
        "the server refuses a record whose tag doesn't match")
    return .Ok
}

updates_keys_and_closes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    pair :: make_pair(P256_CHAIN[0..<P256_CHAIN.count], .P256, P256_KEY[0..<32])
    defer runtime.free(pair)
    pump(pair)
    testing.require(t, tls.connected(&pair.client) && tls.connected(&pair.server), "connected")?
    server_changes :: pair.server.read_changes
    client_changes :: pair.client.read_changes
    tls.update_keys(&pair.client, true)
    pump(pair)
    testing.expect(t, pair.server.read_changes == server_changes + 1, "the server reads with the client's next keys")
    testing.expect(t, pair.client.read_changes == client_changes + 1, "and, asked to, moves its own on")
    exchange(t, pair, "after a KeyUpdate")
    _ = tls.write(&pair.server, string_bytes("last words"))
    tls.close(&pair.server)
    pump(pair)
    testing.expect(t, tls.ended(&pair.client) && pair.client.ending == .Closed, "close_notify ends the client's side as closed")
    got : u8[32]
    count :: tls.read(&pair.client, got[0..<got.count])
    testing.expect(t, count <= got.count && string_of(&got[0], count) == "last words", "what came before it is read")
    return .Ok
}

refuses_to_serve_without_a_chain #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    pair :: make_pair(P256_CHAIN[0..<0], .P256, P256_KEY[0..<32])
    defer runtime.free(pair)
    pump(pair)
    testing.expect(t, tls.ended(&pair.server) && pair.server.ending == .Refused && pair.server.alert == tls.ALERT_INTERNAL_ERROR,
        "a server whose identity has no chain ends rather than send an empty Certificate")
    testing.expect(t, tls.ended(&pair.client) && !tls.connected(&pair.client), "and the client doesn't connect")
    return .Ok
}

/** Bytes made at random, as a ClientHello's or a ServerHello's, end a connection or wait, without harm. */
takes_any_bytes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    return testing.check_property(t, any_bytes)
}

any_bytes : testing.Property : fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    pair :: make_pair(P256_CHAIN[0..<P256_CHAIN.count], .P256, P256_KEY[0..<32])
    defer runtime.free(pair)
    bytes :: testing.draw_bytes(source, 600)
    copy : u8[600]
    for byte, i in bytes {
        if i < copy.count {
            copy[i] = byte
        }
    }
    count :: if bytes.count < copy.count { bytes.count } else { copy.count }
    // Often a handshake record's header, so the parsers past it are reached
    if count >= 9 && testing.draw_bool(source) {
        copy[0] = tls.CONTENT_HANDSHAKE
        copy[1] = 3
        copy[2] = 3
        copy[3] = cast[u8]((count - 5) >> 8)
        copy[4] = cast[u8](count - 5)
        copy[5] = if testing.draw_bool(source) { tls.CLIENT_HELLO } else { tls.SERVER_HELLO }
        copy[6] = 0
        copy[7] = cast[u8]((count - 9) >> 8)
        copy[8] = cast[u8](count - 9)
    }
    _ = tls.received(&pair.server, tls.range(copy, 0, count))
    _ = tls.received(&pair.client, tls.range(copy, 0, count))
    return .Ok
}
