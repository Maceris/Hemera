/**
 * Cryptography: hashes, message authentication, key derivation, encryption, key agreement, signatures and password
 * hashing.
 *
 * Freestanding: callers pass every buffer, so a kernel can use it. What's secret is #secret (docs/memory.md,
 * Secrets), and every function working with secrets is #constant_time, so the compiler checks that none decides
 * timing.
 */
package crypto

import tiers from "std"

/** The package's tier, Freestanding: it needs only base, and allocates nothing. */
PACKAGE_TIER :: tiers.Tier.Freestanding
