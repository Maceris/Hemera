/*
 * Containers that need no allocator: their storage is part of them, or of what they hold. For code
 * with no heap, like a kernel early in boot, and anywhere a fixed limit is fine.
 */
package containers

import tiers from "std"

PACKAGE_TIER :: tiers.Tier.Freestanding
