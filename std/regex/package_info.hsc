/*
 * Regular expressions in linear time: a pattern compiled to a program that a Pike VM runs over the text, every place in
 * the program at once, so no pattern takes more than time proportional to the text's length times the pattern's size.
 */
package regex

import tiers from "std"

PACKAGE_TIER :: tiers.Tier.Allocating
