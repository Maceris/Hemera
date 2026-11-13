package canvas

import runtime from "base"
import fonts from "std"

/** What a path's command does. */
Verb :: enum #backed_by(u8) {
    /** Start a subpath at a point. */
    Move,
    /** A line to a point. */
    Line,
    /** A quadratic curve through a control point to a point: two points. */
    Quad,
    /** A cubic curve through two control points to a point: three points. */
    Cubic,
    /** Close the subpath, a line back to where it started. */
    Close,
}

/** A path: subpaths of lines and curves, in the units the canvas's transform takes. */
Path :: struct {
    verbs : Verb[..],
    points : Point[..],
}

/** κ, the control points' distance for a quarter circle of radius 1 drawn as a cubic. */
KAPPA : f32 : 0.5522847498

/** Start a subpath. */
move_to :: fn(path: ptr[mut Path], x: f32, y: f32) {
    runtime.array_add(&path.verbs, Verb.Move)
    runtime.array_add(&path.points, Point.{x = x, y = y})
}

/** A line to a point. */
line_to :: fn(path: ptr[mut Path], x: f32, y: f32) {
    runtime.array_add(&path.verbs, Verb.Line)
    runtime.array_add(&path.points, Point.{x = x, y = y})
}

/** A quadratic curve through a control point to a point. */
quad_to :: fn(path: ptr[mut Path], cx: f32, cy: f32, x: f32, y: f32) {
    runtime.array_add(&path.verbs, Verb.Quad)
    runtime.array_add(&path.points, Point.{x = cx, y = cy})
    runtime.array_add(&path.points, Point.{x = x, y = y})
}

/** A cubic curve through two control points to a point. */
cubic_to :: fn(path: ptr[mut Path], c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32) {
    runtime.array_add(&path.verbs, Verb.Cubic)
    runtime.array_add(&path.points, Point.{x = c1x, y = c1y})
    runtime.array_add(&path.points, Point.{x = c2x, y = c2y})
    runtime.array_add(&path.points, Point.{x = x, y = y})
}

/** Close the subpath. */
close :: fn(path: ptr[mut Path]) {
    runtime.array_add(&path.verbs, Verb.Close)
}

/** Empty a path, for reuse. */
reset :: fn(path: ptr[mut Path]) {
    runtime.array_reset(&path.verbs)
    runtime.array_reset(&path.points)
}

/** Give back a path's arrays. */
free_path :: fn(path: ptr[mut Path]) {
    runtime.array_free(&path.verbs)
    runtime.array_free(&path.points)
}

/** A rectangle, as a closed subpath. */
rect :: fn(path: ptr[mut Path], x: f32, y: f32, width: f32, height: f32) {
    move_to(path, x, y)
    line_to(path, x + width, y)
    line_to(path, x + width, y + height)
    line_to(path, x, y + height)
    close(path)
}

/** An ellipse, as a closed subpath of four cubics, about its centre. */
ellipse :: fn(path: ptr[mut Path], cx: f32, cy: f32, rx: f32, ry: f32) {
    kx :: rx * KAPPA
    ky :: ry * KAPPA
    move_to(path, cx + rx, cy)
    cubic_to(path, cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry)
    cubic_to(path, cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy)
    cubic_to(path, cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry)
    cubic_to(path, cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy)
    close(path)
}

/** A circle. */
circle :: fn(path: ptr[mut Path], cx: f32, cy: f32, radius: f32) {
    ellipse(path, cx, cy, radius, radius)
}

/** A rectangle with its corners rounded by a radius, no more than half its shorter side. */
rounded_rect :: fn(path: ptr[mut Path], x: f32, y: f32, width: f32, height: f32, radius: f32) {
    half :: (if width < height { width } else { height }) / 2
    r :: if radius < half { radius } else { half }
    if r <= 0 {
        rect(path, x, y, width, height)
        return void
    }
    k :: r * KAPPA
    move_to(path, x + r, y)
    line_to(path, x + width - r, y)
    cubic_to(path, x + width - r + k, y, x + width, y + r - k, x + width, y + r)
    line_to(path, x + width, y + height - r)
    cubic_to(path, x + width, y + height - r + k, x + width - r + k, y + height, x + width - r, y + height)
    line_to(path, x + r, y + height)
    cubic_to(path, x + r - k, y + height, x, y + height - r + k, x, y + height - r)
    line_to(path, x, y + r)
    cubic_to(path, x, y + r - k, x + r - k, y, x + r, y)
    close(path)
}

/**
 * A font's glyph outline added to a path: its design units scaled to a size, y flipped to go down, at a pen position.
 *
 * @param path The path added to.
 * @param outline The glyph's outline (fonts.glyph_outline), in design units, y up.
 * @param scale Pixels per design unit (fonts.scale_of).
 * @param x The pen's x, where the glyph's origin goes.
 * @param y The baseline's y.
 */
add_outline :: fn(path: ptr[mut Path], outline: ptr[fonts.Outline], scale: f32, x: f32, y: f32) {
    at := cast[usize](0)
    for verb in outline.verbs {
        if verb == .Move || verb == .Line {
            p :: point_at(outline, at, scale, x, y)
            if verb == .Move {
                move_to(path, p.x, p.y)
            }
            else {
                line_to(path, p.x, p.y)
            }
            at += 1
        }
        else if verb == .Quad {
            c :: point_at(outline, at, scale, x, y)
            p :: point_at(outline, at + 1, scale, x, y)
            quad_to(path, c.x, c.y, p.x, p.y)
            at += 2
        }
        else {
            close(path)
        }
    }
}

/** An outline's point, scaled and flipped to the pen. */
point_at :: fn(outline: ptr[fonts.Outline], at: usize, scale: f32, x: f32, y: f32) -> Point {
    if at >= outline.points.count {
        return Point.{x = x, y = y}
    }
    p :: outline.points[at]
    return Point.{x = x + p.x * scale, y = y - p.y * scale}
}
