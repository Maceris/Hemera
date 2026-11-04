/**
 * The grant protocol, which a directory's Grant gives and its Link takes, on SlopOS.
 */
package grant

import tiers from "std"

/** The package's tier, Os: its code makes system calls, so it needs an operating system. */
PACKAGE_TIER :: tiers.Tier.Os
