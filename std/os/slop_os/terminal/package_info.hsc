/**
 * The terminal protocol, which programs on SlopOS write to and read typed input from.
 */
package terminal

import tiers from "std"

/** The package's tier, Os: its code makes system calls, so it needs an operating system. */
PACKAGE_TIER :: tiers.Tier.Os
