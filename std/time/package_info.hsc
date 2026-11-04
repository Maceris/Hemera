/**
 * Clocks, calendar dates and time zones.
 *
 * Freestanding: time comes from context.clock, which every context has (a freestanding program's may be NO_CLOCK, or
 * its own), and the rest is arithmetic. Dates are on the proleptic Gregorian calendar in UTC. Time zones, which
 * allocate, are time_zones'.
 */
package time

import tiers from "std"

/** The package's tier, Freestanding: it needs only base, and no operating system. */
PACKAGE_TIER :: tiers.Tier.Freestanding
