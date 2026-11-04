/**
 * Tests: functions marked #test, the assertions they make, and a runner that finds them through reflection and
 * reports what failed, with messages, locations and the values involved (docs/testing.md).
 *
 * Nothing allocates and nothing calls the system: a test's failures go into fixed space in its T, and the runner writes
 * through a Reporter the program gives, so tests run in freestanding code, a kernel's included.
 */
package testing

import tiers from "std"

/** The package's tier, Freestanding: it needs only base and text_buffer, and allocates nothing. */
PACKAGE_TIER :: tiers.Tier.Freestanding
