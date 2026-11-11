/**
 * Linear algebra for graphics and geometry, over the language's own vectors and matrices (docs/types.md, Arrays as
 * Vectors and Matrices): dot and cross products, lengths, reflection and refraction on fixed arrays of numbers;
 * rotations as quaternions; determinants and inverses; and the transforms a renderer needs, in Vulkan's conventions,
 * with OpenGL's beside them.
 */
package linear_algebra

import tiers from "std"

/** The package's tier: Freestanding, as it needs nothing but arithmetic. */
PACKAGE_TIER :: tiers.Tier.Freestanding
