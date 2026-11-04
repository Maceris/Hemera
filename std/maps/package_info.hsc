/**
 * Maps from keys to values, which grow as they're filled, so they need an allocator in context.
 */
package maps

import tiers from "std"

/** This package's tier: maps grow with context.allocator, so it needs an Allocator in context. */
PACKAGE_TIER :: tiers.Tier.Allocating
