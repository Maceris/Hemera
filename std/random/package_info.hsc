/**
 * Random numbers from context.random: bytes, integers, and integers in a range without bias.
 */
package random

import tiers from "std"

/** This package's tier: it needs only base, drawing from whatever generator context.random has. */
PACKAGE_TIER :: tiers.Tier.Freestanding
