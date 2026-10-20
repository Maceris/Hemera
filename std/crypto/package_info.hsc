/*
 * Cryptography (docs/memory.md, Secrets): hashes, message authentication and key derivation, and later
 * encryption, key agreement, signatures and password hashing. Freestanding: callers pass every buffer,
 * so a kernel can use it. What's secret is #secret, and every function working with secrets is
 * #constant_time, so the compiler checks none decides timing.
 */
package crypto

import tiers from "std"

PACKAGE_TIER :: tiers.Tier.Freestanding
