/**
 * The tcp_listener protocol, for a listening TCP port's channel between a program on SlopOS and the network service.
 */
package tcp_listener

import tiers from "std"

/** The package's tier, Os: its code makes system calls, so it needs an operating system. */
PACKAGE_TIER :: tiers.Tier.Os
