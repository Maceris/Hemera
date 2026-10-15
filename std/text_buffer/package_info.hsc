/*
 * Building text in a fixed buffer, without an allocator: for kernels, interrupt handlers and
 * anything else that can't allocate.
 */
package text_buffer

import tiers from "std"

PACKAGE_TIER :: tiers.Tier.Freestanding
