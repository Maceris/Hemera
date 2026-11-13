/**
 * NTP (RFC 5905) as a client, secured with NTS (RFC 8915): the messages of NTS Key Establishment, which runs over TLS
 * 1.3 (std/tls) with ALPN's "ntske/1", the keys it exports, and NTPv4 requests authenticated with the cookies it gives,
 * their answers checked and turned into an offset and a round-trip delay. Nothing in it waits, allocates or makes a
 * system call: its caller moves the bytes, over TCP for NTS-KE and UDP for NTP, and reads the clock.
 *
 * Its AEAD is AEAD_AES_SIV_CMAC_256, the one RFC 8915 requires; its next protocol is NTPv4. An answer is taken only
 * if it's to the request made, by its unique identifier, and its authenticator opens with the server's key; plain,
 * unauthenticated NTP isn't spoken.
 */
package ntp

import tiers from "std"

/** The package's tier, Freestanding: its caller gives every buffer, and its randomness comes from context.random. */
PACKAGE_TIER :: tiers.Tier.Freestanding
