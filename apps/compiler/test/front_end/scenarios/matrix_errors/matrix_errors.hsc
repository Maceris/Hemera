package matrix_errors

/*
 * What matrices refuse (docs/types.md, Matrices): each line below is one error.
 */

Big :: matrix[f32, 5, 4]
Text :: matrix[string, 2, 2]

main :: fn(unknown: usize) {
    square := matrix[f32, 2, 2].{1, 2, 3, 4}
    wide :: matrix[f32, 2, 3].{1, 2, 3, 4, 5, 6}
    _ = matrix[f32, 2, 2].{1, 2, 3}
    _ = square[0]
    _ = wide * wide
    _ = wide * f32.[1, 2]
    _ = square + 1
    _ = transpose(3)
    _ = identity(f32)
    _ = square < square
    square *= wide
}
