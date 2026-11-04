/**
 * The lifecycle channel, a launcher's end of it, and a program's view of being asked to stop.
 */
package lifecycle

import tiers from "std"

/** The package's tier, Os: its code makes system calls, so it needs an operating system. */
PACKAGE_TIER :: tiers.Tier.Os
