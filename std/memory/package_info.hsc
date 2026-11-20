/**
 * Memory related utilities: arenas, shared ownership, an allocator that fails on purpose for testing, copying between
 * slices, and ByteCount, a number of bytes.
 */
package memory

import tiers from "std:tiers"

/** This package's tier: it allocates, so it needs an Allocator in context, but makes no system calls. */
PACKAGE_TIER :: tiers.Tier.Allocating
