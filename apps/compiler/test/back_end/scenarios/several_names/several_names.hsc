/*
 * Several names in one declaration (docs/functions.md, Several Names in One Declaration): each with its own value, in
 * order, typed once or not, at the top level and in a function, or one value for them all. main returns 42 if they all
 * held, or the number of the first that didn't.
 */
package several_names

MIN, MAX :: -10, 10
WIDTH, HEIGHT : u32 : 640, 480

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

divide :: fn(a: int, b: int) -> (int, int) {
    return a / b, a % b
}

main :: fn() -> int {
    errors := 0
    errors += check(MIN == -10 && MAX == 10 && WIDTH * HEIGHT == 307200, 1)
    x, y, z := 1, 2, 3
    errors += check(x + y * 10 + z * 100 == 321, 2)
    small, large : u8 = 1, 200
    errors += check(cast[int](small) + cast[int](large) == 201, 3)
    quotient, remainder := divide(7, 2)
    errors += check(quotient == 3 && remainder == 1, 4)
    low, high, extra := divide(9, 4), 5
    errors += check(low == 2 && high == 1 && extra == 5, 5)
    // Each is its own variable
    x, y = y, x
    errors += check(x == 2 && y == 1, 6)
    both, too := 7
    errors += check(both == 7 && too == 7, 7)
    if errors == 0 {
        return 42
    }
    return errors
}
