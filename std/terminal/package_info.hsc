/**
 * A terminal, as a program uses one: a client of the terminal protocol, writing styled text and reading typed input
 * one event at a time, and a line editor on it, with a cursor, history and completion.
 */
package terminal

import tiers from "std"

/** This package's tier: it talks to a terminal through system calls. */
PACKAGE_TIER :: tiers.Tier.Os
