/**
 * The process manager's protocol, which std/os's launch speaks on SlopOS.
 */
package process_manager

import tiers from "std"

/** The package's tier, Os: its code makes system calls, so it needs an operating system. */
PACKAGE_TIER :: tiers.Tier.Os
