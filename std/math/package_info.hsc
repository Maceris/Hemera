/**
 * Float math: the elementary and special functions, from exp to gamma, for f32 and f64, written in Hemera so they give
 * the same bits on every target and need nothing linked (docs/types.md, Floats). What a CPU does in an instruction,
 * like floor and fused multiply-add, is in base/intrinsics.
 *
 * The f64 functions are fdlibm's (Sun Microsystems), as FreeBSD's msun and musl carry them, each saying where it's from
 * with //SPEC:: within 1 ulp, but for the few whose documentation says more, held to it by tests against references in
 * far more precision. An f32 function works in f64 and rounds once to f32, which is within 1 ulp too, and nearly
 * always correctly rounded.
 */
package math

import tiers from "std"

/** The package's tier: Freestanding, as it needs nothing but arithmetic. */
PACKAGE_TIER :: tiers.Tier.Freestanding
