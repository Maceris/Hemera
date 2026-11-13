package canvas

import intrinsics from "base"

/** The most stops a gradient has. */
MAX_STOPS :: 8

/** A gradient's colour at an offset along it, from 0 to 1. */
Stop :: struct {
    offset : f32,
    color : Color,
}

/**
 * A gradient: linear, from start to end; or radial, from centre start out to radius. Its stops, in order of offset,
 * the first stop_count of them; before the first and after the last, the nearest's colour.
 */
Gradient :: struct {
    start : Point,
    end : Point,
    radius : f32,
    stops : Stop[MAX_STOPS],
    stop_count : usize,
}

/** What a shape's filled or stroked with. */
Paint :: union {
    /** One colour. */
    Solid(Color),
    /** A linear gradient, start to end, in the path's units. */
    Linear(Gradient),
    /** A radial gradient, its centre start, out to radius, in the path's units. */
    Radial(Gradient),
}

/** Add a stop to a gradient, if there's room. */
add_stop :: fn(gradient: ptr[mut Gradient], offset: f32, color: Color) {
    if gradient.stop_count < MAX_STOPS {
        gradient.stops[gradient.stop_count] = Stop.{offset = offset, color = color}
        gradient.stop_count += 1
    }
}

/** A colour premultiplied by its alpha, as a pixel's channels from 0 to 1: blue, green, red, alpha. */
Premultiplied :: struct {
    b : f32,
    g : f32,
    r : f32,
    a : f32,
}

/** A colour premultiplied. */
premultiply :: fn(color: Color) -> Premultiplied {
    a :: clamp_unit(color.a)
    return Premultiplied.{b = clamp_unit(color.b) * a, g = clamp_unit(color.g) * a, r = clamp_unit(color.r) * a, a = a}
}

/** A value kept from 0 to 1; NaN is 0. */
clamp_unit :: fn(value: f32) -> f32 {
    return if value > 0 { (if value < 1 { value } else { cast[f32](1) }) } else { cast[f32](0) }
}

/** A gradient's stop, or a transparent one past its stops. */
stop_at :: fn(gradient: Gradient, index: usize) -> Stop {
    return if index < gradient.stops.count { gradient.stops[index] } else { Stop.{} }
}

/** A gradient's colour at an offset, interpolated between its stops, premultiplied. */
gradient_at :: fn(gradient: Gradient, offset: f32) -> Premultiplied {
    count :: if gradient.stop_count < MAX_STOPS { gradient.stop_count } else { cast[usize](MAX_STOPS) }
    if count == 0 {
        return Premultiplied.{}
    }
    if offset <= stop_at(gradient, 0).offset {
        return premultiply(stop_at(gradient, 0).color)
    }
    for i in cast[usize](1)..<count {
        if offset <= stop_at(gradient, i).offset {
            low :: stop_at(gradient, i - 1)
            high :: stop_at(gradient, i)
            span :: high.offset - low.offset
            t :: if span > 0 { (offset - low.offset) / span } else { cast[f32](1) }
            // Interpolated premultiplied, so a transparent stop doesn't darken
            a :: premultiply(low.color)
            b :: premultiply(high.color)
            return Premultiplied.{b = a.b + (b.b - a.b) * t, g = a.g + (b.g - a.g) * t, r = a.r + (b.r - a.r) * t, a = a.a + (b.a - a.a) * t}
        }
    }
    return premultiply(stop_at(gradient, count - 1).color)
}

/**
 * A paint's colour at a point in the path's units, premultiplied.
 *
 * @param paint The paint.
 * @param point Where, in the path's units: the pixel's centre, transformed back.
 * @return Its colour there.
 */
paint_at :: fn(paint: ptr[Paint], point: Point) -> Premultiplied {
    match paint^ {
        case Solid(color) => return premultiply(color)
        case Linear(gradient) => {
            dx :: gradient.end.x - gradient.start.x
            dy :: gradient.end.y - gradient.start.y
            squared :: dx * dx + dy * dy
            t :: if squared > 0 { ((point.x - gradient.start.x) * dx + (point.y - gradient.start.y) * dy) / squared } else { cast[f32](0) }
            return gradient_at(gradient, t)
        }
        case Radial(gradient) => {
            dx :: point.x - gradient.start.x
            dy :: point.y - gradient.start.y
            distance :: intrinsics.square_root(dx * dx + dy * dy)
            t :: if gradient.radius > 0 { distance / gradient.radius } else { cast[f32](1) }
            return gradient_at(gradient, t)
        }
    }
}

/** Whether a paint's the same everywhere, so it's worked out once for a fill. */
is_solid :: fn(paint: ptr[Paint]) -> bool {
    match paint^ {
        case Solid(color) => return true
        case _ => return false
    }
}
