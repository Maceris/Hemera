/**
 * Regular expressions in linear time: a pattern compiled to a program that a Pike VM runs over the text, every place in
 * the program at once, so no pattern takes more than time proportional to the text's length times the pattern's size.
 */
package regex

import tiers from "std"

/** This package's tier: compiling and matching allocate, so it needs an Allocator in context, but no system calls. */
PACKAGE_TIER :: tiers.Tier.Allocating
