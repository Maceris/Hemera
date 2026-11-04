/**
 * The file_set protocol: a directory and a pattern, for globs.
 */
package file_set

import tiers from "std"

/** The package's tier, Os: its code makes system calls, so it needs an operating system. */
PACKAGE_TIER :: tiers.Tier.Os
