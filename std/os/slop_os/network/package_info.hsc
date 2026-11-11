/**
 * The network protocol, through which programs on SlopOS reach the network service.
 */
package network

import tiers from "std"

/** The package's tier, Os: its code makes system calls, so it needs an operating system. */
PACKAGE_TIER :: tiers.Tier.Os
