/*
 * Maps from keys to values, which grow as they're filled, so they need an allocator in context.
 */
package maps

import tiers from "std"

PACKAGE_TIER :: tiers.Tier.Allocating
