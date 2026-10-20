// 4 * i reaches 64, past the last of 64 elements (docs/types.md, Bounds Checking)
package bounds_scaled_past

main :: fn() -> int {
    words : u32[64]
    total : u32 = 0
    for i in 0..<17 {
        total += words[4 * i]
    }
    return cast[int](total)
}
