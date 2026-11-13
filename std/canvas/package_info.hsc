/**
 * A 2D canvas: drawing into an image of pixels on the CPU. Paths of lines and quadratic and cubic curves are filled,
 * by the non-zero or even-odd rule, or stroked, with joins (miter, round, bevel), caps (butt, round, square) and
 * dashes; in a solid colour or a linear or radial gradient; images are drawn scaled, nearest or bilinear; and text is
 * drawn from a font (std/fonts), its glyphs cached. All of it under an affine transform and inside a clipping
 * rectangle, saved and restored as a stack; and every pixel changed is within the damage the canvas reports, for a
 * compositor to take.
 *
 * Coverage is exact: each edge adds its area and cover to the cells it crosses, as FreeType's rasterizer and font-rs
 * do, and a row's coverage is their running sum, so anti-aliasing needs no supersampling. Curves are flattened to
 * lines within a quarter of a pixel. Pixels are 8-bit BGRA, premultiplied by alpha, in sRGB, blended source-over.
 *
 * Freestanding: the canvas draws into pixels its caller gives, and keeps its scratch in arrays from the context's
 * allocator.
 */
package canvas

import tiers from "std"

/** The package's tier, Freestanding: it needs only base and std's math and fonts. */
PACKAGE_TIER :: tiers.Tier.Freestanding
