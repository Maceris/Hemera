/**
 * Coverage-guided fuzzing of property tests (docs/testing.md, Fuzzing): a program hemera --fuzz builds runs one of a
 * package's property tests on input after input, each made by changing one that reached code no other had, so it
 * searches the test's inputs by what they reach rather than at random. It keeps those inputs, its corpus, in a folder,
 * and a failing input, made as small as it can be, beside them.
 *
 * It reads and writes files, so it's for a hosted program, under an operating system.
 */
package fuzzing

import tiers from "std"

/** The package's tier, Os: it keeps its corpus in files. */
PACKAGE_TIER :: tiers.Tier.Os
