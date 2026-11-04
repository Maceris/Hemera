/**
 * Fiber related implementations, including a default scheduler: fiber pools that carriers share.
 */
package fiber

import tiers from "std"

/** This package's tier: pools and fibers are allocated, but no system calls are made directly. */
PACKAGE_TIER :: tiers.Tier.Allocating
