package canvas

import intrinsics from "base"
import runtime from "base"
import math from "std"

/*
 * Strokes, from a path flattened to polylines in pixels: each segment a rectangle of the stroke's width, each corner a
 * join, each open end a cap, each piece a polygon turned the same way round, so filling them all by the non-zero rule
 * gives their union. Dashes cut the polylines into the pieces drawn first.
 */

/** How a corner's outer side is drawn. */
Join :: enum {
    /** Its edges extended to meet, unless they'd go past the miter limit, when it's bevelled. */
    Miter,
    /** Rounded, a circle of the stroke's width. */
    Round,
    /** Cut straight across. */
    Bevel,
}

/** How an open end is drawn. */
Cap :: enum {
    /** Square, at the end. */
    Butt,
    /** Rounded, a half circle past the end. */
    Round,
    /** Square, half the width past the end. */
    Square,
}

/** The most entries of a dash pattern. */
MAX_DASHES :: 16
/** The most steps a stroke's dashes are walked in; past them, a path too long for its pattern stops being dashed. */
MAX_DASH_STEPS :: 1 << 20

/** How a path is stroked. */
Stroke :: struct {
    /** Its width, in the path's units. */
    width : f32 = 1,
    join : Join = .Miter,
    cap : Cap = .Butt,
    /** For a miter join, the most its point may be past the corner, as a multiple of half the width; past it, bevelled. */
    miter_limit : f32 = 4,
    /** Dashes: on, off, on, off, ... lengths in the path's units, the first dash_count of them; none for a solid line. */
    dashes : f32[MAX_DASHES],
    dash_count : usize,
    /** How far into the pattern the stroke starts. */
    dash_offset : f32,
}

/** A polyline of a flattened path, by its points' places in it, and whether it's closed. */
Polyline :: struct {
    first : usize,
    count : usize,
    closed : bool,
}

/**
 * A stroke's outline: each polyline of a flattened path, dashed if the stroke has dashes, made polygons whose union is
 * the stroke, added to a path to fill by the non-zero rule.
 *
 * @param flat The path flattened to polylines in pixels (flatten).
 * @param stroke The stroke, its lengths in the path's units.
 * @param scale Pixels per path unit (scale_of the transform), which the width and dashes are scaled by.
 * @param into Where the polygons go.
 * @param scratch A path for the dashes' pieces.
 */
stroke_outline :: fn(flat: ptr[Path], stroke: ptr[Stroke], scale: f32, into: ptr[mut Path], scratch: ptr[mut Path]) {
    half :: stroke.width * scale / 2
    if !(half > 0) {
        return void
    }
    source :: if stroke.dash_count > 0 { dashed(flat, stroke, scale, scratch) } else { flat }
    // Each polyline: its points from a Move to the next Move or Close
    at := cast[usize](0)
    first := cast[usize](0)
    count := cast[usize](0)
    for verb in source.verbs {
        if verb == .Move {
            if count > 0 {
                stroke_polyline(source, Polyline.{first = first, count = count}, stroke, half, into)
            }
            first = at
            count = 1
            at += 1
        }
        else if verb == .Line {
            count += 1
            at += 1
        }
        else if verb == .Close {
            if count > 0 {
                stroke_polyline(source, Polyline.{first = first, count = count, closed = true}, stroke, half, into)
            }
            count = 0
        }
    }
    if count > 0 {
        stroke_polyline(source, Polyline.{first = first, count = count}, stroke, half, into)
    }
}

/** Stroke one polyline: its segments, joins and caps. */
stroke_polyline :: fn(path: ptr[Path], line: Polyline, stroke: ptr[Stroke], half: f32, into: ptr[mut Path]) {
    // Its distinct points: one repeated adds nothing
    points : Point[..]
    defer runtime.array_free(&points)
    for i in cast[usize](0)..<line.count {
        p :: point_of(path, line.first + i)
        if points.count == 0 || length(minus(p, points[points.count - 1])) > 0.0001 {
            runtime.array_add(&points, p)
        }
    }
    closed := line.closed
    n := points.count
    // A closed one's last point, back at its first, is the first
    if closed && n > 1 && length(minus(points[0], points[n - 1])) <= 0.0001 {
        n -= 1
    }
    if n == 0 {
        return void
    }
    if n == 1 {
        // A dot: a cap's shape, round or square, or nothing for butt
        p :: nth(points[0..<points.count], 0)
        if stroke.cap == .Round {
            add_circle(into, p, half)
        }
        else if stroke.cap == .Square {
            add_polygon(into, Point.[Point.{x = p.x - half, y = p.y - half}, Point.{x = p.x + half, y = p.y - half},
                Point.{x = p.x + half, y = p.y + half}, Point.{x = p.x - half, y = p.y + half}])
        }
        return void
    }
    if n == 2 {
        closed = false
    }
    segments :: if closed { n } else { n - 1 }
    for s in cast[usize](0)..<segments {
        a := nth(points[0..<points.count], s % n)
        b := nth(points[0..<points.count], (s + 1) % n)
        d :: unit(minus(b, a))
        // Square caps lengthen the first and last segments
        if !closed && stroke.cap == .Square {
            if s == 0 {
                a = Point.{x = a.x - d.x * half, y = a.y - d.y * half}
            }
            if s == segments - 1 {
                b = Point.{x = b.x + d.x * half, y = b.y + d.y * half}
            }
        }
        nx :: -d.y * half
        ny :: d.x * half
        add_polygon(into, Point.[Point.{x = a.x + nx, y = a.y + ny}, Point.{x = b.x + nx, y = b.y + ny},
            Point.{x = b.x - nx, y = b.y - ny}, Point.{x = a.x - nx, y = a.y - ny}])
    }
    // Joins: at every corner between two segments
    corners :: if closed { n } else { n - 2 }
    for c in cast[usize](0)..<corners {
        index :: if closed { c } else { c + 1 }
        before :: nth(points[0..<points.count], (index + n - 1) % n)
        corner :: nth(points[0..<points.count], index % n)
        after :: nth(points[0..<points.count], (index + 1) % n)
        add_join(into, before, corner, after, stroke, half)
    }
    // Round caps
    if !closed && stroke.cap == .Round {
        add_circle(into, nth(points[0..<points.count], 0), half)
        add_circle(into, nth(points[0..<points.count], n - 1), half)
    }
}

/** A point of a list, or the origin past its end. */
nth :: fn(points: Point[], index: usize) -> Point {

    return if index < points.count { points[index] } else { Point.{} }
}

/** A corner's join: the wedge on its outer side, mitered, rounded or bevelled. */
add_join :: fn(into: ptr[mut Path], before: Point, corner: Point, after: Point, stroke: ptr[Stroke], half: f32) {
    d1 :: unit(minus(corner, before))
    d2 :: unit(minus(after, corner))
    cross :: d1.x * d2.y - d1.y * d2.x
    dot :: d1.x * d2.x + d1.y * d2.y
    if cross > -0.0001 && cross < 0.0001 && dot > 0 {
        return void
    }
    if stroke.join == .Round {
        add_circle(into, corner, half)
        return void
    }
    // The outer side: right of the path for a left turn, left of it for a right turn
    side :: if cross > 0 { cast[f32](-1) } else { cast[f32](1) }
    n1 :: Point.{x = -d1.y * side, y = d1.x * side}
    n2 :: Point.{x = -d2.y * side, y = d2.x * side}
    p1 :: Point.{x = corner.x + n1.x * half, y = corner.y + n1.y * half}
    p2 :: Point.{x = corner.x + n2.x * half, y = corner.y + n2.y * half}
    if stroke.join == .Miter {
        bisector :: unit(Point.{x = n1.x + n2.x, y = n1.y + n2.y})
        cosine :: bisector.x * n1.x + bisector.y * n1.y
        if cosine > 0.0001 && 1 / cosine <= stroke.miter_limit {
            reach :: half / cosine
            tip :: Point.{x = corner.x + bisector.x * reach, y = corner.y + bisector.y * reach}
            add_polygon(into, Point.[corner, p1, tip, p2])
            return void
        }
    }
    add_polygon(into, Point.[corner, p1, p2])
}

/** A vector made a unit long; the zero vector stays zero. */
unit :: fn(v: Point) -> Point {
    l :: length(v)
    return if l > 0 { Point.{x = v.x / l, y = v.y / l} } else { Point.{} }
}

/** A closed polygon added, turned counter-clockwise in pixels (positive area, y down), so the non-zero rule unions them. */
add_polygon :: fn(into: ptr[mut Path], corners: Point[]) {
    if corners.count < 3 {
        return void
    }
    area := cast[f32](0)
    for p, i in corners {
        q :: corners[(i + 1) % corners.count]
        area += p.x * q.y - q.x * p.y
    }
    if area >= 0 {
        for p, i in corners {
            if i == 0 {
                move_to(into, p.x, p.y)
            }
            else {
                line_to(into, p.x, p.y)
            }
        }
    }
    else {
        for i in cast[usize](0)..<corners.count {
            j :: corners.count - 1 - i
            p :: if j < corners.count { corners[j] } else { Point.{} }
            if i == 0 {
                move_to(into, p.x, p.y)
            }
            else {
                line_to(into, p.x, p.y)
            }
        }
    }
    close(into)
}

/** A circle as a polygon, enough sides that it strays from the circle by no more than the tolerance. */
add_circle :: fn(into: ptr[mut Path], centre: Point, radius: f32) {
    if !(radius > 0) {
        return void
    }
    // A side's chord is within TOLERANCE of the arc when its angle is 2 acos(1 - TOLERANCE / radius)
    ratio :: if TOLERANCE < radius { 1 - TOLERANCE / radius } else { cast[f32](0) }
    angle :: 2 * math.acos(ratio)
    sides_wanted :: if angle > 0 { intrinsics.ceil(cast[f32](math.TAU) / angle) } else { cast[f32](8) }
    sides :: if sides_wanted < 8 { cast[usize](8) } else if sides_wanted > 256 { cast[usize](256) } else { cast[usize](sides_wanted) }
    for i in cast[usize](0)..<sides {
        theta :: cast[f32](math.TAU) * cast[f32](i) / cast[f32](sides)
        s, c :: math.sin_cos(theta)
        if i == 0 {
            move_to(into, centre.x + c * radius, centre.y + s * radius)
        }
        else {
            line_to(into, centre.x + c * radius, centre.y + s * radius)
        }
    }
    close(into)
}

/**
 * A flattened path cut into its dashes: each polyline walked along, the pattern's on lengths kept as open polylines.
 *
 * @return The dashes, in scratch; for a path that would take more than MAX_DASH_STEPS pieces of the pattern, those walked by then.
 */
dashed :: fn(flat: ptr[Path], stroke: ptr[Stroke], scale: f32, scratch: ptr[mut Path]) -> ptr[Path] {
    reset(scratch)
    pattern : f32[MAX_DASHES]
    total := cast[f32](0)
    count :: if stroke.dash_count < MAX_DASHES { stroke.dash_count } else { cast[usize](MAX_DASHES) }
    for i in cast[usize](0)..<MAX_DASHES {
        if i < count {
            pattern[i] = intrinsics.maximum(stroke.dashes[i] * scale, 0)
            total += pattern[i]
        }
    }
    kept :: pattern[0..<MAX_DASHES]
    used :: if count <= kept.count { kept[0..<count] } else { kept }
    steps := cast[usize](MAX_DASH_STEPS)
    if !(total > 0) {
        return flat
    }
    at := cast[usize](0)
    first := cast[usize](0)
    points := cast[usize](0)
    for verb in flat.verbs {
        if verb == .Move {
            if points > 0 {
                dash_polyline(flat, Polyline.{first = first, count = points}, used, total, stroke.dash_offset * scale, scratch, &steps)
            }
            first = at
            points = 1
            at += 1
        }
        else if verb == .Line {
            points += 1
            at += 1
        }
        else if verb == .Close {
            if points > 0 {
                dash_polyline(flat, Polyline.{first = first, count = points, closed = true}, used, total, stroke.dash_offset * scale, scratch, &steps)
            }
            points = 0
        }
    }
    if points > 0 {
        dash_polyline(flat, Polyline.{first = first, count = points}, used, total, stroke.dash_offset * scale, scratch, &steps)
    }
    return scratch
}

/** One polyline's dashes, walked from its start with the pattern's phase, each step taken from what's left of steps. */
dash_polyline :: fn(path: ptr[Path], line: Polyline, pattern: f32[], total: f32, offset: f32, into: ptr[mut Path], steps: ptr[mut usize]) {
    // Where in the pattern the walk starts
    phase := offset - total * intrinsics.floor(offset / total)
    index := cast[usize](0)
    loop {
        if index >= pattern.count || phase < pattern[index] {
            break
        }
        phase -= pattern[index]
        index += 1
    }
    while true
    if index >= pattern.count {
        index = 0
    }
    left := if index < pattern.count { pattern[index] - phase } else { total }
    on := index % 2 == 0
    drawing := false
    segments :: if line.closed { line.count } else { line.count - 1 }
    for s in cast[usize](0)..<segments {
        a :: point_of(path, line.first + s)
        b :: point_of(path, line.first + (s + 1) % line.count)
        segment :: length(minus(b, a))
        done := cast[f32](0)
        loop {
            // Done, out of steps, or NaN: the walk ends
            if !(done < segment) {
                break
            }
            if steps^ == 0 {
                return void
            }
            steps^ -= 1
            step :: intrinsics.minimum(left, segment - done)
            t0 :: done / segment
            t1 :: (done + step) / segment
            if on {
                if !drawing {
                    move_to(into, a.x + (b.x - a.x) * t0, a.y + (b.y - a.y) * t0)
                    drawing = true
                }
                line_to(into, a.x + (b.x - a.x) * t1, a.y + (b.y - a.y) * t1)
            }
            done += step
            left -= step
            if left <= 0.00001 {
                index = (index + 1) % pattern.count
                left = pattern[index]
                on = !on
                drawing = false
                // A zero-length entry skipped
                if left <= 0 {
                    index = (index + 1) % pattern.count
                    left = pattern[index]
                    on = !on
                }
            }
        }
        while true
    }
}
