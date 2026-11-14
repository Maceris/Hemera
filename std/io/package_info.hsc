/**
 * Standard input and output.
 */
package io

import tiers from "std:tiers"

/** This package's tier: it writes to standard output and error, which take system calls. */
PACKAGE_TIER :: tiers.Tier.Os
