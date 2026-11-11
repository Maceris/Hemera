package array_arithmetic

import testing from "std"

/*
 * Fixed arrays as vectors (docs/types.md, Arrays as Vectors): + - * / % element by element, with a number for every
 * element, and swizzles, read and assigned through.
 */

Point3 :: distinct alias f32[3]

/**
 * Give two numbers, for assigning a swizzle from a call.
 *
 * @return 7 and 8.
 */
two :: fn() -> (f32, f32) {
    return 7, 8
}

works_element_by_element #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a := f32.[1, 2, 3]
    b := f32.[10, 20, 30]
    testing.expect(t, a + b == f32.[11, 22, 33], "a + b")
    testing.expect(t, b - a == f32.[9, 18, 27], "b - a")
    testing.expect(t, a * b == f32.[10, 40, 90], "a * b")
    testing.expect(t, b / a == f32.[10, 10, 10], "b / a")
    testing.expect(t, a * 2 == f32.[2, 4, 6], "a number with every element")
    testing.expect(t, 2 * a == f32.[2, 4, 6], "on either side")
    testing.expect(t, 1 - a == f32.[0, -1, -2], "and subtracting from it")
    testing.expect(t, -a == f32.[-1, -2, -3], "negated")
    position := f32.[1, 2, 3]
    velocity :: f32.[0.5, 0, -1]
    position += velocity * 2
    testing.expect(t, position == f32.[2, 2, 1], "+= an array")
    position *= 3
    testing.expect(t, position == f32.[6, 6, 3], "*= a number")
    return .Ok
}

works_on_integers_and_other_numbers #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a := i32.[7, -7, 9, 10]
    testing.expect(t, a % 4 == i32.[3, -3, 1, 2], "% truncated")
    testing.expect(t, a %% 4 == i32.[3, 1, 1, 2], "%% floored")
    testing.expect(t, a / 2 == i32.[3, -3, 4, 5], "/ truncated")
    a -= 1
    testing.expect(t, a == i32.[6, -8, 8, 9], "-= a number")
    z :: c64.[1 + 2i, 3 - 1i]
    testing.expect(t, z * 2i == c64.[-4 + 2i, 2 + 6i], "complex numbers")
    return .Ok
}

works_at_any_length #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    long : f64[40]
    for &x, i in long {
        x^ = cast[f64](i)
    }
    doubled :: long + long
    for x, i in doubled {
        testing.expect_eq(t, x, cast[f64](2 * i), "element % of 40")
    }
    long *= 0.5
    testing.expect_eq(t, long[39], 19.5, "*= on a long one")
    one : f32[1] = f32.[4]
    testing.expect(t, one * one == f32.[16], "one element")
    return .Ok
}

keeps_distinct_aliases_apart #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    p :: cast[Point3](f32.[1, 2, 3])
    q :: p + p
    testing.expect(t, q == cast[Point3](f32.[2, 4, 6]), "a distinct alias with its own kind")
    return .Ok
}

reads_swizzles #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    v :: f32.[1, 2, 3, 4]
    testing.expect_eq(t, v.x, 1.0, "x")
    testing.expect_eq(t, v.w, 4.0, "w")
    testing.expect(t, v.zyx == f32.[3, 2, 1], "zyx")
    testing.expect(t, v.xxy == f32.[1, 1, 2], "a letter repeated")
    testing.expect(t, v.rgb == f32.[1, 2, 3], "rgb")
    testing.expect(t, v.a == 4, "a")
    colour :: f32.[0.25, 0.5, 0.75]
    testing.expect(t, colour.bgr * 4 == f32.[3, 2, 1], "with arithmetic")
    q :: 1 + 2i + 3j + 4k
    testing.expect(t, q.xyz * 2 == f64.[4, 6, 8], "a quaternion's xyz")
    return .Ok
}

assigns_through_swizzles #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    v : f32[4]
    v.y = 10
    testing.expect(t, v == f32.[0, 10, 0, 0], "one letter")
    v.xy = f32.[1, 2]
    testing.expect(t, v == f32.[1, 2, 0, 0], "an array, element by element")
    v.zw = 3, 4
    testing.expect(t, v == f32.[1, 2, 3, 4], "values, one each")
    v.xz = two()
    testing.expect(t, v == f32.[7, 2, 8, 4], "a call's results")
    v.xy = v.yx
    testing.expect(t, v == f32.[2, 7, 8, 4], "swapped, the right read first")
    v.yz = v.xy
    testing.expect(t, v == f32.[2, 2, 7, 4], "overlapping")
    v.xy += 1, 2
    testing.expect(t, v == f32.[3, 4, 7, 4], "+=")
    v.wx = 5
    testing.expect(t, v == f32.[5, 4, 7, 5], "one number for every element")
    v.rgb *= 2
    testing.expect(t, v == f32.[10, 8, 14, 5], "*= a number")
    return .Ok
}
