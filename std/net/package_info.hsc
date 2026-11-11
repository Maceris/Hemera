/**
 * The network, for programs on SlopOS: TCP connections and listeners, and UDP sockets, through a connection to the
 * network service, which is the only way a program reaches the network. There's no socket API; each connection is a
 * channel, and its data is in memory the program and the service share.
 */
package net

import tiers from "std"

/** The package's tier: Os, since it makes system calls. */
PACKAGE_TIER :: tiers.Tier.Os
