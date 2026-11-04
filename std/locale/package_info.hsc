/**
 * Locales: how human-facing text writes numbers, dates and times, as a context value, and formatters that read it.
 * Nothing allocates.
 */
package locale

import tiers from "std"

/** This package's tier: it needs only base, and allocates nothing. */
PACKAGE_TIER :: tiers.Tier.Freestanding
