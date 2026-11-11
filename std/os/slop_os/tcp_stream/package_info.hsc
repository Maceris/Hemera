/**
 * The tcp_stream protocol, for a TCP connection's channel between a program on SlopOS and the network service.
 */
package tcp_stream

import tiers from "std"

/** The package's tier, Os: its code makes system calls, so it needs an operating system. */
PACKAGE_TIER :: tiers.Tier.Os
