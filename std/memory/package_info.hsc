/**
 * Memory related utilities: arenas, shared ownership, an allocator that fails on purpose for testing, and ByteCount,
 * a number of bytes.
 */
package memory

import tiers from "std"

/** This package's tier: it allocates, so it needs an Allocator in context, but makes no system calls. */
PACKAGE_TIER :: tiers.Tier.Allocating
