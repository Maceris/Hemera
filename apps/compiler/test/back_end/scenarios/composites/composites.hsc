/*
 * Complex numbers and quaternions (docs/types.md, Complex Numbers and Quaternions): floats in parts, written with
 * imaginary literals, with their arithmetic, equality, Odin's real, imag, jmag, kmag, conj and abs, a quaternion's x, y,
 * z, w and xyz, mixing with real numbers, and casts between sizes. main returns 42 if they all held, or the number of
 * the first that didn't.
 */
package composites

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

I :: 1i
HALF :: 0.5 + 1.5i

main :: fn() -> int {
    errors := 0
    a : c64 = 1 + 2i
    b : c64 = 3 - 4i
    errors += check(real(a) == 1 && imag(a) == 2 && imag(b) == -4, 1)
    sum := a + b
    errors += check(real(sum) == 4 && imag(sum) == -2, 2)
    // (1 + 2i)(3 - 4i) = 3 - 4i + 6i + 8 = 11 + 2i
    product := a * b
    errors += check(product == 11 + 2i && product != 11 - 2i, 3)
    errors += check(product / b == a, 4)
    errors += check(-a == -1 - 2i, 5)
    // An untyped one's parts, as the type it defaults to
    errors += check(I * I == -1 && imag(HALF) == 1.5 && real(HALF) == 0.5, 6)

    // Mixing with a real number of the parts' type, and untyped ones
    scale : f32 = 2
    errors += check(a * scale == 2 + 4i && scale + a == 3 + 2i && a * 3 == 3 + 6i, 7)

    // Made from parts, by arithmetic
    re : f64 = 0.25
    im : f64 = -8
    c : c128 = re + im * 1i
    errors += check(c == 0.25 - 8i, 8)
    // To another size, part by part, and a real number as one
    narrowed := cast[c32](c)
    errors += check(real(narrowed) == 0.25 && imag(narrowed) == -8 && cast[c64](scale) == 2, 9)
    // An untyped one where nothing else decides is a c128
    defaulted := 2 + 3i
    errors += check(type_of(defaulted) == c128 && size_of(c32) == 4 && size_of(q256) == 32, 10)

    // Quaternions: x, y, z, then w, and the Hamilton product: ij = k, jk = i, ki = j, ijk = -1
    i : q128 = 1i
    j : q128 = 1j
    k : q128 = 1k
    errors += check(i * j == k && j * k == i && k * i == j && i * j * k == -1, 11)
    errors += check(j * i == -k, 12)
    q : q128 = 1 + 2i + 3j + 4k
    errors += check(real(q) == 1 && imag(q) == 2 && jmag(q) == 3 && kmag(q) == 4, 13)
    errors += check(q.w == 1 && q.x == 2 && q.y == 3 && q.z == 4, 14)
    errors += check((q * q) / q == q, 15)
    errors += check(q - q == 0 && q * 2 == 2 + 4i + 6j + 8k, 16)

    // Fields can be set, and xyz is the vector part
    q.w = 5
    q.x = -1
    errors += check(q == 5 - 1i + 3j + 4k, 17)
    vector := q.xyz
    errors += check(vector.count == 3 && vector[0] == -1 && vector[1] == 3 && vector[2] == 4, 18)
    q.xyz[2] = 7
    errors += check(kmag(q) == 7, 19)

    // conj and abs: |3 + 4i| is 5, and |1 + 2i + 3j + 4k| the square root of 30; abs of a real number too
    errors += check(conj(a) == 1 - 2i && conj(1 + 2i + 3j + 4k) == 1 - 2i - 3j - 4k, 20)
    three_four : c64 = 3 + 4i
    errors += check(abs(three_four) == 5 && abs(cast[c32](three_four)) == 5, 21)
    p : q256 = 1 + 2i + 3j + 4k
    errors += check(abs(p) * abs(p) > 29.99 && abs(p) * abs(p) < 30.01, 22)
    negative : i32 = -7
    errors += check(abs(negative) == 7 && abs(-2.5) == 2.5 && abs(scale) == 2, 23)
    if errors == 0 {
        return 42
    }
    return errors
}
