/**
 * Fonts: TrueType and OpenType fonts with TrueType outlines read from their bytes, and text measured and wrapped with
 * them. A font's character map (cmap formats 4 and 12) gives a code point's glyph; its horizontal metrics (hmtx) each
 * glyph's advance; its glyph outlines (glyf), simple and composite, a glyph's contours of lines and quadratic curves,
 * for a rasterizer to fill (std/canvas); and pair kerning, from GPOS's pair adjustments where the font has them, or
 * its kern table. Hinting isn't done: outlines are drawn as they're designed, anti-aliased. Shaping beyond pair
 * kerning (ligatures, marks, complex scripts) and bidirectional text aren't done yet; CFF outlines aren't read.
 *
 * Text is laid out in lines by advances and kerning, and wrapped to a width at spaces and line breaks, a word wider
 * than the width broken between characters.
 *
 * Freestanding: a font is a view of its bytes, which the caller keeps; outlines and lines go into arrays from the
 * context's allocator.
 */
package fonts

import tiers from "std"

/** The package's tier, Freestanding: it needs only base. */
PACKAGE_TIER :: tiers.Tier.Freestanding
