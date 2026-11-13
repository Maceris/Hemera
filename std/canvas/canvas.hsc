package canvas

import intrinsics from "base"
import runtime from "base"

/** The most saved states. */
MAX_SAVED :: 32

/**
 * An image of pixels: 8-bit blue, green, red and alpha, premultiplied by alpha, each row stride bytes after the last.
 * A view of its pixels, its owner's; a canvas draws into one on the heap, in a static or in mapped memory, not on the
 * stack.
 */
Image :: struct {
    pixels : mut u8[],
    width : usize,
    height : usize,
    stride : usize,
}

/** How an image is sampled when it's scaled. */
Filter :: enum {
    /** The nearest pixel. */
    Nearest,
    /** The four nearest, weighted by distance. */
    Bilinear,
}

/** What save keeps, and restore puts back. */
State :: struct {
    transform : Affine,
    clip : Rect,
}

/** A canvas drawing into an image, its state, and its scratch. */
Canvas :: struct {
    target : Image,
    /** From the path's units to pixels. */
    transform : Affine,
    /** What may be drawn on, in pixels: within the image always. */
    clip : Rect,
    saved : State[MAX_SAVED],
    saved_count : usize,
    /** Every pixel changed since take_damage last took it is within it. */
    damage : Rect,
    raster : Raster,
    /** Scratch: a path flattened, a stroke's outline, dashes, and a row's coverage. */
    flat : Path,
    outline : Path,
    dashes : Path,
    row : f32[..],
    glyphs : GlyphCache,
}

/**
 * A canvas on an image.
 *
 * @param target The image drawn into, its pixels the caller's, kept for as long as the canvas is used.
 * @return The canvas, its transform the identity and its clip the whole image; free_canvas gives its scratch back.
 */
make :: fn(target: Image) -> Canvas {
    return Canvas.{target = target, clip = Rect.{x1 = cast[i32](target.width), y1 = cast[i32](target.height)}}
}

/** Give back a canvas's scratch. */
free_canvas :: fn(canvas: ptr[mut Canvas]) {
    free_raster(&canvas.raster)
    free_path(&canvas.flat)
    free_path(&canvas.outline)
    free_path(&canvas.dashes)
    runtime.array_free(&canvas.row)
    free_glyphs(&canvas.glyphs)
}

/** Save the transform and the clip, for restore. */
save :: fn(canvas: ptr[mut Canvas]) {
    if canvas.saved_count < MAX_SAVED {
        canvas.saved[canvas.saved_count] = State.{transform = canvas.transform, clip = canvas.clip}
    }
    canvas.saved_count += 1
}

/** Put back the transform and the clip as they were at the last save; nothing without one. */
restore :: fn(canvas: ptr[mut Canvas]) {
    if canvas.saved_count == 0 {
        return void
    }
    canvas.saved_count -= 1
    if canvas.saved_count < MAX_SAVED {
        state :: canvas.saved[canvas.saved_count]
        canvas.transform = state.transform
        canvas.clip = state.clip
    }
}

/** Move what's drawn next. */
translate :: fn(canvas: ptr[mut Canvas], x: f32, y: f32) {
    canvas.transform = then(translation(x, y), canvas.transform)
}

/** Scale what's drawn next. */
scale :: fn(canvas: ptr[mut Canvas], x: f32, y: f32) {
    canvas.transform = then(scaling(x, y), canvas.transform)
}

/** Rotate what's drawn next, by radians. */
rotate :: fn(canvas: ptr[mut Canvas], radians: f32) {
    canvas.transform = then(rotation(radians), canvas.transform)
}

/** Set the transform outright. */
set_transform :: fn(canvas: ptr[mut Canvas], transform: Affine) {
    canvas.transform = transform
}

/**
 * Narrow the clip to a rectangle, in the path's units: what the transform makes of it, as whole pixels holding it.
 * Under a rotation, the rectangle's bounds.
 */
clip_rect :: fn(canvas: ptr[mut Canvas], x: f32, y: f32, width: f32, height: f32) {
    corners :: Point.[apply(canvas.transform, Point.{x = x, y = y}), apply(canvas.transform, Point.{x = x + width, y = y}),
        apply(canvas.transform, Point.{x = x, y = y + height}), apply(canvas.transform, Point.{x = x + width, y = y + height})]
    x0 := corners[0].x
    y0 := corners[0].y
    x1 := corners[0].x
    y1 := corners[0].y
    for p in corners {
        x0 = intrinsics.minimum(x0, p.x)
        y0 = intrinsics.minimum(y0, p.y)
        x1 = intrinsics.maximum(x1, p.x)
        y1 = intrinsics.maximum(y1, p.y)
    }
    limit :: cast[f32](1 << 24)
    rect :: Rect.{x0 = cast[i32](intrinsics.round_even(intrinsics.maximum(x0, -limit))), y0 = cast[i32](intrinsics.round_even(intrinsics.maximum(y0, -limit))),
        x1 = cast[i32](intrinsics.round_even(intrinsics.minimum(x1, limit))), y1 = cast[i32](intrinsics.round_even(intrinsics.minimum(y1, limit)))}
    canvas.clip = intersect(canvas.clip, rect)
}

/**
 * Take what's been drawn since the last take: a rectangle holding every pixel changed, and empty from now on.
 *
 * @return The damage; empty if nothing's been drawn.
 */
take_damage :: fn(canvas: ptr[mut Canvas]) -> Rect {
    taken :: canvas.damage
    canvas.damage = Rect.{}
    return taken
}

/**
 * Fill a path.
 *
 * @param canvas The canvas.
 * @param path The path, in its own units, its subpaths closed for the fill.
 * @param paint What it's filled with.
 * @param rule How its inside is found.
 */
fill :: fn(canvas: ptr[mut Canvas], path: ptr[Path], paint: Paint, rule: FillRule = .NonZero) {
    reset(&canvas.flat)
    flatten(path, canvas.transform, &canvas.flat)
    fill_flat(canvas, paint, rule)
}

/**
 * Stroke a path.
 *
 * @param canvas The canvas.
 * @param path The path, in its own units.
 * @param paint What it's stroked with.
 * @param stroke Its width, joins, caps and dashes, in the path's units.
 */
stroke :: fn(canvas: ptr[mut Canvas], path: ptr[Path], paint: Paint, stroke: Stroke) {
    reset(&canvas.flat)
    flatten(path, canvas.transform, &canvas.flat, false)
    reset(&canvas.outline)
    stroke_outline(&canvas.flat, &stroke, scale_of(canvas.transform), &canvas.outline, &canvas.dashes)
    // The outline's polygons, already in pixels, filled as they are
    reset(&canvas.flat)
    flatten(&canvas.outline, Affine.{}, &canvas.flat)
    fill_flat(canvas, paint, .NonZero)
}

/** Fill a rectangle, in the path's units. */
fill_rect :: fn(canvas: ptr[mut Canvas], x: f32, y: f32, width: f32, height: f32, paint: Paint) {
    reset(&canvas.outline)
    rect(&canvas.outline, x, y, width, height)
    // Through flat directly, so the outline path's free for the fill
    reset(&canvas.flat)
    flatten(&canvas.outline, canvas.transform, &canvas.flat)
    fill_flat(canvas, paint, .NonZero)
}

/** Fill the clip with a colour, replacing what's there, not blending. */
clear :: fn(canvas: ptr[mut Canvas], color: Color) {
    region :: intersect(canvas.clip, image_rect(canvas))
    if is_empty(region) {
        return void
    }
    p :: premultiply(color)
    bytes :: u8.[to_byte(p.b), to_byte(p.g), to_byte(p.r), to_byte(p.a)]
    for y in cast[usize](region.y0)..<cast[usize](region.y1) {
        for x in cast[usize](region.x0)..<cast[usize](region.x1) {
            at :: y * canvas.target.stride + 4 * x
            for i in cast[usize](0)..<4 {
                if at + i < canvas.target.pixels.count {
                    canvas.target.pixels[at + i] = bytes[i]
                }
            }
        }
    }
    canvas.damage = union_of(canvas.damage, region)
}

/** The whole image, as a rectangle. */
image_rect :: fn(canvas: ptr[Canvas]) -> Rect {
    return Rect.{x1 = cast[i32](canvas.target.width), y1 = cast[i32](canvas.target.height)}
}

/** A channel from 0 to 1 as a byte, rounded. */
to_byte :: fn(value: f32) -> u8 {
    return cast[u8](intrinsics.round_even(clamp_unit(value) * 255))
}

/** Fill the polylines in flat, in pixels, with a paint. */
fill_flat :: fn(canvas: ptr[mut Canvas], paint: Paint, rule: FillRule) {
    region :: intersect(intersect(bounds_of(&canvas.flat), canvas.clip), image_rect(canvas))
    if is_empty(region) {
        return void
    }
    begin(&canvas.raster, region)
    add_polylines(&canvas.raster, &canvas.flat)
    width :: cast[usize](region.x1 - region.x0)
    if canvas.row.count < width {
        loop {
            runtime.array_add(&canvas.row, 0)
        }
        while canvas.row.count < width
    }
    solid :: is_solid(&paint)
    colour := paint_at(&paint, Point.{})
    back :: inverse(canvas.transform)
    touched := Rect.{}
    for row in cast[usize](0)..<cast[usize](region.y1 - region.y0) {
        if !coverage_row(&canvas.raster, row, rule, canvas.row[0..<canvas.row.count]) {
            continue
        }
        y :: cast[usize](region.y0) + row
        first := width
        last := cast[usize](0)
        for column in cast[usize](0)..<width {
            covered :: if column < canvas.row.count { canvas.row[column] } else { cast[f32](0) }
            if covered <= 0.0001 {
                continue
            }
            x :: cast[usize](region.x0) + column
            if !solid {
                colour = paint_at(&paint, apply(back, Point.{x = cast[f32](x) + 0.5, y = cast[f32](y) + 0.5}))
            }
            blend(canvas, x, y, colour, covered)
            first = if column < first { column } else { first }
            last = column
        }
        if first < width {
            touched = union_of(touched, Rect.{x0 = region.x0 + cast[i32](first), y0 = cast[i32](y), x1 = region.x0 + cast[i32](last) + 1, y1 = cast[i32](y) + 1})
        }
    }
    canvas.damage = union_of(canvas.damage, touched)
}

/** Blend a premultiplied colour over a pixel, by a coverage, source over. */
blend :: fn(canvas: ptr[mut Canvas], x: usize, y: usize, colour: Premultiplied, covered: f32) {
    pixels :: four(canvas.target.pixels, y * canvas.target.stride + 4 * x)
    if pixels.count < 4 {
        return void
    }
    at :: cast[usize](0)
    source :: vector[f32, 4].{colour.b, colour.g, colour.r, colour.a} * intrinsics.splat[vector[f32, 4]](covered)
    under :: vector[f32, 4].{cast[f32](pixels[at]), cast[f32](pixels[at + 1]), cast[f32](pixels[at + 2]), cast[f32](pixels[at + 3])}
    keep :: 1 - colour.a * covered
    result :: source * intrinsics.splat[vector[f32, 4]](255) + under * intrinsics.splat[vector[f32, 4]](keep)
    rounded :: intrinsics.round_even(result)
    pixels[at] = channel(rounded[0])
    pixels[at + 1] = channel(rounded[1])
    pixels[at + 2] = channel(rounded[2])
    pixels[at + 3] = channel(rounded[3])
}

/** A channel's value, from 0 to 255 after rounding, as a byte. */
channel :: fn(value: f32) -> u8 {
    return if value >= 255 { cast[u8](255) } else if value > 0 { cast[u8](value) } else { cast[u8](0) }
}

/**
 * Draw an image into a rectangle, in the path's units, scaled to fill it.
 *
 * @param canvas The canvas.
 * @param image The image, premultiplied BGRA.
 * @param x The rectangle's left.
 * @param y Its top.
 * @param width Its width.
 * @param height Its height.
 * @param filter How the image is sampled.
 */
draw_image :: fn(canvas: ptr[mut Canvas], image: Image, x: f32, y: f32, width: f32, height: f32, filter: Filter = .Bilinear) {
    if image.width == 0 || image.height == 0 || !(width > 0) || !(height > 0) {
        return void
    }
    reset(&canvas.outline)
    rect(&canvas.outline, x, y, width, height)
    reset(&canvas.flat)
    flatten(&canvas.outline, canvas.transform, &canvas.flat)
    region :: intersect(intersect(bounds_of(&canvas.flat), canvas.clip), image_rect(canvas))
    if is_empty(region) {
        return void
    }
    begin(&canvas.raster, region)
    add_polylines(&canvas.raster, &canvas.flat)
    columns :: cast[usize](region.x1 - region.x0)
    if canvas.row.count < columns {
        loop {
            runtime.array_add(&canvas.row, 0)
        }
        while canvas.row.count < columns
    }
    // From a pixel's centre to the image's pixels
    back :: inverse(canvas.transform)
    sx :: cast[f32](image.width) / width
    sy :: cast[f32](image.height) / height
    for row in cast[usize](0)..<cast[usize](region.y1 - region.y0) {
        if !coverage_row(&canvas.raster, row, .NonZero, canvas.row[0..<canvas.row.count]) {
            continue
        }
        py :: cast[usize](region.y0) + row
        for column in cast[usize](0)..<columns {
            covered :: if column < canvas.row.count { canvas.row[column] } else { cast[f32](0) }
            if covered <= 0.0001 {
                continue
            }
            px :: cast[usize](region.x0) + column
            user :: apply(back, Point.{x = cast[f32](px) + 0.5, y = cast[f32](py) + 0.5})
            u :: (user.x - x) * sx - 0.5
            v :: (user.y - y) * sy - 0.5
            colour :: if filter == .Nearest { texel(image, u + 0.5, v + 0.5) } else { bilinear(image, u, v) }
            blend(canvas, px, py, colour, covered)
        }
    }
    canvas.damage = union_of(canvas.damage, region)
}

/** An image's pixel nearest a point, clamped to its edges, as premultiplied channels from 0 to 1. */
texel :: fn(image: Image, u: f32, v: f32) -> Premultiplied {
    return pixel_at(image, clamp_index(intrinsics.floor(u), image.width), clamp_index(intrinsics.floor(v), image.height))
}

/** An image sampled between its four nearest pixels, clamped to its edges. */
bilinear :: fn(image: Image, u: f32, v: f32) -> Premultiplied {
    fu :: intrinsics.floor(u)
    fv :: intrinsics.floor(v)
    tu :: u - fu
    tv :: v - fv
    x0 :: clamp_index(fu, image.width)
    x1 :: clamp_index(fu + 1, image.width)
    y0 :: clamp_index(fv, image.height)
    y1 :: clamp_index(fv + 1, image.height)
    a :: pixel_at(image, x0, y0)
    b :: pixel_at(image, x1, y0)
    c :: pixel_at(image, x0, y1)
    d :: pixel_at(image, x1, y1)
    w00 :: (1 - tu) * (1 - tv)
    w10 :: tu * (1 - tv)
    w01 :: (1 - tu) * tv
    w11 :: tu * tv
    return Premultiplied.{b = a.b * w00 + b.b * w10 + c.b * w01 + d.b * w11, g = a.g * w00 + b.g * w10 + c.g * w01 + d.g * w11,
        r = a.r * w00 + b.r * w10 + c.r * w01 + d.r * w11, a = a.a * w00 + b.a * w10 + c.a * w01 + d.a * w11}
}

/** A coordinate as an index within a size, clamped to its edges. */
clamp_index :: fn(value: f32, size: usize) -> usize {
    if !(value > 0) {
        return 0
    }
    top :: cast[f32](size - 1)
    return if value >= top { size - 1 } else { cast[usize](value) }
}

/** An image's pixel, as premultiplied channels from 0 to 1; transparent past its bytes. */
pixel_at :: fn(image: Image, x: usize, y: usize) -> Premultiplied {
    pixels :: four(image.pixels, y * image.stride + 4 * x)
    if pixels.count < 4 {
        return Premultiplied.{}
    }
    return Premultiplied.{b = cast[f32](pixels[0]) / 255, g = cast[f32](pixels[1]) / 255,
        r = cast[f32](pixels[2]) / 255, a = cast[f32](pixels[3]) / 255}
}

/** A pixel's four bytes, at an offset; none past the end. */
four :: fn(pixels: mut u8[], at: usize) -> mut u8[] {
    if at > pixels.count || pixels.count - at < 4 {
        return pixels[0..<0]
    }
    return pixels[at..<at + 4]
}
