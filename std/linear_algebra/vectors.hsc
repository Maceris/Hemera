package linear_algebra

import intrinsics from "base"

/*
 * Functions on fixed arrays of numbers as vectors, of any length unless they say otherwise, as GLSL has them. T is the
 * element type, and n the count, both worked out from the arguments.
 */

/**
 * The dot product: the sum of the elements' products.
 *
 * @tparam T The elements' type, a number.
 * @tparam n How many elements.
 * @param a One array.
 * @param b The other, of the same type.
 * @return a[0] × b[0] + a[1] × b[1] + ..., summed from the first; 0 for no elements.
 */
dot :: fn[T, n: usize](a: T[n], b: T[n]) -> T {
    sum : T
    for i in 0..<n {
        sum += a[i] * b[i]
    }
    return sum
}

/**
 * The cross product of two arrays of three, perpendicular to both, in a right-handed system.
 *
 * @tparam T The elements' type, a number.
 * @param a The first.
 * @param b The second.
 * @return a × b: its length is |a| |b| sin θ, and cross(x, y) is z.
 */
cross :: fn[T](a: T[3], b: T[3]) -> T[3] {
    return T.[a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
}

/**
 * The squared length, which needs no square root, for comparing lengths.
 *
 * @tparam T The elements' type, a number.
 * @tparam n How many elements.
 * @param a The array.
 * @return dot(a, a).
 */
length_squared :: fn[T, n: usize](a: T[n]) -> T {
    return dot(a, a)
}

/**
 * The Euclidean length.
 *
 * @tparam T The elements' type: f32 or f64.
 * @tparam n How many elements.
 * @param a The array.
 * @return √(dot(a, a)), correctly rounded from the dot product, which overflows to infinity for huge elements.
 */
length :: fn[T, n: usize](a: T[n]) -> T {
    return intrinsics.square_root(dot(a, a))
}

/**
 * The distance between two points.
 *
 * @tparam T The elements' type: f32 or f64.
 * @tparam n How many elements.
 * @param a One point.
 * @param b The other.
 * @return length(a - b).
 */
distance :: fn[T, n: usize](a: T[n], b: T[n]) -> T {
    return length(a - b)
}

/**
 * Scale an array to length 1, keeping its direction.
 *
 * @tparam T The elements' type: f32 or f64.
 * @tparam n How many elements.
 * @param a The array.
 * @return a / length(a); a itself, all zeros, for a zero array, which has no direction.
 */
normalize :: fn[T, n: usize](a: T[n]) -> T[n] {
    size :: length(a)
    if size == 0 {
        return a
    }
    return a * (1 / size)
}

/**
 * Interpolate between two arrays, element by element.
 *
 * @tparam T The elements' type: f32 or f64.
 * @tparam n How many elements.
 * @param a Where it starts, at 0.
 * @param b Where it ends, at 1.
 * @param t How far: 0 gives a exactly and 1 gives b exactly; beyond them it extrapolates.
 * @return a × (1 - t) + b × t.
 */
lerp :: fn[T, n: usize](a: T[n], b: T[n], t: T) -> T[n] {
    return a * (1 - t) + b * t
}

/**
 * The lesser of each pair of elements.
 *
 * @tparam T The elements' type, a number.
 * @tparam n How many elements.
 * @param a One array.
 * @param b The other.
 * @return Each element the lesser of a's and b's, a's when they're equal or b's is NaN.
 */
minimum :: fn[T, n: usize](a: T[n], b: T[n]) -> T[n] {
    result := a
    for i in 0..<n {
        if b[i] < a[i] {
            result[i] = b[i]
        }
    }
    return result
}

/**
 * The greater of each pair of elements.
 *
 * @tparam T The elements' type, a number.
 * @tparam n How many elements.
 * @param a One array.
 * @param b The other.
 * @return Each element the greater of a's and b's, a's when they're equal or b's is NaN.
 */
maximum :: fn[T, n: usize](a: T[n], b: T[n]) -> T[n] {
    result := a
    for i in 0..<n {
        if b[i] > a[i] {
            result[i] = b[i]
        }
    }
    return result
}

/**
 * Keep each element between bounds.
 *
 * @tparam T The elements' type, a number.
 * @tparam n How many elements.
 * @param a The array.
 * @param low Each element's least; at most high's.
 * @param high Each element's greatest.
 * @return Each element of a, raised to low's or lowered to high's where it's beyond them.
 */
clamp :: fn[T, n: usize](a: T[n], low: T[n], high: T[n]) -> T[n] {
    return minimum(maximum(a, low), high)
}

/**
 * Each element's absolute value.
 *
 * @tparam T The elements' type: a signed integer or a float.
 * @tparam n How many elements.
 * @param a The array.
 * @return Each element without its sign; for an integer's least, itself, as it has no positive.
 */
absolute :: fn[T, n: usize](a: T[n]) -> T[n] {
    result := a
    for i in 0..<n {
        result[i] = abs(a[i])
    }
    return result
}

/**
 * Reflect a direction off a surface.
 *
 * @tparam T The elements' type: f32 or f64.
 * @tparam n How many elements.
 * @param incident The direction arriving.
 * @param normal The surface's normal, of length 1.
 * @return incident - 2 dot(normal, incident) normal: the direction leaving, as off a mirror.
 */
reflect :: fn[T, n: usize](incident: T[n], normal: T[n]) -> T[n] {
    return incident - normal * (2 * dot(normal, incident))
}

/**
 * Refract a direction through a surface, by Snell's law.
 *
 * @tparam T The elements' type: f32 or f64.
 * @tparam n How many elements.
 * @param incident The direction arriving, of length 1.
 * @param normal The surface's normal, of length 1, against incident.
 * @param ratio The ratio of the refractive indices, the side it comes from over the side it goes to.
 * @return The direction through, of length 1; all zeros for total internal reflection, where none goes through.
 */
refract :: fn[T, n: usize](incident: T[n], normal: T[n], ratio: T) -> T[n] {
    cosine :: dot(normal, incident)
    k :: 1 - ratio * ratio * (1 - cosine * cosine)
    if k < 0 {
        zero : T[n]
        return zero
    }
    return incident * ratio - normal * (ratio * cosine + intrinsics.square_root(k))
}

/**
 * Turn a normal to face a direction, as GLSL's faceforward.
 *
 * @tparam T The elements' type: f32 or f64.
 * @tparam n How many elements.
 * @param normal The normal.
 * @param incident The direction it should face against.
 * @param reference The normal whose side decides.
 * @return normal where dot(reference, incident) is below 0, -normal otherwise.
 */
face_forward :: fn[T, n: usize](normal: T[n], incident: T[n], reference: T[n]) -> T[n] {
    if dot(reference, incident) < 0 {
        return normal
    }
    return -normal
}

/**
 * Apply a function to each element, like std/math's, as GLSL's functions work on vectors.
 *
 * @tparam T The elements' type.
 * @tparam n How many elements.
 * @param a The array.
 * @param function What each element is given to, like math.sin[f32].
 * @return Each element's result, in order.
 */
map :: fn[T, n: usize](a: T[n], function: (fn(x: T) -> T)) -> T[n] {
    result : T[n]
    for i in 0..<n {
        result[i] = function(a[i])
    }
    return result
}

/**
 * Apply a function of two to each pair of elements, like math.power or math.atan2.
 *
 * @tparam T The elements' type.
 * @tparam n How many elements.
 * @param a The first arguments.
 * @param b The second arguments.
 * @param function What each pair is given to.
 * @return Each pair's result, in order.
 */
map_pairs :: fn[T, n: usize](a: T[n], b: T[n], function: (fn(x: T, y: T) -> T)) -> T[n] {
    result : T[n]
    for i in 0..<n {
        result[i] = function(a[i], b[i])
    }
    return result
}
