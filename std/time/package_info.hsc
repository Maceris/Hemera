/**
 * Clocks, calendar dates and time zones.
 *
 * Freestanding: time comes from context.clock, which every context has (a freestanding program's may be NO_CLOCK, or
 * its own), and the rest is arithmetic. Dates are on the proleptic Gregorian calendar in UTC, and time zones are read
 * from TZif data (RFC 8536) that the caller supplies.
 */
package time

import tiers from "std"

/** The package's tier, Freestanding: it needs only base, and no operating system. */
PACKAGE_TIER :: tiers.Tier.Freestanding
