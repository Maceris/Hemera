package linear_algebra

import math from "std"

/*
 * Matrices' numerics and the transforms (docs/types.md, Matrices). The transforms are 4 × 4, for points as columns
 * f32.[x, y, z, 1] multiplied on the right, in a right-handed world. The projections are Vulkan's: a camera looking
 * down -z, clip-space depth from 0 at the near plane to 1 at the far one, and y down; the _opengl ones OpenGL's, depth
 * from -1 to 1 and y up.
 */

/**
 * A square matrix's determinant, by elimination with partial pivoting.
 *
 * @tparam T The elements' type, f32 or f64.
 * @tparam n Its rows and columns.
 * @param m The matrix.
 * @return det(m): 0 for a singular matrix, up to rounding.
 */
determinant :: fn[T, n: usize](m: matrix[T, n, n]) -> T {
    a := m
    result : T = 1
    for column in 0..<n {
        // The largest below the diagonal, for the least rounding
        pivot := column
        for row in column + 1..<n {
            if abs(a[row, column]) > abs(a[pivot, column]) {
                pivot = row
            }
        }
        if a[pivot, column] == 0 {
            return 0
        }
        if pivot != column {
            for k in 0..<n {
                a[column, k], a[pivot, k] = a[pivot, k], a[column, k]
            }
            result = -result
        }
        result *= a[column, column]
        for row in column + 1..<n {
            factor :: a[row, column] / a[column, column]
            for k in column..<n {
                a[row, k] -= factor * a[column, k]
            }
        }
    }
    return result
}

/**
 * A square matrix's inverse, by Gauss-Jordan elimination with partial pivoting.
 *
 * @tparam T The elements' type, f32 or f64.
 * @tparam n Its rows and columns.
 * @param m The matrix.
 * @return m⁻¹, with m × m⁻¹ the identity up to rounding; none if m is singular, a pivot exactly 0.
 */
inverse :: fn[T, n: usize](m: matrix[T, n, n]) -> matrix[T, n, n]? {
    a := m
    result := identity(matrix[T, n, n])
    for column in 0..<n {
        pivot := column
        for row in column + 1..<n {
            if abs(a[row, column]) > abs(a[pivot, column]) {
                pivot = row
            }
        }
        if a[pivot, column] == 0 {
            return null
        }
        if pivot != column {
            for k in 0..<n {
                a[column, k], a[pivot, k] = a[pivot, k], a[column, k]
                result[column, k], result[pivot, k] = result[pivot, k], result[column, k]
            }
        }
        // The pivot's row scaled to 1 there, then taken from every other row
        scale :: 1 / a[column, column]
        for k in 0..<n {
            a[column, k] *= scale
            result[column, k] *= scale
        }
        for row in 0..<n {
            if row == column {
                continue
            }
            factor :: a[row, column]
            for k in 0..<n {
                a[row, k] -= factor * a[column, k]
                result[row, k] -= factor * result[column, k]
            }
        }
    }
    return result
}

/**
 * The outer product of two arrays: a column times a row.
 *
 * @tparam T The elements' type, a number.
 * @tparam rows How many elements a has.
 * @tparam columns How many b has.
 * @param a The column.
 * @param b The row.
 * @return The rows × columns matrix whose (r, c) element is a[r] × b[c].
 */
outer_product :: fn[T, rows: usize, columns: usize](a: T[rows], b: T[columns]) -> matrix[T, rows, columns] {
    result : matrix[T, rows, columns]
    for r in 0..<rows {
        for c in 0..<columns {
            result[r, c] = a[r] * b[c]
        }
    }
    return result
}

/**
 * The transform that moves points by an offset.
 *
 * @tparam T The elements' type, f32 or f64.
 * @param offset How far along x, y and z.
 * @return The 4 × 4 matrix with offset in its last column.
 */
translation :: fn[T](offset: T[3]) -> matrix[T, 4, 4] {
    return matrix[T, 4, 4].{
        1, 0, 0, offset[0],
        0, 1, 0, offset[1],
        0, 0, 1, offset[2],
        0, 0, 0, 1,
    }
}

/**
 * The transform that scales along each axis, about the origin.
 *
 * @tparam T The elements' type, f32 or f64.
 * @param factors The scale along x, y and z.
 * @return The 4 × 4 matrix with factors on its diagonal.
 */
scaling :: fn[T](factors: T[3]) -> matrix[T, 4, 4] {
    return matrix[T, 4, 4].{
        factors[0], 0, 0, 0,
        0, factors[1], 0, 0,
        0, 0, factors[2], 0,
        0, 0, 0, 1,
    }
}

/**
 * The transform that rotates about an axis through the origin, counterclockwise looking from the axis's tip.
 *
 * @tparam T The elements' type, f32 or f64.
 * @param axis The axis, of any length but 0: it's normalized.
 * @param angle The angle, in radians.
 * @return The 4 × 4 matrix of the rotation, by Rodrigues' formula.
 */
rotation :: fn[T](axis: T[3], angle: T) -> matrix[T, 4, 4] {
    u :: normalize(axis)
    s, c :: math.sin_cos(angle)
    t :: 1 - c
    x :: u[0]
    y :: u[1]
    z :: u[2]
    return matrix[T, 4, 4].{
        t * x * x + c, t * x * y - s * z, t * x * z + s * y, 0,
        t * x * y + s * z, t * y * y + c, t * y * z - s * x, 0,
        t * x * z - s * y, t * y * z + s * x, t * z * z + c, 0,
        0, 0, 0, 1,
    }
}

/**
 * A camera's view transform: from the world to where the camera looks down -z, with +y up and +x right.
 *
 * @tparam T The elements' type, f32 or f64.
 * @param eye Where the camera is.
 * @param target What it looks at, not at eye.
 * @param up Which way is up in the world, not along the line of sight.
 * @return The 4 × 4 matrix moving eye to the origin and target onto -z, as GLM's lookAtRH.
 */
look_at :: fn[T](eye: T[3], target: T[3], up: T[3]) -> matrix[T, 4, 4] {
    forward :: normalize(target - eye)
    right :: normalize(cross(forward, up))
    camera_up :: cross(right, forward)
    return matrix[T, 4, 4].{
        right[0], right[1], right[2], -dot(right, eye),
        camera_up[0], camera_up[1], camera_up[2], -dot(camera_up, eye),
        -forward[0], -forward[1], -forward[2], dot(forward, eye),
        0, 0, 0, 1,
    }
}

/**
 * A perspective projection, as Vulkan takes it: view space looking down -z to clip space with depth from 0 at near to
 * 1 at far, and y down.
 *
 * @tparam T The elements' type, f32 or f64.
 * @param vertical_fov The field of view top to bottom, in radians, between 0 and π.
 * @param aspect Width over height.
 * @param near The near plane's distance, above 0.
 * @param far The far plane's distance, beyond near.
 * @return The 4 × 4 matrix; a point's depth is its clip z over its clip w.
 */
perspective :: fn[T](vertical_fov: T, aspect: T, near: T, far: T) -> matrix[T, 4, 4] {
    f :: 1 / math.tan(vertical_fov / 2)
    return matrix[T, 4, 4].{
        f / aspect, 0, 0, 0,
        0, -f, 0, 0,
        0, 0, far / (near - far), near * far / (near - far),
        0, 0, -1, 0,
    }
}

/**
 * An orthographic projection, as Vulkan takes it: the box between the planes to clip space, depth from 0 at near to 1
 * at far, and y down.
 *
 * @tparam T The elements' type, f32 or f64.
 * @param left The box's left, in view space.
 * @param right Its right, not left.
 * @param bottom Its bottom.
 * @param top Its top, not bottom.
 * @param near The near plane's distance down -z.
 * @param far The far plane's, not near.
 * @return The 4 × 4 matrix.
 */
orthographic :: fn[T](left: T, right: T, bottom: T, top: T, near: T, far: T) -> matrix[T, 4, 4] {
    return matrix[T, 4, 4].{
        2 / (right - left), 0, 0, -(right + left) / (right - left),
        0, -2 / (top - bottom), 0, (top + bottom) / (top - bottom),
        0, 0, -1 / (far - near), -near / (far - near),
        0, 0, 0, 1,
    }
}

/**
 * A perspective projection as OpenGL takes it: depth from -1 at near to 1 at far, and y up.
 *
 * @tparam T The elements' type, f32 or f64.
 * @param vertical_fov The field of view top to bottom, in radians, between 0 and π.
 * @param aspect Width over height.
 * @param near The near plane's distance, above 0.
 * @param far The far plane's distance, beyond near.
 * @return The 4 × 4 matrix, as gluPerspective's.
 */
perspective_opengl :: fn[T](vertical_fov: T, aspect: T, near: T, far: T) -> matrix[T, 4, 4] {
    f :: 1 / math.tan(vertical_fov / 2)
    return matrix[T, 4, 4].{
        f / aspect, 0, 0, 0,
        0, f, 0, 0,
        0, 0, (far + near) / (near - far), 2 * far * near / (near - far),
        0, 0, -1, 0,
    }
}

/**
 * An orthographic projection as OpenGL takes it: depth from -1 at near to 1 at far, and y up.
 *
 * @tparam T The elements' type, f32 or f64.
 * @param left The box's left, in view space.
 * @param right Its right, not left.
 * @param bottom Its bottom.
 * @param top Its top, not bottom.
 * @param near The near plane's distance down -z.
 * @param far The far plane's, not near.
 * @return The 4 × 4 matrix, as glOrtho's.
 */
orthographic_opengl :: fn[T](left: T, right: T, bottom: T, top: T, near: T, far: T) -> matrix[T, 4, 4] {
    return matrix[T, 4, 4].{
        2 / (right - left), 0, 0, -(right + left) / (right - left),
        0, 2 / (top - bottom), 0, -(top + bottom) / (top - bottom),
        0, 0, -2 / (far - near), -(far + near) / (far - near),
        0, 0, 0, 1,
    }
}
