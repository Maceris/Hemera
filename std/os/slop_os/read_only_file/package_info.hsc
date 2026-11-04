/**
 * The read_only_file protocol, which std/os's files speak on SlopOS.
 */
package read_only_file

import tiers from "std"

/** The package's tier, Os: its code makes system calls, so it needs an operating system. */
PACKAGE_TIER :: tiers.Tier.Os
