package math

import intrinsics from "base"

/*
 * Complex numbers and quaternions (docs/types.md, Complex Numbers and Quaternions): what isn't an operator, for any of
 * c32, c64, c128, q64, q128 and q256.
 */

// The float a complex number's or a quaternion's parts are: f16, f32 or f64.
part_of :: fn(T: type) -> type {
    info :: type_info_of(T)
    parts : usize = if info.variant == .QUATERNION { 4 } else { 2 }
    bytes :: info.size / parts
    return if bytes == 2 { f16 } else if bytes == 4 { f32 } else { f64 }
}

// z with its imaginary parts negated: twice its real part, less itself.
conjugate :: fn[T](z: T) -> T {
    return 2 * z.real - z
}

// How far z is from 0: the square root of the sum of its parts' squares, which z times its conjugate is.
magnitude :: fn[T, P = part_of(T)](z: T) -> P {
    return intrinsics.square_root((z * conjugate(z)).real)
}
