package linear_algebra_test

import linear_algebra from "std"
import math from "std"
import testing from "std"

/*
 * std/linear_algebra: vectors' functions, quaternions against the matrices they make, determinants and inverses, and
 * the transforms against where they should put points.
 */

/** Whether two arrays are within tolerance of each other, element by element. */
near :: fn[n: usize](a: f32[n], b: f32[n], tolerance: f32 = 1e-5) -> bool {
    for i in 0..<n {
        if abs(a[i] - b[i]) > tolerance {
            return false
        }
    }
    return true
}

/** Whether two matrices are within tolerance of each other, element by element. */
near_matrix :: fn[rows: usize, columns: usize](a: matrix[f32, rows, columns], b: matrix[f32, rows, columns], tolerance: f32 = 1e-5) -> bool {
    for r in 0..<rows {
        for c in 0..<columns {
            if abs(a[r, c] - b[r, c]) > tolerance {
                return false
            }
        }
    }
    return true
}

/** A point through a 4 × 4 transform, divided by w. */
transformed :: fn(m: matrix[f32, 4, 4], point: f32[3]) -> f32[3] {
    clip :: m * f32.[point[0], point[1], point[2], 1]
    return f32.[clip[0] / clip[3], clip[1] / clip[3], clip[2] / clip[3]]
}

works_on_vectors #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a :: f32.[1, 2, 3]
    b :: f32.[4, 5, 6]
    testing.expect_eq(t, linear_algebra.dot(a, b), 32.0, "dot")
    testing.expect(t, linear_algebra.cross(f32.[1, 0, 0], f32.[0, 1, 0]) == f32.[0, 0, 1], "x × y is z")
    testing.expect(t, linear_algebra.cross(a, b) == f32.[-3, 6, -3], "cross")
    testing.expect_eq(t, linear_algebra.length(f32.[3, 4]), 5.0, "length")
    testing.expect_eq(t, linear_algebra.length_squared(f32.[3, 4]), 25.0, "length_squared")
    testing.expect(t, linear_algebra.normalize(f32.[0, 3, 4]) == f32.[0, 0.6, 0.8], "normalize")
    testing.expect(t, linear_algebra.normalize(f32.[0, 0]) == f32.[0, 0], "a zero array stays")
    testing.expect_eq(t, linear_algebra.distance(f32.[1, 1], f32.[4, 5]), 5.0, "distance")
    testing.expect(t, linear_algebra.lerp(a, b, 0) == a && linear_algebra.lerp(a, b, 1) == b, "lerp's ends exactly")
    testing.expect(t, linear_algebra.lerp(a, b, 0.5) == f32.[2.5, 3.5, 4.5], "and between")
    testing.expect(t, linear_algebra.minimum(f32.[1, 5], f32.[3, 2]) == f32.[1, 2], "minimum")
    testing.expect(t, linear_algebra.maximum(f32.[1, 5], f32.[3, 2]) == f32.[3, 5], "maximum")
    testing.expect(t, linear_algebra.clamp(f32.[-1, 0.5, 9], f32.[0, 0, 0], f32.[1, 1, 1]) == f32.[0, 0.5, 1], "clamp")
    testing.expect(t, linear_algebra.absolute(i32.[-3, 4]) == i32.[3, 4], "absolute")
    testing.expect_eq(t, linear_algebra.dot(f64.[1, 2, 3, 4, 5], f64.[1, 1, 1, 1, 1]), 15.0, "any length")
    return .Ok
}

reflects_and_refracts #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    up :: f32.[0, 1, 0]
    testing.expect(t, linear_algebra.reflect(f32.[1, -1, 0], up) == f32.[1, 1, 0], "reflect")
    straight :: linear_algebra.refract(f32.[0, -1, 0], up, 1.0 / 1.5)
    testing.expect(t, near(straight, f32.[0, -1, 0]), "straight through")
    slanted :: linear_algebra.normalize(f32.[1, -1, 0])
    bent :: linear_algebra.refract(slanted, up, 1.0 / 1.5)
    // Snell: sin of the angle out is sin in over 1.5
    testing.expect(t, abs(bent[0] - slanted[0] / 1.5) < 1e-6, "bent toward the normal")
    testing.expect(t, linear_algebra.refract(slanted, up, 1.5) == f32.[0, 0, 0], "total internal reflection")
    testing.expect(t, linear_algebra.face_forward(up, f32.[0, -1, 0], up) == up, "facing")
    testing.expect(t, linear_algebra.face_forward(up, f32.[0, 1, 0], up) == f32.[-0.0, -1, -0.0], "turned")
    testing.expect(t, linear_algebra.map(f32.[0, 8], math.cube_root[f32]) == f32.[0, 2], "map")
    return .Ok
}

rotates_with_quaternions #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    quarter :: linear_algebra.from_axis_angle(f32.[0, 0, 2], cast[f32](math.PI / 2))
    testing.expect(t, near(linear_algebra.rotate(quarter, f32.[1, 0, 0]), f32.[0, 1, 0]), "a quarter turn about z takes x to y")
    m :: linear_algebra.to_matrix(quarter)
    testing.expect(t, near(m * f32.[0, 3, 1], linear_algebra.rotate(quarter, f32.[0, 3, 1])), "its matrix rotates the same")
    back :: linear_algebra.from_matrix(m)
    testing.expect(t, abs(back.x - quarter.x) + abs(back.y - quarter.y) + abs(back.z - quarter.z) + abs(back.w - quarter.w) < 1e-6,
        "and gives it back")
    none :: linear_algebra.from_axis_angle(f32.[0, 0, 1], 0)
    eighth :: linear_algebra.from_axis_angle(f32.[0, 0, 1], cast[f32](math.PI / 4))
    halfway :: linear_algebra.slerp(none, quarter, 0.5)
    testing.expect(t, near(linear_algebra.rotate(halfway, f32.[1, 0, 0]), linear_algebra.rotate(eighth, f32.[1, 0, 0])), "slerp")
    yawed :: linear_algebra.from_euler(cast[f32](0), cast[f32](math.PI / 2), cast[f32](0))
    testing.expect(t, near(linear_algebra.rotate(yawed, f32.[0, 0, 1]), f32.[1, 0, 0]), "yaw turns z toward x")
    both :: linear_algebra.from_euler(cast[f32](0.3), cast[f32](0.5), cast[f32](0.7))
    expected :: linear_algebra.rotate(linear_algebra.from_axis_angle(f32.[0, 1, 0], 0.5),
        linear_algebra.rotate(linear_algebra.from_axis_angle(f32.[1, 0, 0], 0.3),
        linear_algebra.rotate(linear_algebra.from_axis_angle(f32.[0, 0, 1], 0.7), f32.[1, 2, 3])))
    testing.expect(t, near(linear_algebra.rotate(both, f32.[1, 2, 3]), expected), "roll, then pitch, then yaw")
    wide :: linear_algebra.from_axis_angle(f64.[1, 1, 0], 1.25)
    testing.expect(t, abs(abs(wide) - 1) < 1e-15, "q256 from f64")
    return .Ok
}

keeps_lengths_when_rotating #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    axis :: f64.[cast[f64](testing.draw_between(source, -100, 100)), cast[f64](testing.draw_between(source, -100, 100)), 1]
    angle :: cast[f64](testing.draw_between(source, -1000, 1000)) / 100
    v :: f64.[cast[f64](testing.draw_between(source, -50, 50)), 2, cast[f64](testing.draw_between(source, -50, 50))]
    q :: linear_algebra.from_axis_angle(axis, angle)
    turned :: linear_algebra.rotate(q, v)
    testing.expect(t, abs(linear_algebra.length(turned) - linear_algebra.length(v)) < 1e-9, "a rotation keeps lengths")
    testing.expect(t, abs(linear_algebra.dot(turned, axis) - linear_algebra.dot(v, axis)) < 1e-9, "and what's along the axis")
    return .Ok
}

solves_matrices #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    two :: matrix[f32, 2, 2].{
        4, 7,
        2, 6,
    }
    testing.expect_eq(t, linear_algebra.determinant(two), 10.0, "2 × 2")
    three :: matrix[f64, 3, 3].{
        2, -3, 1,
        2, 0, -1,
        1, 4, 5,
    }
    testing.expect(t, abs(linear_algebra.determinant(three) - 49) < 1e-12, "3 × 3")
    singular :: matrix[f32, 3, 3].{1, 2, 3, 2, 4, 6, 0, 1, 1}
    testing.expect_eq(t, linear_algebra.determinant(singular), 0.0, "singular")
    testing.expect(t, linear_algebra.inverse(singular) is_none, "has no inverse")
    inverse :: linear_algebra.inverse(two) or_else identity(matrix[f32, 2, 2])
    testing.expect(t, near_matrix(inverse, matrix[f32, 2, 2].{0.6, -0.7, -0.2, 0.4}), "2 × 2's inverse")
    m :: linear_algebra.translation(f32.[1, 2, 3]) * linear_algebra.rotation(f32.[1, 1, 0], 0.8) * linear_algebra.scaling(f32.[2, 3, 4])
    undone :: linear_algebra.inverse(m) or_else identity(matrix[f32, 4, 4])
    testing.expect(t, near_matrix(undone * m, identity(matrix[f32, 4, 4])), "a transform's inverse undoes it")
    testing.expect(t, linear_algebra.outer_product(f32.[1, 2], f32.[3, 4, 5]) == matrix[f32, 2, 3].{3, 4, 5, 6, 8, 10}, "outer product")
    return .Ok
}

transforms_points #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, transformed(linear_algebra.translation(f32.[1, 2, 3]), f32.[1, 1, 1]) == f32.[2, 3, 4], "translation")
    testing.expect(t, transformed(linear_algebra.scaling(f32.[2, 3, 4]), f32.[1, 1, 1]) == f32.[2, 3, 4], "scaling")
    turned :: transformed(linear_algebra.rotation(f32.[0, 0, 1], cast[f32](math.PI / 2)), f32.[1, 0, 0])
    testing.expect(t, near(turned, f32.[0, 1, 0]), "rotation about z")
    view :: linear_algebra.look_at(f32.[0, 0, 5], f32.[0, 0, 0], f32.[0, 1, 0])
    testing.expect(t, near(transformed(view, f32.[0, 0, 5]), f32.[0, 0, 0]), "the eye to the origin")
    testing.expect(t, near(transformed(view, f32.[0, 0, 0]), f32.[0, 0, -5]), "the target down -z")
    testing.expect(t, near(transformed(view, f32.[0, 1, 0]), f32.[0, 1, -5]), "up stays up")
    projection :: linear_algebra.perspective(cast[f32](math.PI / 2), 2, 1, 10)
    near_point :: transformed(projection, f32.[0, 0, -1])
    far_point :: transformed(projection, f32.[0, 0, -10])
    testing.expect(t, near(near_point, f32.[0, 0, 0]) && near(far_point, f32.[0, 0, 1]), "Vulkan's depth, 0 to 1")
    testing.expect(t, near(transformed(projection, f32.[2, 1, -1]), f32.[1, -1, 0]), "the corner, y down")
    gl :: linear_algebra.perspective_opengl(cast[f32](math.PI / 2), 2, 1, 10)
    testing.expect(t, near(transformed(gl, f32.[0, 0, -1]), f32.[0, 0, -1]) && near(transformed(gl, f32.[0, 0, -10]), f32.[0, 0, 1]),
        "OpenGL's depth, -1 to 1")
    testing.expect(t, near(transformed(gl, f32.[2, 1, -1]), f32.[1, 1, -1]), "y up")
    box :: linear_algebra.orthographic(cast[f32](-2), 2, -1, 1, 0, 10)
    testing.expect(t, near(transformed(box, f32.[2, 1, 0]), f32.[1, -1, 0]) && near(transformed(box, f32.[-2, -1, -10]), f32.[-1, 1, 1]),
        "orthographic, Vulkan's")
    gl_box :: linear_algebra.orthographic_opengl(cast[f32](-2), 2, -1, 1, 0, 10)
    testing.expect(t, near(transformed(gl_box, f32.[2, 1, 0]), f32.[1, 1, -1]) && near(transformed(gl_box, f32.[-2, -1, -10]), f32.[-1, -1, 1]),
        "orthographic, OpenGL's")
    return .Ok
}
