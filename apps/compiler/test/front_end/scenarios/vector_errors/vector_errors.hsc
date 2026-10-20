/*
 * Vectors used wrongly (docs/types.md, Vectors): lanes that can't be, counts that aren't powers of two
 * or are too big, a lane chosen at run time or out of range, operators that don't apply, intrinsics
 * given what they can't take, an immediate that isn't a constant, and #target_features misused.
 */
package vector_errors

import intrinsics from "base"
import x86_64 from "base/intrinsics"

Words :: vector[u32, 4]
Strings :: vector[string, 4]
Three :: vector[u32, 3]
Huge :: vector[u64, 16]

added #target_features("+aes") :: fn() {}

main :: fn() -> int {
    a := Words.{1, 2, 3, 4}
    which := 2
    _ = a[which]
    _ = a[4]
    _ = a + vector[u32, 8].{}
    _ = a / a
    bits := bit_cast[v128](a)
    _ = bits + bits
    _ = Words.{1, 2}
    _ = intrinsics.rotate_lanes(a, which)
    _ = intrinsics.reduce_add(vector[f32, 4].{})
    _ = intrinsics.byte_swap(cast[u8](1))
    _ = x86_64.aes_key_assist(bits, cast[u8](which))
    _ = a + 0x1_0000_0000
    // These are fine
    _ = a[3] + intrinsics.reduce_add(a)
    return 0
}
