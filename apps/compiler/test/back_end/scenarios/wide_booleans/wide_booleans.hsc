/*
 * b16, b32 and b64 (docs/types.md): true is 1 and false 0, in a wider integer, and ! gives the other,
 * through a widening and as a condition. main returns 42 if they all held, or the number of the first that
 * didn't.
 */
package wide_booleans

check :: fn(ok: b64, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

flip :: fn(value: b32) -> b32 {
    return !value
}

main :: fn() -> int {
    errors := 0
    a : b16 = true
    b : b32 = true
    c : b64 = true
    off : b16 = false
    errors += check(!(!a), 1)
    errors += check(!(!b), 2)
    errors += check(!(!c), 3)
    errors += check(!off, 4)
    errors += check(bit_cast[u16](!a) == 0 && bit_cast[u16](!off) == 1, 5)
    wide : b64 = a
    errors += check(!(!wide), 6)
    errors += check(bit_cast[u32](flip(true)) == 0 && bit_cast[u32](flip(false)) == 1, 7)
    if !c {
        errors += 8
    }
    if errors == 0 {
        return 42
    }
    return errors
}
