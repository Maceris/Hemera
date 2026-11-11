/*
 * std/crypto's DER, PEM and X.509: chains from a test authority (certificates.hsc, made by
 * make_certificates.py) validated to their anchors, good ones with RSA, RSA-PSS, P-256 and Ed25519
 * signatures and in any order, and bad ones refused for the reason each is bad; host names matched, base64
 * strict, and DER's times and integers read as RFC 5280 and X.690 say. Run with hemera --test.
 */
package x509_test

import crypto from "std"
import testing from "std"

// 2026-06-01T00:00:00Z, when every chain here but the expired and future ones is valid
NOW :: 1780272000

/** Room for a chain's or the anchors' DER. */
Der :: struct {
    bytes: u8[16384],
    count: usize,
}

/**
 * Decode PEM certificates into DER one after another.
 *
 * @param text The PEM.
 * @param into Where the DER goes; its count is set, 0 when the PEM didn't decode.
 */
der_of :: fn(text: string, into: ptr[mut Der]) {
    into.count = crypto.pem_certificates(bit_cast[u8[]](text), into.bytes) or_else 0
}

verdict_of :: fn(chain_text: string, purpose: crypto.X509Purpose) -> crypto.X509Verdict {
    anchors := Der.{}
    chain := Der.{}
    der_of(ANCHORS, &anchors)
    der_of(chain_text, &chain)
    return crypto.x509_verify_chain(chain.bytes[0..<chain.count % 16385], anchors.bytes[0..<anchors.count % 16385], NOW, purpose)
}

validates_good_chains #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, verdict_of(RSA_CHAIN, .SERVER) == .VALID, "a P-256 leaf by an RSA-PSS-signed intermediate by an RSA root")
    testing.expect(t, verdict_of(P256_CHAIN, .SERVER) == .VALID, "ECDSA all the way to a P-256 root")
    testing.expect(t, verdict_of(ED25519_CHAIN, .SERVER) == .VALID, "a leaf signed by an Ed25519 root")
    testing.expect(t, verdict_of(SHUFFLED_CHAIN, .SERVER) == .VALID, "a chain with a certificate off its path, out of order")
    testing.expect(t, verdict_of(CONSTRAINED_GOOD_CHAIN, .SERVER) == .VALID, "names within a CA's name constraints")
    testing.expect(t, verdict_of(CLIENT_ONLY_CHAIN, .CLIENT) == .VALID, "a client's certificate, for a client")
    testing.expect(t, verdict_of(CLIENT_ONLY_CHAIN, .ANY) == .VALID, "and for any purpose")
    return .Ok
}

refuses_bad_chains #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, verdict_of(EXPIRED_CHAIN, .SERVER) == .EXPIRED, "an expired leaf")
    testing.expect(t, verdict_of(FUTURE_CHAIN, .SERVER) == .EXPIRED, "a leaf not yet valid")
    testing.expect(t, verdict_of(NOT_CA_CHAIN, .SERVER) == .NOT_A_CA, "an issuer that isn't a CA")
    testing.expect(t, verdict_of(NO_CERT_SIGN_CHAIN, .SERVER) == .NOT_A_CA, "an issuer whose key usage hasn't keyCertSign")
    testing.expect(t, verdict_of(PATH_TOO_LONG_CHAIN, .SERVER) == .PATH_TOO_LONG, "a CA below one whose path length is 0")
    testing.expect(t, verdict_of(CONSTRAINED_DNS_CHAIN, .SERVER) == .NAME_CONSTRAINTS, "a DNS name outside the permitted subtrees")
    testing.expect(t, verdict_of(CONSTRAINED_EXCLUDED_CHAIN, .SERVER) == .NAME_CONSTRAINTS, "a DNS name in an excluded subtree")
    testing.expect(t, verdict_of(CONSTRAINED_IP_CHAIN, .SERVER) == .NAME_CONSTRAINTS, "an IP address outside the permitted range")
    testing.expect(t, verdict_of(CLIENT_ONLY_CHAIN, .SERVER) == .PURPOSE, "a client's certificate, for a server")
    testing.expect(t, verdict_of(KEY_USAGE_CHAIN, .SERVER) == .KEY_USAGE, "a leaf that can't sign")
    testing.expect(t, verdict_of(CRITICAL_CHAIN, .SERVER) == .MALFORMED, "an unknown critical extension")
    testing.expect(t, verdict_of(FORGED_CHAIN, .SERVER) == .BAD_SIGNATURE, "a changed signature")
    testing.expect(t, verdict_of(UNKNOWN_CHAIN, .SERVER) == .UNKNOWN_ISSUER, "a root that isn't an anchor")
    testing.expect(t, verdict_of(SMALL_RSA_CHAIN, .SERVER) == .UNSUPPORTED, "an RSA key of 1024 bits")
    anchors := Der.{}
    der_of(ANCHORS, &anchors)
    testing.expect(t, crypto.x509_verify_chain(anchors.bytes[0..<0], anchors.bytes[0..<anchors.count % 16385], NOW, .SERVER) == .BAD_CHAIN,
        "an empty chain")
    testing.expect(t, crypto.x509_verify_chain(anchors.bytes[0..<10], anchors.bytes[0..<anchors.count % 16385], NOW, .SERVER) == .MALFORMED,
        "a chain cut short")
    return .Ok
}

matches_host_names #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    chain := Der.{}
    der_of(P256_CHAIN, &chain)
    first := crypto.der_next(chain.bytes[0..<chain.count % 16385]) or_else crypto.DerElement.{}
    leaf := crypto.x509_parse(first.whole) or_else crypto.X509Certificate.{}
    testing.expect(t, leaf.der.count > 0, "the leaf is read")
    testing.expect(t, crypto.x509_matches_host(&leaf, "example.test"), "its DNS name")
    testing.expect(t, crypto.x509_matches_host(&leaf, "EXAMPLE.test."), "ignoring case and a trailing dot")
    testing.expect(t, crypto.x509_matches_host(&leaf, "a.wild.test"), "a wildcard's one label")
    testing.expect(t, !crypto.x509_matches_host(&leaf, "a.b.wild.test"), "but not two")
    testing.expect(t, !crypto.x509_matches_host(&leaf, "wild.test"), "or none")
    testing.expect(t, !crypto.x509_matches_host(&leaf, "other.test"), "another name")
    testing.expect(t, crypto.x509_matches_host(&leaf, "192.0.2.1"), "its IPv4 address")
    testing.expect(t, crypto.x509_matches_host(&leaf, "2001:db8::1"), "its IPv6 address, written short")
    testing.expect(t, crypto.x509_matches_host(&leaf, "2001:0db8:0:0:0:0:0:1"), "and long")
    testing.expect(t, !crypto.x509_matches_host(&leaf, "192.0.2.2"), "not another address")
    testing.expect(t, !crypto.x509_matches_host(&leaf, "2001:db8::2"), "of either kind")
    return .Ok
}

decodes_base64_strictly #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    output : u8[64]
    count := crypto.base64_decode(bit_cast[u8[]]("aGVs\r\nbG8="), output) or_else 99
    testing.expect(t, count == 5 && output[0] == cast[u8]('h') && output[4] == cast[u8]('o'), "hello, across a line break")
    testing.expect(t, crypto.base64_decode(bit_cast[u8[]]("aGVsbG9="), output) == null, "left-over bits that aren't 0 are refused")
    testing.expect(t, crypto.base64_decode(bit_cast[u8[]]("aGVsbG8"), output) == null, "a group cut short")
    testing.expect(t, crypto.base64_decode(bit_cast[u8[]]("aG=sbG8="), output) == null, "padding before the end")
    testing.expect(t, crypto.base64_decode(bit_cast[u8[]]("aGVs-G8="), output) == null, "a character outside the alphabet")
    text : u8[64]
    written := crypto.base64_encode(bit_cast[u8[]]("hello"), text) or_else 0
    testing.expect(t, written == 8 && text[6] == cast[u8]('8') && text[7] == cast[u8]('='), "hello encodes to aGVsbG8=")
    return .Ok
}

// A time's element: its tag, then its text
time_of :: fn(tag: u8, text: string, buffer: ptr[mut u8[32]]) -> crypto.DerElement {
    buffer[0] = tag
    buffer[1] = cast[u8](text.count)
    for c, i in text {
        if i < 30 {
            buffer[2 + i] = cast[u8](c)
        }
    }
    return crypto.der_next(buffer[0..<(2 + text.count) % 33]) or_else crypto.DerElement.{}
}

reads_der #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    buffer : u8[32]
    testing.expect(t, crypto.der_time(time_of(crypto.DER_UTC_TIME, "491231235959Z", &buffer)) == 2524607999, "a UTCTime's 49 is 2049")
    testing.expect(t, crypto.der_time(time_of(crypto.DER_UTC_TIME, "500101000000Z", &buffer)) == -631152000, "and its 50 1950")
    testing.expect(t, crypto.der_time(time_of(crypto.DER_GENERALIZED_TIME, "21000229000000Z", &buffer)) == null, "2100 isn't a leap year")
    testing.expect(t, crypto.der_time(time_of(crypto.DER_GENERALIZED_TIME, "20240229120000Z", &buffer)) == 1709208000, "2024 is")
    testing.expect(t, crypto.der_time(time_of(crypto.DER_UTC_TIME, "491231235960Z", &buffer)) == null, "a leap second is refused")
    padded := crypto.der_next(u8.[0x02, 0x02, 0x00, 0x7f]) or_else crypto.DerElement.{}
    testing.expect(t, crypto.der_integer(padded) == null, "an INTEGER padded with a zero it doesn't need")
    long := u8.[0x04, 0x81, 0x05, 1, 2, 3, 4, 5]
    testing.expect(t, crypto.der_next(long) == null, "a long-form length under 128")
    indefinite := u8.[0x30, 0x80, 0, 0]
    testing.expect(t, crypto.der_next(indefinite) == null, "an indefinite length")
    return .Ok
}
