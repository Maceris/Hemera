/*
 * Time related utilities. Freestanding: time comes from context.clock, which every context has (a
 * freestanding program's may be NO_CLOCK, or its own), and the rest is arithmetic.
 */
package time

import tiers from "std"

PACKAGE_TIER :: tiers.Tier.Freestanding
