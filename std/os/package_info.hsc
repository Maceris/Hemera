/**
 * Access to the operating system.
 */
package os

import tiers from "std"

/** The package's tier: Os, since it makes system calls, so only packages of that tier can import it. */
PACKAGE_TIER :: tiers.Tier.Os
