/**
 * A logger with more on each line than the standard one: the time, where the message was logged
 * from, and the thread.
 */
package logger

import tiers from "std"

/** This package's tier: it reads the clock and writes to standard output or error, which take system calls. */
PACKAGE_TIER :: tiers.Tier.Os
