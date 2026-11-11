package array_arithmetic_errors

/*
 * What arrays as vectors refuse (docs/types.md, Arrays as Vectors): each line below is one error.
 */

Point3 :: distinct alias f32[3]

main :: fn() {
    v := f32.[1, 2, 3, 4]
    three :: f32.[1, 2, 3]
    wide :: f64.[1, 2, 3]
    p :: cast[Point3](three)
    _ = v.xg
    _ = three.w
    _ = v.xyzwx
    v.xx = 1, 2
    _ = &v.xy
    _ = p + three
    _ = three + wide
    _ = three % 2
    _ = three + "two"
    _ = three < three
    w := three
    w += wide
    _ = w
}
