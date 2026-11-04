/**
 * Building text in a fixed buffer, without an allocator: for kernels, interrupt handlers and
 * anything else that can't allocate. append_format formats values of any type into it, the way
 * loggers format their parameters, from their type information.
 */
package text_buffer

import tiers from "std"

/** This package's tier: it never allocates or makes system calls, so it works anywhere, interrupt handlers too. */
PACKAGE_TIER :: tiers.Tier.Freestanding
