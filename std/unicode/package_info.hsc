/**
 * Unicode: UTF-8, grapheme clusters (UAX #29), the columns text takes on a terminal, normalization (UAX #15) and case
 * folding, from tables generated from the Unicode Character Database. Nothing allocates.
 */
package unicode

import tiers from "std"

/** The package's tier, Freestanding: it needs only base, and allocates nothing. */
PACKAGE_TIER :: tiers.Tier.Freestanding
