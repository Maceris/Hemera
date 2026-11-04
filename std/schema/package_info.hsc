/**
 * A type's schema: its description serialized the same way in every build and every program, and the hash that names
 * it.
 */
package schema

import tiers from "std"

/** This package's tier: it allocates, so it needs an Allocator in context, but makes no system calls. */
PACKAGE_TIER :: tiers.Tier.Allocating
