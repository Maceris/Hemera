/**
 * The tiers of package that indicate what a std package needs from the
 * system it runs on and which packages it is allowed to import.
 */
package tiers

/** This package's own tier: it needs only base, so any package may import it. */
PACKAGE_TIER :: Tier.Freestanding
