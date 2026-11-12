/**
 * Float math: the elementary and special functions, from exp to gamma, for f32 and f64, written in Hemera so they give
 * the same bits on every target and need nothing linked (docs/types.md, Floats). What a CPU does in an instruction,
 * like floor and fused multiply-add, is in base/intrinsics.
 *
 * The f64 functions are fdlibm's (Sun Microsystems), as FreeBSD's msun and musl carry them, each saying where it's from
 * with //SPEC:: within 1 ulp, but for the few whose documentation says more, held to it by tests against references in
 * far more precision.
 *
 * Every function also takes vector[f32, n] and vector[f64, n], lane by lane. The commonest f32 functions (exp, exp2,
 * exp_minus_one, log, log2, log10, log_one_plus, power, the trigonometric ones and their inverses, cube_root and
 * hypotenuse) have kernels of their own (lanes.hsc): branch-free, with short polynomials in f64 lanes sized for f32,
 * so eight lanes take about what two values took through f64's functions. Checked on every f32, they're within 0.51
 * ulp, nearly always correctly rounded; a scalar f32 runs the same kernel on one lane, giving the same bits. The other
 * functions, and f64's on vectors, work a lane at a time.
 */
package math

import tiers from "std"

/** The package's tier: Freestanding, as it needs nothing but arithmetic. */
PACKAGE_TIER :: tiers.Tier.Freestanding
