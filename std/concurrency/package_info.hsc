/**
 * Tasks that need to run concurrently: locks, conditions and channels shared by threads and fibers, and spin locks
 * taken in a checked order.
 */
package concurrency

import tiers from "std"

/** This package's tier: it needs only base, since waiting parks through the runtime. */
PACKAGE_TIER :: tiers.Tier.Freestanding
