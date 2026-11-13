package canvas

import intrinsics from "base"
import runtime from "base"

/*
 * The rasterizer. A path's edges, flattened to lines in pixels, each add to the cells of a region what they cover:
 * every row an edge crosses gets its signed height there, split between the cell the edge enters and the cells it
 * spans, by area (font-rs's accumulation, as FreeType's gray rasterizer does it). A row's coverage at a pixel is then
 * the running sum of its cells, its winding number's fractional part included: the non-zero rule takes its magnitude,
 * up to 1; even-odd folds it modulo 2. An edge left of the region adds its cover at its left side, as winding there
 * counts for every pixel right of it; one right of it adds nothing.
 */

/** How far a flattened curve may stray from the curve, in pixels. */
TOLERANCE : f32 : 0.25
/** The most lines a curve is flattened to. */
MAX_SEGMENTS : u32 : 256

/** How a path's inside is found: by winding number, non-zero or odd. */
FillRule :: enum {
    NonZero,
    EvenOdd,
}

/** A rasterizer's region, its cells, and a row's coverage. */
Raster :: struct {
    /** The region, in pixels: its left and top, and its size. */
    x0 : i32,
    y0 : i32,
    width : usize,
    height : usize,
    /** Each row's cells, width + 2 of them, the two past the width taking what spills past it; zero between fills. */
    cells : f32[..],
}

/** Make a raster ready for a region: its cells, zero. */
begin :: fn(raster: ptr[mut Raster], region: Rect) {
    raster.x0 = region.x0
    raster.y0 = region.y0
    raster.width = cast[usize](region.x1 - region.x0)
    raster.height = cast[usize](region.y1 - region.y0)
    needed :: (raster.width + 2) * raster.height
    if raster.cells.count < needed {
        runtime.array_reserve(&raster.cells, needed)
        loop {
            runtime.array_add(&raster.cells, 0)
        }
        while raster.cells.count < needed
    }
}

/** Give back a raster's cells. */
free_raster :: fn(raster: ptr[mut Raster]) {
    runtime.array_free(&raster.cells)
}

/** Add a cell's share, if it's in the region. */
add_cell :: fn(raster: ptr[mut Raster], at: usize, value: f32) {
    if at < raster.cells.count {
        raster.cells[at] += value
    }
}

/** Add an edge, in pixels: clipped to the region's sides, then accumulated row by row. */
add_line :: fn(raster: ptr[mut Raster], from: Point, to: Point) {
    w :: cast[f32](raster.width)
    // In the region's own coordinates
    ax := from.x - cast[f32](raster.x0)
    ay := from.y - cast[f32](raster.y0)
    bx := to.x - cast[f32](raster.x0)
    by := to.y - cast[f32](raster.y0)
    if ay == by {
        return void
    }
    // Wholly right of the region: nothing it covers is seen
    if ax >= w && bx >= w {
        return void
    }
    // Wholly left: its cover, at the left side
    if ax <= 0 && bx <= 0 {
        accumulate(raster, 0, ay, 0, by)
        return void
    }
    // Crossing the left side: the part left of it at the side
    if (ax < 0) != (bx < 0) {
        ty :: ay + (by - ay) * (0 - ax) / (bx - ax)
        if ax < 0 {
            accumulate(raster, 0, ay, 0, ty)
            ax = 0
            ay = ty
        }
        else {
            accumulate(raster, 0, ty, 0, by)
            bx = 0
            by = ty
        }
    }
    // Crossing the right side: the part right of it dropped
    if (ax > w) != (bx > w) {
        ty :: ay + (by - ay) * (w - ax) / (bx - ax)
        if ax > w {
            ax = w
            ay = ty
        }
        else {
            bx = w
            by = ty
        }
    }
    accumulate(raster, ax, ay, bx, by)
}

/** Accumulate a line within the region's columns, 0 to width (font-rs's draw_line). */
accumulate :: fn(raster: ptr[mut Raster], ax: f32, ay: f32, bx: f32, by: f32) {
    if ay == by {
        return void
    }
    direction :: if ay < by { cast[f32](1) } else { cast[f32](-1) }
    x0 :: if ay < by { ax } else { bx }
    y0 :: if ay < by { ay } else { by }
    x1 :: if ay < by { bx } else { ax }
    y1 :: if ay < by { by } else { ay }
    h :: cast[f32](raster.height)
    if y1 <= 0 || y0 >= h {
        return void
    }
    stride :: raster.width + 2
    dxdy :: (x1 - x0) / (y1 - y0)
    x := x0
    if y0 < 0 {
        x -= y0 * dxdy
    }
    first :: if y0 < 0 { cast[usize](0) } else { cast[usize](intrinsics.floor(y0)) }
    last :: if y1 > h { raster.height } else { cast[usize](intrinsics.ceil(y1)) }
    for row in first..<last {
        start :: row * stride
        top :: if cast[f32](row) > y0 { cast[f32](row) } else { y0 }
        bottom :: if cast[f32](row + 1) < y1 { cast[f32](row + 1) } else { y1 }
        dy :: bottom - top
        x_next :: x + dxdy * dy
        d :: dy * direction
        // Kept within the columns, which rounding could take a hair past
        w :: cast[f32](raster.width)
        here :: intrinsics.minimum(intrinsics.maximum(x, 0), w)
        there :: intrinsics.minimum(intrinsics.maximum(x_next, 0), w)
        left :: if here < there { here } else { there }
        right :: if here < there { there } else { here }
        left_floor :: intrinsics.floor(left)
        left_cell :: cast[usize](left_floor)
        right_ceil :: intrinsics.ceil(right)
        right_cell :: cast[usize](right_ceil)
        if right_cell <= left_cell + 1 {
            middle :: 0.5 * (here + there) - left_floor
            add_cell(raster, start + left_cell, d - d * middle)
            add_cell(raster, start + left_cell + 1, d * middle)
        }
        else {
            s :: 1 / (right - left)
            left_fraction :: left - left_floor
            a0 :: 0.5 * s * (1 - left_fraction) * (1 - left_fraction)
            right_fraction :: right - right_ceil + 1
            am :: 0.5 * s * right_fraction * right_fraction
            add_cell(raster, start + left_cell, d * a0)
            if right_cell == left_cell + 2 {
                add_cell(raster, start + left_cell + 1, d * (1 - a0 - am))
            }
            else {
                a1 :: s * (1.5 - left_fraction)
                add_cell(raster, start + left_cell + 1, d * (a1 - a0))
                for cell in left_cell + 2..<right_cell - 1 {
                    add_cell(raster, start + cell, d * s)
                }
                a2 :: a1 + cast[f32](right_cell - left_cell - 3) * s
                add_cell(raster, start + right_cell - 1, d * (1 - a2 - am))
            }
            add_cell(raster, start + right_cell, d * am)
        }
        x = x_next
    }
}

/**
 * A row's coverage, its cells summed and the fill rule applied, each pixel's from 0 to 1; the row's cells are zeroed
 * for the next fill.
 *
 * @param raster The raster.
 * @param row The row, from the region's top.
 * @param rule The fill rule.
 * @param into Where the coverage goes, a value for each of the region's columns.
 * @return Whether any of it's more than 0.
 */
coverage_row :: fn(raster: ptr[mut Raster], row: usize, rule: FillRule, into: mut f32[]) -> bool {
    stride :: raster.width + 2
    start :: row * stride
    sum := cast[f32](0)
    any := false
    for column in cast[usize](0)..<stride {
        at :: start + column
        if at < raster.cells.count {
            sum += raster.cells[at]
            raster.cells[at] = 0
        }
        if column < raster.width && column < into.count {
            magnitude :: if sum < 0 { -sum } else { sum }
            covered := cast[f32](0)
            if rule == .NonZero {
                covered = if magnitude < 1 { magnitude } else { cast[f32](1) }
            }
            else {
                folded :: magnitude - 2 * intrinsics.floor(magnitude / 2)
                covered = if folded > 1 { 2 - folded } else { folded }
            }
            into[column] = covered
            any = any || covered > 0.0001
        }
    }
    return any
}

/**
 * A path flattened into lines in pixels: transformed, and its curves split into lines; added to a polyline path of
 * Moves, Lines and Closes.
 *
 * @param path The path, in its own units.
 * @param transform To pixels.
 * @param into Where the polylines go, added to what's there.
 * @param closing Whether every subpath's closed, as a fill takes it; for a stroke, false, only those the path closes.
 */
flatten :: fn(path: ptr[Path], transform: Affine, into: ptr[mut Path], closing: bool = true) {
    at := cast[usize](0)
    current := Point.{}
    start := Point.{}
    open := false
    for verb in path.verbs {
        if verb == .Move {
            if open && closing {
                close(into)
            }
            current = apply(transform, point_of(path, at))
            start = current
            move_to(into, current.x, current.y)
            open = true
            at += 1
        }
        else if verb == .Line {
            p :: apply(transform, point_of(path, at))
            if !open {
                move_to(into, current.x, current.y)
                start = current
                open = true
            }
            line_to(into, p.x, p.y)
            current = p
            at += 1
        }
        else if verb == .Quad {
            c :: apply(transform, point_of(path, at))
            p :: apply(transform, point_of(path, at + 1))
            if !open {
                move_to(into, current.x, current.y)
                start = current
                open = true
            }
            ddx :: current.x - 2 * c.x + p.x
            ddy :: current.y - 2 * c.y + p.y
            n :: segments_for(intrinsics.square_root(ddx * ddx + ddy * ddy) / (8 * TOLERANCE))
            for i in cast[u32](1)..<n + 1 {
                t :: cast[f32](i) / cast[f32](n)
                u :: 1 - t
                line_to(into, u * u * current.x + 2 * u * t * c.x + t * t * p.x, u * u * current.y + 2 * u * t * c.y + t * t * p.y)
            }
            current = p
            at += 2
        }
        else if verb == .Cubic {
            c1 :: apply(transform, point_of(path, at))
            c2 :: apply(transform, point_of(path, at + 1))
            p :: apply(transform, point_of(path, at + 2))
            if !open {
                move_to(into, current.x, current.y)
                start = current
                open = true
            }
            d1x :: current.x - 2 * c1.x + c2.x
            d1y :: current.y - 2 * c1.y + c2.y
            d2x :: c1.x - 2 * c2.x + p.x
            d2y :: c1.y - 2 * c2.y + p.y
            dd :: intrinsics.maximum(d1x * d1x + d1y * d1y, d2x * d2x + d2y * d2y)
            n :: segments_for(0.75 * intrinsics.square_root(dd) / TOLERANCE)
            for i in cast[u32](1)..<n + 1 {
                t :: cast[f32](i) / cast[f32](n)
                u :: 1 - t
                b0 :: u * u * u
                b1 :: 3 * u * u * t
                b2 :: 3 * u * t * t
                b3 :: t * t * t
                line_to(into, b0 * current.x + b1 * c1.x + b2 * c2.x + b3 * p.x, b0 * current.y + b1 * c1.y + b2 * c2.y + b3 * p.y)
            }
            current = p
            at += 3
        }
        else {
            if open {
                close(into)
                open = false
            }
            current = start
        }
    }
    if open && closing {
        close(into)
    }
}

/** How many lines a curve takes, from the square of how many its curvature needs. */
segments_for :: fn(squared: f32) -> u32 {
    n :: intrinsics.ceil(intrinsics.square_root(squared))
    if !(n >= 1) {
        return 1
    }
    return if n > cast[f32](MAX_SEGMENTS) { MAX_SEGMENTS } else { cast[u32](n) }
}

/** A path's point, or the origin past its end. */
point_of :: fn(path: ptr[Path], at: usize) -> Point {
    return if at < path.points.count { path.points[at] } else { Point.{} }
}

/** The bounds of a polyline path, whole pixels holding every point; empty for none. */
bounds_of :: fn(path: ptr[Path]) -> Rect {
    if path.points.count == 0 {
        return Rect.{}
    }
    x0 := cast[f32](1e30)
    y0 := cast[f32](1e30)
    x1 := cast[f32](-1e30)
    y1 := cast[f32](-1e30)
    for p in path.points {
        x0 = intrinsics.minimum(x0, p.x)
        y0 = intrinsics.minimum(y0, p.y)
        x1 = intrinsics.maximum(x1, p.x)
        y1 = intrinsics.maximum(y1, p.y)
    }
    // Clamped well within i32, so a wild coordinate can't overflow
    limit :: cast[f32](1 << 24)
    return Rect.{x0 = cast[i32](intrinsics.floor(intrinsics.maximum(x0, -limit))), y0 = cast[i32](intrinsics.floor(intrinsics.maximum(y0, -limit))),
        x1 = cast[i32](intrinsics.ceil(intrinsics.minimum(x1, limit))) + 1, y1 = cast[i32](intrinsics.ceil(intrinsics.minimum(y1, limit))) + 1}
}

/** Add a polyline path's edges to a raster: each Line from the point before it, each subpath closed. */
add_polylines :: fn(raster: ptr[mut Raster], path: ptr[Path]) {
    at := cast[usize](0)
    current := Point.{}
    start := Point.{}
    for verb in path.verbs {
        if verb == .Move {
            if at > 0 {
                add_line(raster, current, start)
            }
            current = point_of(path, at)
            start = current
            at += 1
        }
        else if verb == .Line {
            p :: point_of(path, at)
            add_line(raster, current, p)
            current = p
            at += 1
        }
        else if verb == .Close {
            add_line(raster, current, start)
            current = start
        }
    }
}
