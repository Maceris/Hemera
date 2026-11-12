/**
 * TLS 1.3 (RFC 8446), client and server, over any byte stream: a Connection is a state machine its caller feeds the bytes
 * that arrive (received) and takes the bytes to send from (output, sent), reading and writing plaintext once it's
 * connected. Nothing in it waits, allocates or makes a system call, so it runs over SlopOS's TCP (std/net's tls), in a
 * test's memory, or anywhere else.
 *
 * Its suites are TLS_AES_128_GCM_SHA256, which RFC 8446 makes mandatory, TLS_AES_256_GCM_SHA384 and
 * TLS_CHACHA20_POLY1305_SHA256; its key exchanges X25519 and P-256 (secp256r1), with HelloRetryRequest for whichever the
 * other side didn't offer first; its signatures ECDSA on P-256 and P-384, RSA-PSS and Ed25519, of which a server signs
 * with ECDSA on P-256 or Ed25519. A client checks the server's certificate chain against trust anchors it's given, and
 * the leaf against the host's name, as part of connecting (decisions/0188, 13f); connecting without that is
 * client_unverified, a function of another name. There's no resumption, no 0-RTT data, and no client certificates: a
 * client asked for one says it has none.
 */
package tls

import tiers from "std"

/** The package's tier, Freestanding: its caller gives every buffer, and its randomness comes from context.random. */
PACKAGE_TIER :: tiers.Tier.Freestanding
