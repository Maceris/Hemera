/**
 * Fast float math: std/math's functions by the same names, for f32, f64 and vectors of either, trading accuracy for
 * speed. Each says its bound; where one has a kernel here it's within 3.5 ulp, and the others are std/math's. Like
 * std/math, it's written in Hemera, so it gives the same bits on every target.
 *
 * f32's kernels are f32 throughout: SLEEF's 3.5-ulp algorithms and coefficients (lanes_32.hsc), for exp, exp2, log,
 * log2, sin, cos, tan, asin, acos, atan, atan2 and cube_root. f64's (lanes_64.hsc), for exp, exp2, log, log2, sin, cos,
 * asin, acos, atan and atan2, are SLEEF's shapes with series worked out for 53 bits. Each is one reduction and one
 * polynomial with fused multiply-adds, branch-free, so it works lane by lane on a vector[T, n]; a lane its reduction
 * doesn't cover, like an angle past 39000 for f32's trigonometric ones, is worked out again by std/math's function.
 */
package fast

import tiers from "std"

/** The package's tier: Freestanding, as it needs nothing but arithmetic. */
PACKAGE_TIER :: tiers.Tier.Freestanding
