/*
 * Complex numbers and quaternions (docs/types.md, Complex Numbers and Quaternions): floats in parts, written with
 * imaginary literals, with their arithmetic, equality, Odin's real, imag, jmag, kmag, conj and abs, a quaternion's x, y,
 * z, w and xyz, mixing with real numbers, and casts between sizes.
 */
package composites

import testing from "std"

I :: 1i
HALF :: 0.5 + 1.5i

takes_complex_numbers_apart #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a : c64 = 1 + 2i
    b : c64 = 3 - 4i
    testing.expect_eq(t, real(a), 1, "1 + 2i's real part")
    testing.expect_eq(t, imag(a), 2, "1 + 2i's imaginary part")
    testing.expect_eq(t, imag(b), -4, "3 - 4i's imaginary part keeps its sign")
    // An untyped one's parts, as the type it defaults to
    testing.expect(t, I * I == -1, "i squared is -1")
    testing.expect_eq(t, imag(HALF), 1.5, "an untyped constant's imaginary part")
    testing.expect_eq(t, real(HALF), 0.5, "an untyped constant's real part")
    return .Ok
}

does_complex_arithmetic #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a : c64 = 1 + 2i
    b : c64 = 3 - 4i
    sum := a + b
    testing.expect_eq(t, real(sum), 4, "real parts add")
    testing.expect_eq(t, imag(sum), -2, "imaginary parts add")
    // (1 + 2i)(3 - 4i) = 3 - 4i + 6i + 8 = 11 + 2i
    product := a * b
    testing.expect(t, product == 11 + 2i, "i times -4i is +4, so the product is 11 + 2i")
    testing.expect(t, product != 11 - 2i, "equality looks at the imaginary part too")
    testing.expect(t, product / b == a, "dividing undoes multiplying, exactly for these small integers")
    testing.expect(t, -a == -1 - 2i, "negating negates both parts")
    return .Ok
}

mixes_with_real_numbers #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    a : c64 = 1 + 2i
    // Mixing with a real number of the parts' type, and untyped ones
    scale : f32 = 2
    testing.expect(t, a * scale == 2 + 4i, "a real number scales both parts")
    testing.expect(t, scale + a == 3 + 2i, "a real number adds to the real part only")
    testing.expect(t, a * 3 == 3 + 6i, "an untyped real number scales both parts")
    return .Ok
}

converts_between_sizes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Made from parts, by arithmetic
    re : f64 = 0.25
    im : f64 = -8
    c : c128 = re + im * 1i
    testing.expect(t, c == 0.25 - 8i, "a real plus a real times i has those parts")
    // To another size, part by part, and a real number as one
    narrowed := cast[c32](c)
    testing.expect_eq(t, real(narrowed), 0.25, "0.25 fits a half-size float exactly")
    testing.expect_eq(t, imag(narrowed), -8, "-8 fits a half-size float exactly")
    scale : f32 = 2
    testing.expect(t, cast[c64](scale) == 2, "a real number cast to complex has no imaginary part")
    // An untyped one where nothing else decides is a c128
    defaulted := 2 + 3i
    testing.expect(t, type_of(defaulted) == c128, "an untyped complex number defaults to c128")
    testing.expect_eq(t, size_of(c32), 4, "two 16-bit parts")
    testing.expect_eq(t, size_of(q256), 32, "four 64-bit parts")
    return .Ok
}

multiplies_quaternions_as_hamilton_did #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Quaternions: x, y, z, then w, and the Hamilton product: ij = k, jk = i, ki = j, ijk = -1
    i : q128 = 1i
    j : q128 = 1j
    k : q128 = 1k
    testing.expect(t, i * j == k, "ij = k")
    testing.expect(t, j * k == i, "jk = i")
    testing.expect(t, k * i == j, "ki = j")
    testing.expect(t, i * j * k == -1, "ijk = -1")
    testing.expect(t, j * i == -k, "the product doesn't commute: ji = -k")
    return .Ok
}

reaches_a_quaternions_parts #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    q : q128 = 1 + 2i + 3j + 4k
    testing.expect_eq(t, real(q), 1, "the real part")
    testing.expect_eq(t, imag(q), 2, "the i part")
    testing.expect_eq(t, jmag(q), 3, "the j part")
    testing.expect_eq(t, kmag(q), 4, "the k part")
    testing.expect_eq(t, q.w, 1, "w is the real part")
    testing.expect_eq(t, q.x, 2, "x is the i part")
    testing.expect_eq(t, q.y, 3, "y is the j part")
    testing.expect_eq(t, q.z, 4, "z is the k part")
    testing.expect(t, (q * q) / q == q, "dividing undoes multiplying, exactly for these small integers")
    testing.expect(t, q - q == 0, "a quaternion less itself is zero")
    testing.expect(t, q * 2 == 2 + 4i + 6j + 8k, "a real number scales every part")
    // Fields can be set, and xyz is the vector part
    q.w = 5
    q.x = -1
    testing.expect(t, q == 5 - 1i + 3j + 4k, "setting w and x changes the real and i parts")
    vector := q.xyz
    testing.require_eq(t, vector.count, 3, "the vector part has three parts")?
    testing.expect_eq(t, vector[0], -1, "xyz starts with x")
    testing.expect_eq(t, vector[1], 3, "then y")
    testing.expect_eq(t, vector[2], 4, "then z")
    q.xyz[2] = 7
    testing.expect_eq(t, kmag(q), 7, "setting xyz's third part sets the k part")
    return .Ok
}

works_out_conjugates_and_magnitudes #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // conj and abs: |3 + 4i| is 5, and |1 + 2i + 3j + 4k| the square root of 30; abs of a real number too
    a : c64 = 1 + 2i
    testing.expect(t, conj(a) == 1 - 2i, "a complex number's conjugate negates its imaginary part")
    testing.expect(t, conj(1 + 2i + 3j + 4k) == 1 - 2i - 3j - 4k, "a quaternion's conjugate negates its vector part")
    three_four : c64 = 3 + 4i
    testing.expect_eq(t, abs(three_four), 5, "3, 4, 5 is a right triangle")
    testing.expect_eq(t, abs(cast[c32](three_four)), 5, "and at half the size")
    p : q256 = 1 + 2i + 3j + 4k
    testing.expect(t, abs(p) * abs(p) > 29.99 && abs(p) * abs(p) < 30.01, "the square of the magnitude is 1 + 4 + 9 + 16")
    negative : i32 = -7
    testing.expect_eq(t, abs(negative), 7, "abs of a negative integer")
    testing.expect_eq(t, abs(-2.5), 2.5, "abs of a negative untyped float")
    scale : f32 = 2
    testing.expect_eq(t, abs(scale), 2, "abs of a positive float is itself")
    return .Ok
}
