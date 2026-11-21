package canvas

import intrinsics from "base:intrinsics"
import runtime from "base:runtime"

/** The most saved states. */
MAX_SAVED :: 32

/**
 * An image of pixels: 8-bit blue, green, red and alpha, premultiplied by alpha, each row stride bytes after the last.
 * A view of its pixels, its owner's; a canvas draws into one on the heap, in a static or in mapped memory, not on the
 * stack.
 */
Image :: struct {
    pixels : mut u8[],
    width  : usize,
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
    flat    : Path,
    outline : Path,
    dashes  : Path,
    row     : f32[..],
    glyphs  : GlyphCache,
}

/**
 * A canvas on an image.
 *
 * @param target The image drawn into, its pixels the caller's, kept for as long as the canvas is used.
 * @return The canvas, its transform the identity and its clip the whole image; free_canvas gives its scratch back.
 */
make :: fn(target : Image) -> Canvas {
    return Canvas.{target = target, clip = Rect.{x1 = cast[i32](target.width), y1 = cast[i32](target.height)}}
}

/** Give back a canvas's scratch. */
free_canvas :: fn(canvas : ptr[mut Canvas]) {
    free_raster(&canvas.raster)
    free_path(&canvas.flat)
    free_path(&canvas.outline)
    free_path(&canvas.dashes)
    runtime.array_free(&canvas.row)
    free_glyphs(&canvas.glyphs)
}

/** Save the transform and the clip, for restore. */
save :: fn(canvas : ptr[mut Canvas]) {
    if canvas.saved_count < MAX_SAVED {
        canvas.saved[canvas.saved_count] = State.{transform = canvas.transform, clip = canvas.clip}
    }
    canvas.saved_count += 1
}

/** Put back the transform and the clip as they were at the last save; nothing without one. */
restore :: fn(canvas : ptr[mut Canvas]) {
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
translate :: fn(canvas : ptr[mut Canvas], x : f32, y : f32) {
    canvas.transform = then(translation(x, y), canvas.transform)
}

/** Scale what's drawn next. */
scale :: fn(canvas : ptr[mut Canvas], x : f32, y : f32) {
    canvas.transform = then(scaling(x, y), canvas.transform)
}

/** Rotate what's drawn next, by radians. */
rotate :: fn(canvas : ptr[mut Canvas], radians : f32) {
    canvas.transform = then(rotation(radians), canvas.transform)
}

/** Set the transform outright. */
set_transform :: fn(canvas : ptr[mut Canvas], transform : Affine) {
    canvas.transform = transform
}

/**
 * Narrow the clip to a rectangle, in the path's units: what the transform makes of it, as whole pixels holding it.
 * Under a rotation, the rectangle's bounds.
 */
clip_rect :: fn(canvas : ptr[mut Canvas], x : f32, y : f32, width : f32, height : f32) {
    corners :: Point.[
        apply(canvas.transform, Point.{x = x, y = y}),
        apply(canvas.transform, Point.{x = x + width, y = y}),
        apply(canvas.transform, Point.{x = x, y = y + height}),
        apply(canvas.transform, Point.{x = x + width, y = y + height})
    ]
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
    rect :: Rect.{
        x0 = cast[i32](intrinsics.round_even(intrinsics.maximum(x0, -limit))),
        y0 = cast[i32](intrinsics.round_even(intrinsics.maximum(y0, -limit))),
        x1 = cast[i32](intrinsics.round_even(intrinsics.minimum(x1, limit))),
        y1 = cast[i32](intrinsics.round_even(intrinsics.minimum(y1, limit))),
    }
    canvas.clip = intersect(canvas.clip, rect)
}

/**
 * Take what's been drawn since the last take: a rectangle holding every pixel changed, and empty from now on.
 *
 * @return The damage; empty if nothing's been drawn.
 */
take_damage :: fn(canvas : ptr[mut Canvas]) -> Rect {
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
fill :: fn(canvas : ptr[mut Canvas], path : ptr[Path], paint : Paint, rule : FillRule = .NonZero) {
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
stroke :: fn(canvas : ptr[mut Canvas], path : ptr[Path], paint : Paint, stroke : Stroke) {
    reset(&canvas.flat)
    flatten(path, canvas.transform, &canvas.flat, false)
    reset(&canvas.outline)
    stroke_outline(&canvas.flat, &stroke, scale_of(canvas.transform), &canvas.outline, &canvas.dashes)
    // The outline's polygons, already in pixels, filled as they are
    reset(&canvas.flat)
    flatten(&canvas.outline, Affine.{}, &canvas.flat)
    fill_flat(canvas, paint, .NonZero)
}

/**
 * Fill a rectangle, in the path's units.
 *
 * Under a transform that keeps its sides along the image's (no rotation or shear), each pixel's coverage is worked out
 * from how much of it the rectangle covers, with no path rasterized, and a run of pixels an opaque solid paint covers
 * whole is written as it is; otherwise it's filled as a path.
 */
fill_rect :: fn(canvas : ptr[mut Canvas], x : f32, y : f32, width : f32, height : f32, paint : Paint) {
    if canvas.transform.b == 0 && canvas.transform.c == 0 {
        a :: apply(canvas.transform, Point.{x = x, y = y})
        b :: apply(canvas.transform, Point.{x = x + width, y = y + height})
        fill_box(
            canvas,
            intrinsics.minimum(a.x, b.x),
            intrinsics.minimum(a.y, b.y),
            intrinsics.maximum(a.x, b.x),
            intrinsics.maximum(a.y, b.y),
            paint
        )
        return void
    }
    reset(&canvas.outline)
    rect(&canvas.outline, x, y, width, height)
    // Through flat directly, so the outline path's free for the fill
    reset(&canvas.flat)
    flatten(&canvas.outline, canvas.transform, &canvas.flat)
    fill_flat(canvas, paint, .NonZero)
}

/** Fill the clip with a colour, replacing what's there, not blending. */
clear :: fn(canvas : ptr[mut Canvas], color : Color) {
    region :: intersect(canvas.clip, image_rect(canvas))
    if is_empty(region) {
        return void
    }
    p :: premultiply(color)
    bytes :: u8.[to_byte(p.b), to_byte(p.g), to_byte(p.r), to_byte(p.a)]
    for y in cast[usize](region.y0)..<cast[usize](region.y1) {
        fill_run(canvas, y, cast[usize](region.x0), cast[usize](region.x1), bytes)
    }
    canvas.damage = union_of(canvas.damage, region)
}

/**
 * Write one pixel's bytes over a run of a row, replacing what's there: the first pixel's written, then copied in ever
 * larger blocks.
 *
 * @param canvas The canvas, whose target's written; its clip isn't looked at.
 * @param y The row.
 * @param x0 The run's first column.
 * @param x1 One past its last; nothing's written when it isn't past x0, or the run isn't all within the pixels.
 * @param bytes The pixel: blue, green, red and alpha, premultiplied.
 */
fill_run :: fn(canvas : ptr[mut Canvas], y : usize, x0 : usize, x1 : usize, bytes : u8[4]) {
    if x1 <= x0 {
        return void
    }
    start :: y * canvas.target.stride + 4 * x0
    count :: 4 * (x1 - x0)
    pixels :: canvas.target.pixels
    if start > pixels.count {
        return void
    }
    rest :: pixels[start..<pixels.count]
    if count > rest.count || count < 4 {
        return void
    }
    run :: rest[0..<count]
    run[0] = bytes[0]
    run[1] = bytes[1]
    run[2] = bytes[2]
    run[3] = bytes[3]
    // What's written so far, copied after itself: never more than's been written, so the two never overlap
    done := cast[usize](4)
    loop {
        if done >= run.count {
            break
        }
        after :: run[done..<run.count]
        step :: if done < after.count { done } else { after.count }
        intrinsics.mem_copy_non_overlapping(cast[mut rawptr](after.data), cast[rawptr](run.data), step)
        done += step
    }
}

/**
 * Fill a rectangle in pixels whose sides are along the image's: each pixel by how much of it the rectangle covers,
 * within the clip. Rows and columns it covers whole, with an opaque solid paint, are written as runs (fill_run).
 *
 * @param canvas The canvas; what's drawn is added to its damage.
 * @param x0 The rectangle's left, in pixels, which may be a fraction or off the image.
 * @param y0 Its top.
 * @param x1 Its right, not left of x0.
 * @param y1 Its bottom, not above y0.
 * @param paint What it's filled with; a gradient's worked out at each pixel's centre, transformed back.
 */
fill_box :: fn(canvas : ptr[mut Canvas], x0 : f32, y0 : f32, x1 : f32, y1 : f32, paint : Paint) {
    limit :: cast[f32](1 << 24)
    bounds :: Rect.{
        x0 = cast[i32](intrinsics.floor(intrinsics.maximum(x0, -limit))),
        y0 = cast[i32](intrinsics.floor(intrinsics.maximum(y0, -limit))),
        x1 = cast[i32](intrinsics.ceil(intrinsics.minimum(x1, limit))),
        y1 = cast[i32](intrinsics.ceil(intrinsics.minimum(y1, limit))),
    }
    region :: intersect(intersect(bounds, canvas.clip), image_rect(canvas))
    if is_empty(region) {
        return void
    }
    solid :: is_solid(&paint)
    colour := paint_at(&paint, Point.{})
    opaque :: solid && colour.a >= 1
    bytes :: u8.[to_byte(colour.b), to_byte(colour.g), to_byte(colour.r), to_byte(colour.a)]
    back :: inverse(canvas.transform)
    // The columns every pixel of which is inside, within the region: written as a run on a row covered whole
    inside_x0 :: cast[i32](intrinsics.ceil(intrinsics.maximum(x0, -limit)))
    inside_x1 :: cast[i32](intrinsics.floor(intrinsics.minimum(x1, limit)))
    inner_x0 :: if inside_x0 > region.x0 { inside_x0 } else { region.x0 }
    inner_x1 :: if inside_x1 < region.x1 { inside_x1 } else { region.x1 }
    touched := Rect.{}
    for row in region.y0..<region.y1 {
        y :: cast[f32](row)
        cover_y :: intrinsics.minimum(y + 1, y1) - intrinsics.maximum(y, y0)
        if cover_y <= 0.0001 {
            continue
        }
        whole_row :: opaque && cover_y >= 1
        first := region.x1
        last := region.x0
        column := region.x0
        loop {
            if column >= region.x1 {
                break
            }
            if whole_row && column == inner_x0 && inner_x0 < inner_x1 {
                fill_run(canvas, cast[usize](row), cast[usize](inner_x0), cast[usize](inner_x1), bytes)
                // Columns are gone through left to right, so the run's after any pixel already touched in the row
                if first == region.x1 {
                    first = inner_x0
                }
                last = inner_x1 - 1
                column = inner_x1
                continue
            }
            x :: cast[f32](column)
            covered :: (intrinsics.minimum(x + 1, x1) - intrinsics.maximum(x, x0)) * cover_y
            if covered > 0.0001 {
                if !solid {
                    colour = paint_at(&paint, apply(back, Point.{x = x + 0.5, y = y + 0.5}))
                }
                blend(canvas, cast[usize](column), cast[usize](row), colour, intrinsics.minimum(covered, 1))
                if first == region.x1 {
                    first = column
                }
                last = column
            }
            column += 1
        }
        if first < region.x1 {
            touched = union_of(touched, Rect.{x0 = first, y0 = row, x1 = last + 1, y1 = row + 1})
        }
    }
    canvas.damage = union_of(canvas.damage, touched)
}

/** The whole image, as a rectangle. */
image_rect :: fn(canvas : ptr[Canvas]) -> Rect {
    return Rect.{x1 = cast[i32](canvas.target.width), y1 = cast[i32](canvas.target.height)}
}

/** A channel from 0 to 1 as a byte, rounded. */
to_byte :: fn(value : f32) -> u8 {
    return cast[u8](intrinsics.round_even(clamp_unit(value) * 255))
}

/** Fill the polylines in flat, in pixels, with a paint. */
fill_flat :: fn(canvas : ptr[mut Canvas], paint : Paint, rule : FillRule) {
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
    /*
     * An opaque solid paint over a pixel covered whole, or as near as rounding to bytes can't tell, is the paint's own
     * bytes, written without blending
     */
    opaque :: solid && colour.a >= 1
    bytes :: u8.[to_byte(colour.b), to_byte(colour.g), to_byte(colour.r), to_byte(colour.a)]
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
            if opaque && covered >= 0.999 {
                pixel :: four(canvas.target.pixels, y * canvas.target.stride + 4 * x)
                if pixel.count == 4 {
                    pixel[0] = bytes[0]
                    pixel[1] = bytes[1]
                    pixel[2] = bytes[2]
                    pixel[3] = bytes[3]
                }
            }
            else {
                if !solid {
                    colour = paint_at(&paint, apply(back, Point.{x = cast[f32](x) + 0.5, y = cast[f32](y) + 0.5}))
                }
                blend(canvas, x, y, colour, covered)
            }
            first = if column < first { column } else { first }
            last = column
        }
        if first < width {
            touched = union_of(
                touched,
                Rect.{
                    x0 = region.x0 + cast[i32](first),
                    y0 = cast[i32](y),
                    x1 = region.x0 + cast[i32](last) + 1,
                    y1 = cast[i32](y) + 1,
                }
            )
        }
    }
    canvas.damage = union_of(canvas.damage, touched)
}

/** Blend a premultiplied colour over a pixel, by a coverage, source over. */
blend :: fn(canvas : ptr[mut Canvas], x : usize, y : usize, colour : Premultiplied, covered : f32) {
    pixels :: four(canvas.target.pixels, y * canvas.target.stride + 4 * x)
    if pixels.count < 4 {
        return void
    }
    at :: cast[usize](0)
    source :: vector[f32, 4].{colour.b, colour.g, colour.r, colour.a} * intrinsics.splat[vector[f32, 4]](covered)
    under :: vector[f32, 4].{
        cast[f32](pixels[at]),
        cast[f32](pixels[at + 1]),
        cast[f32](pixels[at + 2]),
        cast[f32](pixels[at + 3])
    }
    keep :: 1 - colour.a * covered
    result :: source * intrinsics.splat[vector[f32, 4]](255) + under * intrinsics.splat[vector[f32, 4]](keep)
    rounded :: intrinsics.round_even(result)
    pixels[at] = channel(rounded[0])
    pixels[at + 1] = channel(rounded[1])
    pixels[at + 2] = channel(rounded[2])
    pixels[at + 3] = channel(rounded[3])
}

/** A channel's value, rounded, as a byte: a cast saturates, so past 255 it's 255, and below 0 or NaN it's 0. */
channel :: fn(value : f32) -> u8 {
    return cast[u8](value)
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
draw_image :: fn(
    canvas : ptr[mut Canvas],
    image : Image,
    x : f32,
    y : f32,
    width : f32,
    height : f32,
    filter : Filter = .Bilinear
) {
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
texel :: fn(image : Image, u : f32, v : f32) -> Premultiplied {
    return pixel_at(
        image,
        clamp_index(intrinsics.floor(u), image.width),
        clamp_index(intrinsics.floor(v), image.height)
    )
}

/** An image sampled between its four nearest pixels, clamped to its edges. */
bilinear :: fn(image : Image, u : f32, v : f32) -> Premultiplied {
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
    return Premultiplied.{
        b = a.b * w00 + b.b * w10 + c.b * w01 + d.b * w11,
        g = a.g * w00 + b.g * w10 + c.g * w01 + d.g * w11,
        r = a.r * w00 + b.r * w10 + c.r * w01 + d.r * w11,
        a = a.a * w00 + b.a * w10 + c.a * w01 + d.a * w11,
    }
}

/** A coordinate as an index within a size, clamped to its edges. */
clamp_index :: fn(value : f32, size : usize) -> usize {
    if !(value > 0) {
        return 0
    }
    top :: cast[f32](size - 1)
    return if value >= top { size - 1 } else { cast[usize](value) }
}

/** An image's pixel, as premultiplied channels from 0 to 1; transparent past its bytes. */
pixel_at :: fn(image : Image, x : usize, y : usize) -> Premultiplied {
    pixels :: four(image.pixels, y * image.stride + 4 * x)
    if pixels.count < 4 {
        return Premultiplied.{}
    }
    return Premultiplied.{
        b = cast[f32](pixels[0]) / 255,
        g = cast[f32](pixels[1]) / 255,
        r = cast[f32](pixels[2]) / 255,
        a = cast[f32](pixels[3]) / 255,
    }
}

/** A pixel's four bytes, at an offset; none past the end. */
four :: fn(pixels : mut u8[], at : usize) -> mut u8[] {
    if at > pixels.count || pixels.count - at < 4 {
        return pixels[0..<0]
    }
    return pixels[at..<at + 4]
}
