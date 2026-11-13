package canvas

import intrinsics from "base"
import math from "std"

/** A point, or a vector, in pixels or a path's units. */
Point :: struct {
    x : f32,
    y : f32,
}

/** A rectangle of whole pixels: from (x0, y0) up to, but not including, (x1, y1); empty when x1 <= x0 or y1 <= y0. */
Rect :: struct {
    x0 : i32,
    y0 : i32,
    x1 : i32,
    y1 : i32,
}

/** An affine transform: x' = a x + c y + e, y' = b x + d y + f. The default is the identity. */
Affine :: struct {
    a : f32 = 1,
    b : f32,
    c : f32,
    d : f32 = 1,
    e : f32,
    f : f32,
}

/** A colour: red, green, blue and alpha from 0 to 1, in sRGB, not premultiplied. */
Color :: struct {
    r : f32,
    g : f32,
    b : f32,
    a : f32 = 1,
}

/** A colour from 8-bit red, green and blue, opaque. */
rgb :: fn(r: u8, g: u8, b: u8) -> Color {
    return Color.{r = cast[f32](r) / 255, g = cast[f32](g) / 255, b = cast[f32](b) / 255}
}

/** A colour from 8-bit red, green, blue and alpha. */
rgba :: fn(r: u8, g: u8, b: u8, a: u8) -> Color {
    return Color.{r = cast[f32](r) / 255, g = cast[f32](g) / 255, b = cast[f32](b) / 255, a = cast[f32](a) / 255}
}

/** Whether a rectangle has no pixels. */
is_empty :: fn(rect: Rect) -> bool {
    return rect.x1 <= rect.x0 || rect.y1 <= rect.y0
}

/** Where two rectangles overlap; empty if they don't. */
intersect :: fn(a: Rect, b: Rect) -> Rect {
    return Rect.{x0 = if a.x0 > b.x0 { a.x0 } else { b.x0 }, y0 = if a.y0 > b.y0 { a.y0 } else { b.y0 },
        x1 = if a.x1 < b.x1 { a.x1 } else { b.x1 }, y1 = if a.y1 < b.y1 { a.y1 } else { b.y1 }}
}

/** The smallest rectangle holding both; one that's empty is left out. */
union_of :: fn(a: Rect, b: Rect) -> Rect {
    if is_empty(a) {
        return b
    }
    if is_empty(b) {
        return a
    }
    return Rect.{x0 = if a.x0 < b.x0 { a.x0 } else { b.x0 }, y0 = if a.y0 < b.y0 { a.y0 } else { b.y0 },
        x1 = if a.x1 > b.x1 { a.x1 } else { b.x1 }, y1 = if a.y1 > b.y1 { a.y1 } else { b.y1 }}
}

/** A point transformed. */
apply :: fn(m: Affine, p: Point) -> Point {
    return Point.{x = m.a * p.x + m.c * p.y + m.e, y = m.b * p.x + m.d * p.y + m.f}
}

/** One transform after another: first applied first. */
then :: fn(first: Affine, second: Affine) -> Affine {
    return Affine.{a = second.a * first.a + second.c * first.b, b = second.b * first.a + second.d * first.b,
        c = second.a * first.c + second.c * first.d, d = second.b * first.c + second.d * first.d,
        e = second.a * first.e + second.c * first.f + second.e, f = second.b * first.e + second.d * first.f + second.f}
}

/** A transform's inverse; the identity for one that can't be inverted, as a scale by 0. */
inverse :: fn(m: Affine) -> Affine {
    det :: m.a * m.d - m.b * m.c
    if det == 0 {
        return Affine.{}
    }
    inv :: 1 / det
    return Affine.{a = m.d * inv, b = -m.b * inv, c = -m.c * inv, d = m.a * inv, e = (m.c * m.f - m.d * m.e) * inv,
        f = (m.b * m.e - m.a * m.f) * inv}
}

/** How much a transform scales lengths, on average: the square root of its determinant's magnitude. */
scale_of :: fn(m: Affine) -> f32 {
    det :: m.a * m.d - m.b * m.c
    return intrinsics.square_root(if det < 0 { -det } else { det })
}

/** A translation. */
translation :: fn(x: f32, y: f32) -> Affine {
    return Affine.{e = x, f = y}
}

/** A scale about the origin. */
scaling :: fn(x: f32, y: f32) -> Affine {
    return Affine.{a = x, d = y}
}

/** A rotation about the origin, by radians, from x toward y. */
rotation :: fn(radians: f32) -> Affine {
    s, c :: math.sin_cos(radians)
    return Affine.{a = c, b = s, c = -s, d = c}
}

/** Whether a transform only moves, neither scaling, rotating nor shearing. */
is_translation :: fn(m: Affine) -> bool {
    return m.a == 1 && m.b == 0 && m.c == 0 && m.d == 1
}

/** A vector's length. */
length :: fn(p: Point) -> f32 {
    return intrinsics.square_root(p.x * p.x + p.y * p.y)
}

/** Two points' difference, q - p. */
minus :: fn(q: Point, p: Point) -> Point {
    return Point.{x = q.x - p.x, y = q.y - p.y}
}
