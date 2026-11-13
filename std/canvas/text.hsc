package canvas

import intrinsics from "base"
import runtime from "base"
import fonts from "std"
import unicode from "std"

/*
 * Text: each glyph's outline rasterized once, at its size and a quarter-pixel step of where it starts, into a
 * coverage mask the cache keeps; then the mask blended with the paint wherever the glyph's drawn. A canvas whose
 * transform scales, rotates or shears draws its text as paths instead, uncached.
 */

/** How many glyphs the cache holds. */
GLYPH_SLOTS :: 1024
/** The most bytes of masks the cache keeps; past it, it starts again empty. */
GLYPH_POOL_BYTES :: 4 * 1024 * 1024
/** How many steps a pixel's split into for where a glyph starts. */
SUBPIXEL_STEPS :: 4

/** A glyph's mask, cached: what it's for, where it goes from the pen, and its coverage's place in the pool. */
CachedGlyph :: struct {
    used : bool,
    font : usize,
    glyph : u32,
    size : u32,
    step : u32,
    left : i32,
    top : i32,
    width : usize,
    height : usize,
    at : usize,
}

/** The glyph cache: its slots, its masks' bytes, and scratch for an outline. */
GlyphCache :: struct {
    slots : CachedGlyph[GLYPH_SLOTS],
    pool : u8[..],
    outline : fonts.Outline,
    path : Path,
    flat : Path,
}

/** Give back a glyph cache's arrays. */
free_glyphs :: fn(cache: ptr[mut GlyphCache]) {
    runtime.array_free(&cache.pool)
    fonts.free_outline(&cache.outline)
    free_path(&cache.path)
    free_path(&cache.flat)
}

/** Empty the cache, every glyph rasterized again as it's next drawn. */
clear_glyphs :: fn(cache: ptr[mut GlyphCache]) {
    for &slot in cache.slots {
        slot.used = false
    }
    runtime.array_reset(&cache.pool)
}

/**
 * Draw text on a line, its baseline at y, starting at x.
 *
 * @param canvas The canvas.
 * @param font The font.
 * @param size Its size, in the path's units per em.
 * @param x Where the first glyph's origin goes, in the path's units.
 * @param y The baseline.
 * @param text UTF-8; a line break is drawn as any other character, its glyph or the missing glyph.
 * @param paint What the glyphs are filled with.
 * @return Where the pen ended, the x after the text, in the path's units.
 */
draw_text :: fn(canvas: ptr[mut Canvas], font: ptr[fonts.Font], size: f32, x: f32, y: f32, text: u8[], paint: Paint) -> f32 {
    scale :: fonts.scale_of(font, size)
    if !is_translation(canvas.transform) {
        // Scaled, rotated or sheared: as paths
        pen := x
        previous := cast[u32](0)
        reset(&canvas.outline)
        at := cast[usize](0)
        loop {
            point, length :: unicode.decode(text, at)
            at += if length > 0 { length } else { cast[usize](1) }
            glyph :: fonts.glyph_index(font, point)
            if previous != 0 {
                pen += cast[f32](fonts.kerning(font, previous, glyph)) * scale
            }
            fonts.clear(&canvas.glyphs.outline)
            _ = fonts.glyph_outline(font, glyph, &canvas.glyphs.outline)
            add_outline(&canvas.outline, &canvas.glyphs.outline, scale, pen, y)
            pen += cast[f32](fonts.advance(font, glyph)) * scale
            previous = glyph
        }
        while at < text.count
        reset(&canvas.flat)
        flatten(&canvas.outline, canvas.transform, &canvas.flat)
        fill_flat(canvas, paint, .NonZero)
        return pen
    }
    origin :: apply(canvas.transform, Point.{x = x, y = y})
    baseline :: cast[i32](intrinsics.round_even(origin.y))
    pen := origin.x
    previous := cast[u32](0)
    solid :: is_solid(&paint)
    colour := paint_at(&paint, Point.{})
    back :: inverse(canvas.transform)
    at := cast[usize](0)
    loop {
        point, length :: unicode.decode(text, at)
        at += if length > 0 { length } else { cast[usize](1) }
        glyph :: fonts.glyph_index(font, point)
        if previous != 0 {
            pen += cast[f32](fonts.kerning(font, previous, glyph)) * scale
        }
        whole :: intrinsics.floor(pen)
        step :: cast[u32](intrinsics.floor((pen - whole) * cast[f32](SUBPIXEL_STEPS))) % SUBPIXEL_STEPS
        match cached(canvas, font, glyph, size, step) {
            case Some(slot) => {
                mask :: if slot < GLYPH_SLOTS { canvas.glyphs.slots[slot] } else { CachedGlyph.{} }
                left :: cast[i32](whole) + mask.left
                top :: baseline + mask.top
                draw_mask(canvas, mask, left, top, &paint, solid, colour, back)
            }
            case None => {}
        }
        pen += cast[f32](fonts.advance(font, glyph)) * scale
        previous = glyph
    }
    while at < text.count
    return x + (pen - origin.x)
}

/** A glyph's mask's slot, found in the cache or rasterized into it; null for a glyph that draws nothing. */
cached :: fn(canvas: ptr[mut Canvas], font: ptr[fonts.Font], glyph: u32, size: f32, step: u32) -> usize? {
    cache :: &canvas.glyphs
    key_font :: cast[usize](font.data.data)
    key_size :: cast[u32](intrinsics.round_even(size * 64))
    hash := (key_font >> 4) ~ (cast[usize](glyph) * 0x9e3779b1) ~ (cast[usize](key_size) * 0x85ebca6b) ~ cast[usize](step)
    hash = hash ~ (hash >> 15)
    free := cast[usize](GLYPH_SLOTS)
    for probe in cast[usize](0)..<8 {
        slot :: (hash + probe) % GLYPH_SLOTS
        found :: cache.slots[slot]
        if !found.used {
            if free == GLYPH_SLOTS {
                free = slot
            }
            continue
        }
        if found.font == key_font && found.glyph == glyph && found.size == key_size && found.step == step {
            return if found.width > 0 { slot } else { null }
        }
    }
    if free == GLYPH_SLOTS || cache.pool.count > GLYPH_POOL_BYTES {
        clear_glyphs(cache)
        free = hash % GLYPH_SLOTS
    }
    // Rasterized: the outline at the size, its origin a step into the pixel, the baseline at 0
    fonts.clear(&cache.outline)
    _ = fonts.glyph_outline(font, glyph, &cache.outline)
    reset(&cache.path)
    add_outline(&cache.path, &cache.outline, fonts.scale_of(font, size), cast[f32](step) / cast[f32](SUBPIXEL_STEPS), 0)
    reset(&cache.flat)
    flatten(&cache.path, Affine.{}, &cache.flat)
    made := CachedGlyph.{used = true, font = key_font, glyph = glyph, size = key_size, step = step, at = cache.pool.count}
    region :: bounds_of(&cache.flat)
    if !is_empty(region) && region.x1 - region.x0 < 4096 && region.y1 - region.y0 < 4096 {
        begin(&canvas.raster, region)
        add_polylines(&canvas.raster, &cache.flat)
        width :: cast[usize](region.x1 - region.x0)
        height :: cast[usize](region.y1 - region.y0)
        if canvas.row.count < width {
            loop {
                runtime.array_add(&canvas.row, 0)
            }
            while canvas.row.count < width
        }
        for row in cast[usize](0)..<height {
            _ = coverage_row(&canvas.raster, row, .NonZero, canvas.row[0..<canvas.row.count])
            for column in cast[usize](0)..<width {
                covered :: if column < canvas.row.count { canvas.row[column] } else { cast[f32](0) }
                runtime.array_add(&cache.pool, to_byte(covered))
            }
        }
        made.left = region.x0
        made.top = region.y0
        made.width = width
        made.height = height
    }
    if free < GLYPH_SLOTS {
        cache.slots[free] = made
    }
    return if made.width > 0 && free < GLYPH_SLOTS { free } else { null }
}

/** Blend a glyph's mask with a paint, its top left at a pixel, within the clip. */
draw_mask :: fn(canvas: ptr[mut Canvas], mask: CachedGlyph, left: i32, top: i32, paint: ptr[Paint], solid: bool, colour: Premultiplied, back: Affine) {
    placed :: Rect.{x0 = left, y0 = top, x1 = left + cast[i32](mask.width), y1 = top + cast[i32](mask.height)}
    region :: intersect(intersect(placed, canvas.clip), image_rect(canvas))
    if is_empty(region) {
        return void
    }
    for y in region.y0..<region.y1 {
        for x in region.x0..<region.x1 {
            at :: mask.at + cast[usize](y - top) * mask.width + cast[usize](x - left)
            covered :: if at < canvas.glyphs.pool.count { cast[f32](canvas.glyphs.pool[at]) / 255 } else { cast[f32](0) }
            if covered <= 0 {
                continue
            }
            shade :: if solid { colour } else { paint_at(paint, apply(back, Point.{x = cast[f32](x) + 0.5, y = cast[f32](y) + 0.5})) }
            blend(canvas, cast[usize](x), cast[usize](y), shade, covered)
        }
    }
    canvas.damage = union_of(canvas.damage, region)
}
