package jmag_of_complex

// jmag and kmag are only a quaternion's parts
main :: fn() -> f32 {
    z : c64 = 1 + 2i
    return jmag(z)
}
