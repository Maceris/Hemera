/**
 * The datagrams protocol, for a UDP socket's channel between a program on SlopOS and the network service.
 */
package datagrams

import tiers from "std"

/** The package's tier, Os: its code makes system calls, so it needs an operating system. */
PACKAGE_TIER :: tiers.Tier.Os
