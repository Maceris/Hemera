/*
 * Complex numbers and quaternions (docs/types.md, Complex Numbers and Quaternions): floats in parts, written with
 * imaginary literals, with their arithmetic, equality, parts, mixing with real numbers, and casts between sizes. main
 * returns 42 if they all held, or the number of the first that didn't.
 */
package composites

import math from "std"

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

I :: 1i
// An untyped constant's parts, as the type it defaults to
HALF :: 0.5 + 1.5i

main :: fn() -> int {
    errors := 0
    a : c64 = 1 + 2i
    b : c64 = 3 - 4i
    errors += check(a.real == 1 && a.imag == 2 && b.imag == -4, 1)
    sum := a + b
    errors += check(sum.real == 4 && sum.imag == -2, 2)
    // (1 + 2i)(3 - 4i) = 3 - 4i + 6i + 8 = 11 + 2i
    product := a * b
    errors += check(product == 11 + 2i && product != 11 - 2i, 3)
    errors += check(product / b == a, 4)
    errors += check(-a == -1 - 2i, 5)
    errors += check(I * I == -1 && HALF.imag == 1.5, 6)

    // Mixing with a real number of the parts' type, and untyped ones
    scale : f32 = 2
    errors += check(a * scale == 2 + 4i && scale + a == 3 + 2i && a * 3 == 3 + 6i, 7)

    // Parts can be set
    c : c128
    c.real = 0.25
    c.imag = -8
    errors += check(c == 0.25 - 8i, 8)
    // To another size, part by part, and a real number as one
    narrowed := cast[c32](c)
    errors += check(narrowed.real == 0.25 && narrowed.imag == -8 && cast[c64](scale) == 2, 9)
    // An untyped one where nothing else decides is a c128
    defaulted := 2 + 3i
    errors += check(type_of(defaulted) == c128 && size_of(c32) == 4 && size_of(q256) == 32, 10)

    // Quaternions: imag, jmag, kmag, then real, and the Hamilton product: ij = k, jk = i, ki = j, ijk = -1
    i : q128 = 1i
    j : q128 = 1j
    k : q128 = 1k
    errors += check(i * j == k && j * k == i && k * i == j && i * j * k == -1, 11)
    errors += check(j * i == -k, 12)
    q : q128 = 1 + 2i + 3j + 4k
    errors += check(q.real == 1 && q.imag == 2 && q.jmag == 3 && q.kmag == 4, 13)
    errors += check((q * q) / q == q, 14)
    errors += check(q - q == 0 && q * 2 == 2 + 4i + 6j + 8k, 15)

    // std's conjugate and magnitude: |3 + 4i| is 5, and |1 + 2i + 3j + 4k| the square root of 30
    errors += check(math.conjugate(a) == 1 - 2i && math.conjugate(q) == 1 - 2i - 3j - 4k, 16)
    three_four : c64 = 3 + 4i
    length :: math.magnitude(three_four)
    errors += check(length == 5 && math.magnitude(q) * math.magnitude(q) > 29.99 && math.magnitude(q) * math.magnitude(q) < 30.01, 17)
    errors += check(math.magnitude(cast[c32](three_four)) == 5, 18)
    if errors == 0 {
        return 42
    }
    return errors
}
