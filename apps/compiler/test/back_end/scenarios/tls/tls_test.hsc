package tls_test

import runtime from "base"
import crypto from "std"
import testing from "std"
import tls from "std"

/*
 * std/tls: RFC 8448's Simple 1-RTT Handshake replayed, as a client from its ClientHello on and as a server up to its
 * ServerHello, each record and secret checked against the RFC's (rfc8448.hsc).
 */

/**
 * Tell whether a secret's first bytes are the bytes expected.
 *
 * @param secret The secret.
 * @param expected The bytes.
 * @return True if they're the same, as many as expected has.
 */
same_secret #constant_time :: fn(secret: ptr[tls.Secret], expected: u8[]) -> bool {
    copy : crypto.SecretByte[tls.HASH_MOST]
    for i in 0..<tls.HASH_MOST {
        copy[i] = cast[crypto.SecretByte](secret[i])
    }
    return expected.count <= tls.HASH_MOST && crypto.equal(copy[0..<expected.count], expected)
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

replays_rfc8448_as_a_client #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    connection :: runtime.new(tls.Connection)
    defer runtime.free(connection)
    key : crypto.X25519SecretKey
    for byte, i in CLIENT_SECRET_KEY {
        key[i] = byte
    }
    tls.client_after_hello(connection, CLIENT_HELLO[0..<CLIENT_HELLO.count], &key)
    _ = tls.received(connection, SERVER_HELLO_RECORD[0..<SERVER_HELLO_RECORD.count])
    testing.expect(t, same_secret(&connection.handshake_secret, HANDSHAKE_SECRET[0..<32]), "the handshake secret")
    testing.expect(t, same_secret(&connection.client_handshake_secret, CLIENT_HANDSHAKE_SECRET[0..<32]), "the client's handshake traffic secret")
    testing.expect(t, same_secret(&connection.server_secret, SERVER_HANDSHAKE_SECRET[0..<32]), "the server's handshake traffic secret")
    testing.expect(t, same_secret(&connection.master_secret, MASTER_SECRET[0..<32]), "the master secret")
    testing.expect(t, same(connection.read.iv[0..<12], SERVER_HANDSHAKE_IV[0..<12]), "the server's handshake IV")
    _ = tls.received(connection, SERVER_HANDSHAKE_RECORD[0..<SERVER_HANDSHAKE_RECORD.count])
    testing.note(t, "state %, ending %, alert %", connection.state, connection.ending, connection.alert)
    testing.require(t, tls.connected(connection), "connected once the server's handshake records are taken")?
    testing.end_note(t)
    testing.expect(t, same_secret(&connection.client_secret, CLIENT_APPLICATION_SECRET[0..<32]), "the client's application traffic secret")
    testing.expect(t, same_secret(&connection.server_secret, SERVER_APPLICATION_SECRET[0..<32]), "the server's application traffic secret")
    testing.expect(t, same_secret(&connection.exporter_secret, EXPORTER_SECRET[0..<32]), "the exporter master secret")
    testing.expect(t, same(tls.output(connection), CLIENT_FINISHED_RECORD[0..<CLIENT_FINISHED_RECORD.count]), "the client's Finished record")
    tls.sent(connection, tls.output(connection).count)
    testing.expect_eq(t, tls.write(connection, APPLICATION_DATA[0..<APPLICATION_DATA.count]), APPLICATION_DATA.count, "the data written")
    testing.expect(t, same(tls.output(connection), CLIENT_DATA_RECORD[0..<CLIENT_DATA_RECORD.count]), "the client's application data record")
    tls.sent(connection, tls.output(connection).count)
    _ = tls.received(connection, TICKET_RECORD[0..<TICKET_RECORD.count])
    testing.expect(t, tls.connected(connection), "a NewSessionTicket passed over")
    _ = tls.received(connection, SERVER_DATA_RECORD[0..<SERVER_DATA_RECORD.count])
    back : u8[64]
    count :: tls.read(connection, back[0..<back.count])
    testing.expect(t, count <= back.count && same(back[0..<count], APPLICATION_DATA[0..<APPLICATION_DATA.count]),
        "the server's application data read")
    tls.close(connection)
    testing.expect(t, same(tls.output(connection), CLIENT_ALERT_RECORD[0..<CLIENT_ALERT_RECORD.count]), "the client's close_notify record")
    return .Ok
}

/** A chain to point an identity at, on the heap, as a connection keeps a pointer to it. */
Chain :: struct {
    bytes : u8[5],
}

replays_rfc8448_as_a_server #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    connection :: runtime.new(tls.Connection)
    defer runtime.free(connection)
    // Any P-256 key and any DER as a chain: only the ServerHello and the secrets are the RFC's
    identity := tls.Identity.{kind = .P256}
    chain :: runtime.new(Chain)
    defer runtime.free(chain)
    chain.bytes = u8.[0x30, 0x03, 0x02, 0x01, 0x00]
    identity.chain = cast[rawptr](&chain.bytes[0])
    identity.chain_bytes = chain.bytes.count
    for i in 0..<32 {
        identity.p256[i] = cast[u8](i + 1)
    }
    tls.server(connection, &identity)
    server_random : u8[32]
    for i in 0..<32 {
        server_random[i] = SERVER_HELLO[6 + i]
    }
    key : crypto.X25519SecretKey
    for byte, i in SERVER_SECRET_KEY {
        key[i] = byte
    }
    tls.server_with_keys(connection, &server_random, &key)
    _ = tls.received(connection, CLIENT_HELLO_RECORD[0..<CLIENT_HELLO_RECORD.count])
    testing.note(t, "state %, ending %, alert %", connection.state, connection.ending, connection.alert)
    out :: tls.output(connection)
    testing.expect(t, out.count >= SERVER_HELLO_RECORD.count && same(out[0..<SERVER_HELLO_RECORD.count], SERVER_HELLO_RECORD[0..<SERVER_HELLO_RECORD.count]),
        "the ServerHello's record")
    testing.end_note(t)
    testing.expect(t, same_secret(&connection.handshake_secret, HANDSHAKE_SECRET[0..<32]), "the handshake secret")
    testing.expect(t, same_secret(&connection.client_handshake_secret, CLIENT_HANDSHAKE_SECRET[0..<32]), "the client's handshake traffic secret")
    testing.expect(t, same_secret(&connection.master_secret, MASTER_SECRET[0..<32]), "the master secret")
    return .Ok
}
