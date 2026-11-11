package matrices

import testing from "std"

/*
 * Matrices (docs/types.md, Matrices): literals written row by row and stored column by column, m[row, column], the
 * products, element-wise + and -, transpose and identity, and casts to and from the array of their elements.
 */

Transform :: matrix[f32, 4, 4]

/** A translation, written as on paper. */
moved_by :: fn(x: f32, y: f32, z: f32) -> Transform {
    return Transform.{
        1, 0, 0, x,
        0, 1, 0, y,
        0, 0, 1, z,
        0, 0, 0, 1,
    }
}

stores_column_by_column #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    m :: matrix[f32, 2, 3].{
        1, 2, 3,
        4, 5, 6,
    }
    testing.expect_eq(t, m[0, 2], 3.0, "row 0, column 2")
    testing.expect_eq(t, m[1, 0], 4.0, "row 1, column 0")
    stored :: cast[f32[6]](m)
    testing.expect(t, stored == f32.[1, 4, 2, 5, 3, 6], "column by column")
    back :: cast[matrix[f32, 2, 3]](stored)
    testing.expect(t, back == m, "and back")
    testing.expect_eq(t, size_of(Transform), 64, "16 floats")
    return .Ok
}

sets_elements #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    m : matrix[i32, 2, 2]
    m[0, 1] = 5
    m[1, 0] = -3
    testing.expect(t, m == matrix[i32, 2, 2].{0, 5, -3, 0}, "by row and column")
    for row in 0..<2 {
        for column in 0..<2 {
            m[row, column] += 1
        }
    }
    testing.expect(t, m == matrix[i32, 2, 2].{1, 6, -2, 1}, "in a loop, proven in bounds")
    return .Ok
}

multiplies #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a :: matrix[f32, 2, 3].{
        1, 2, 3,
        4, 5, 6,
    }
    b :: matrix[f32, 3, 2].{
        7, 8,
        9, 10,
        11, 12,
    }
    testing.expect(t, a * b == matrix[f32, 2, 2].{58, 64, 139, 154}, "the matrix product")
    testing.expect(t, b * a == matrix[f32, 3, 3].{39, 54, 69, 49, 68, 87, 59, 82, 105}, "the other way")
    testing.expect(t, a * f32.[1, 0, -1] == f32.[-2, -2], "a column")
    testing.expect(t, f32.[1, -1] * a == f32.[-3, -3, -3], "a row")
    testing.expect(t, a * 2 == matrix[f32, 2, 3].{2, 4, 6, 8, 10, 12}, "a number")
    testing.expect(t, 2 * a == a + a, "on either side, and +")
    testing.expect(t, a - a == matrix[f32, 2, 3].{}, "-")
    testing.expect(t, -a == a * -1, "negated")
    moved :: moved_by(1, 2, 3) * f32.[10, 20, 30, 1]
    testing.expect(t, moved == f32.[11, 22, 33, 1], "a point moved")
    both :: moved_by(1, 0, 0) * moved_by(0, 5, 0)
    testing.expect(t, both == moved_by(1, 5, 0), "two translations, and an alias's product is the alias")
    return .Ok
}

transposes_and_knows_identity #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a :: matrix[f32, 2, 3].{
        1, 2, 3,
        4, 5, 6,
    }
    testing.expect(t, transpose(a) == matrix[f32, 3, 2].{1, 4, 2, 5, 3, 6}, "transpose")
    testing.expect(t, transpose(transpose(a)) == a, "twice")
    one :: identity(Transform)
    testing.expect(t, one * moved_by(1, 2, 3) == moved_by(1, 2, 3), "identity")
    testing.expect(t, identity(matrix[i32, 2, 3]) == matrix[i32, 2, 3].{1, 0, 0, 0, 1, 0}, "not square")
    return .Ok
}

assigns_in_place #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    m := moved_by(1, 0, 0)
    m *= moved_by(0, 2, 0)
    testing.expect(t, m == moved_by(1, 2, 0), "*= a matrix, reading itself")
    m += identity(Transform)
    m -= identity(Transform)
    testing.expect(t, m == moved_by(1, 2, 0), "+= and -=")
    m *= 2
    testing.expect_eq(t, m[3, 3], 2.0, "*= a number")
    return .Ok
}

draws_matrices #test :: fn(t: ptr[mut testing.T], source: ptr[mut testing.Source]) -> testing.Outcome {
    m :: testing.draw[matrix[i32, 3, 3]](source)
    testing.expect(t, transpose(transpose(m)) == m, "transposed twice is itself")
    testing.expect(t, m * identity(matrix[i32, 3, 3]) == m, "times identity is itself")
    return .Ok
}
