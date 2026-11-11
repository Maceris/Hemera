package linear_algebra

import intrinsics from "base"
import math from "std"

/*
 * Rotations as unit quaternions (docs/types.md, Complex Numbers and Quaternions): q = w + xi + yj + zk, its Hamilton
 * product composing rotations, q1 * q2 rotating by q2 then q1. T is the parts' type, f32 or f64, and Q the quaternion
 * of them, each worked out from the other.
 */

/**
 * Give the quaternion type whose parts are a float type.
 *
 * @param T f16, f32 or f64.
 * @return q64, q128 or q256; q256 for anything else.
 */
quaternion_of :: fn(T: type) -> type {
    if T == f16 {
        return q64
    }
    if T == f32 {
        return q128
    }
    return q256
}

/**
 * Give the float type a quaternion's parts are.
 *
 * @param Q q64, q128 or q256.
 * @return f16, f32 or f64; f64 for anything else.
 */
part_of :: fn(Q: type) -> type {
    if Q == q64 {
        return f16
    }
    if Q == q128 {
        return f32
    }
    return f64
}

/**
 * The rotation by an angle about an axis, counterclockwise looking from the axis's tip toward the origin.
 *
 * @tparam T The parts' type, f32 or f64.
 * @tparam Q The quaternion type, of T.
 * @param axis The axis, of any length but 0: it's normalized.
 * @param angle The angle, in radians.
 * @return The unit quaternion cos(angle/2) + sin(angle/2) (xi + yj + zk), for the normalized axis.
 */
from_axis_angle :: fn[T, Q = quaternion_of(T)](axis: T[3], angle: T) -> Q {
    unit :: normalize(axis)
    s, c :: math.sin_cos(angle / 2)
    q : Q
    q.x = unit[0] * s
    q.y = unit[1] * s
    q.z = unit[2] * s
    q.w = c
    return q
}

/**
 * Rotate a vector by a unit quaternion: q v q*, worked out without the products.
 *
 * @tparam Q The quaternion type.
 * @tparam T Its parts' type.
 * @param q The rotation, of length 1.
 * @param v The vector.
 * @return v rotated.
 */
rotate :: fn[Q, T = part_of(Q)](q: Q, v: T[3]) -> T[3] {
    // v + 2w (u × v) + 2u × (u × v), for u the vector part
    u :: T.[q.x, q.y, q.z]
    t :: cross(u, v) * 2
    return v + t * q.w + cross(u, t)
}

/**
 * Give a quaternion's dot product with another, as vectors of four.
 *
 * @tparam Q The quaternion type.
 * @tparam T Its parts' type.
 * @param a One.
 * @param b The other.
 * @return a.x b.x + a.y b.y + a.z b.z + a.w b.w.
 */
quaternion_dot :: fn[Q, T = part_of(Q)](a: Q, b: Q) -> T {
    return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
}

/**
 * Scale a quaternion to length 1.
 *
 * @tparam Q The quaternion type.
 * @param q The quaternion.
 * @return q / |q|; q itself for 0.
 */
quaternion_normalize :: fn[Q](q: Q) -> Q {
    size :: abs(q)
    if size == 0 {
        return q
    }
    result := q
    result.x /= size
    result.y /= size
    result.z /= size
    result.w /= size
    return result
}

/**
 * Interpolate between two rotations along the shorter arc, at a constant angular speed.
 *
 * @tparam Q The quaternion type.
 * @tparam T Its parts' type.
 * @param a Where it starts, at 0; of length 1.
 * @param b Where it ends, at 1; of length 1.
 * @param t How far, from 0 to 1.
 * @return The rotation between, of length 1: a at 0, b or -b (the same rotation) at 1. Nearly parallel ones are
 *     interpolated linearly and normalized, where the arc's formula would divide by nearly 0.
 */
slerp :: fn[Q, T = part_of(Q)](a: Q, b: Q, t: T) -> Q {
    toward := b
    cosine := quaternion_dot(a, toward)
    // The shorter way round: q and -q are the same rotation
    if cosine < 0 {
        toward = -toward
        cosine = -cosine
    }
    from := 1 - t
    to := t
    if cosine < 0.9995 {
        angle :: math.acos(cosine)
        sine :: math.sin(angle)
        from = math.sin((1 - t) * angle) / sine
        to = math.sin(t * angle) / sine
    }
    result : Q
    result.x = a.x * from + toward.x * to
    result.y = a.y * from + toward.y * to
    result.z = a.z * from + toward.z * to
    result.w = a.w * from + toward.w * to
    return if cosine < 0.9995 { result } else { quaternion_normalize(result) }
}

/**
 * The rotation matrix of a unit quaternion.
 *
 * @tparam Q The quaternion type.
 * @tparam T Its parts' type.
 * @param q The rotation, of length 1.
 * @return The 3 × 3 matrix that rotates a column as q does: to_matrix(q) * v is rotate(q, v).
 */
to_matrix :: fn[Q, T = part_of(Q)](q: Q) -> matrix[T, 3, 3] {
    x :: q.x
    y :: q.y
    z :: q.z
    w :: q.w
    return matrix[T, 3, 3].{
        1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y),
        2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x),
        2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y),
    }
}

/**
 * The unit quaternion of a rotation matrix, by Shepperd's method: from the diagonal's largest, so nothing's divided by
 * nearly 0.
 *
 * @tparam T The elements' type, f32 or f64.
 * @tparam Q The quaternion type, of T.
 * @param m A rotation: orthonormal, with determinant 1.
 * @return The quaternion with w at least 0 whose to_matrix is m.
 */
from_matrix :: fn[T, Q = quaternion_of(T)](m: matrix[T, 3, 3]) -> Q {
    trace :: m[0, 0] + m[1, 1] + m[2, 2]
    q : Q
    if trace > 0 {
        s :: intrinsics.square_root(trace + 1) * 2
        q.w = s / 4
        q.x = (m[2, 1] - m[1, 2]) / s
        q.y = (m[0, 2] - m[2, 0]) / s
        q.z = (m[1, 0] - m[0, 1]) / s
    }
    else if m[0, 0] > m[1, 1] && m[0, 0] > m[2, 2] {
        s :: intrinsics.square_root(1 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q.w = (m[2, 1] - m[1, 2]) / s
        q.x = s / 4
        q.y = (m[0, 1] + m[1, 0]) / s
        q.z = (m[0, 2] + m[2, 0]) / s
    }
    else if m[1, 1] > m[2, 2] {
        s :: intrinsics.square_root(1 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q.w = (m[0, 2] - m[2, 0]) / s
        q.x = (m[0, 1] + m[1, 0]) / s
        q.y = s / 4
        q.z = (m[1, 2] + m[2, 1]) / s
    }
    else {
        s :: intrinsics.square_root(1 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q.w = (m[1, 0] - m[0, 1]) / s
        q.x = (m[0, 2] + m[2, 0]) / s
        q.y = (m[1, 2] + m[2, 1]) / s
        q.z = s / 4
    }
    if q.w < 0 {
        return -q
    }
    return q
}

/**
 * The rotation of Euler angles, as cameras and vehicles are turned: roll about z, then pitch about x, then yaw about y,
 * each about the world's axis, so yaw × pitch × roll.
 *
 * @tparam T The angles' type, f32 or f64.
 * @tparam Q The quaternion type, of T.
 * @param pitch The angle about x, in radians: positive tips +y toward +z.
 * @param yaw The angle about y, in radians: positive turns +z toward +x.
 * @param roll The angle about z, in radians: positive turns +x toward +y.
 * @return The unit quaternion of the three rotations.
 */
from_euler :: fn[T, Q = quaternion_of(T)](pitch: T, yaw: T, roll: T) -> Q {
    about_x :: from_axis_angle(T.[1, 0, 0], pitch)
    about_y :: from_axis_angle(T.[0, 1, 0], yaw)
    about_z :: from_axis_angle(T.[0, 0, 1], roll)
    return about_y * about_x * about_z
}
