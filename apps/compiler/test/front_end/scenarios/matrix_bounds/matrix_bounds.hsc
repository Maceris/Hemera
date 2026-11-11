package matrix_bounds

/*
 * A matrix's indexes are proven in bounds as an array's are (docs/types.md, Matrices): each line below is one error.
 */

main :: fn(unknown: usize) {
    square := matrix[f32, 2, 2].{1, 2, 3, 4}
    _ = square[2, 0]
    _ = square[0, unknown]
    if unknown < 2 {
        _ = square[unknown, 1]
    }
}
