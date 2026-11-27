/**
 * The query protocol: a live query's channel, and the terms of a predicate over a volume's indexes.
 */
package query

import tiers from "std:tiers"

/** The package's tier, Os: its code makes system calls, so it needs an operating system. */
PACKAGE_TIER :: tiers.Tier.Os
