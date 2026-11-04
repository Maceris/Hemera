/**
 * Working with strings: formatting into new strings, parsing numbers, and finding, comparing,
 * trimming and splitting text. Only format and clone allocate.
 */
package strings

import tiers from "std"

/** This package's tier: format and clone allocate, so it needs an Allocator in context. */
PACKAGE_TIER :: tiers.Tier.Allocating
