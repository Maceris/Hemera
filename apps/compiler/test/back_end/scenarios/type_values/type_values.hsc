/*
 * Type values compared with == and types_are_aliases, which both follow plain aliases and stop at distinct ones, at
 * compile time and at run time (docs/types.md, Comparing Type Values). main returns 42 if they all held, or the number of the first that didn't.
 */
package type_values

Index :: alias int
Ind :: alias Index
Counter :: distinct alias int

#assert int == int
#assert Index == int && Ind == int
#assert Counter != int
#assert types_are_aliases(Index, int) && types_are_aliases(Ind, int)
#assert !types_are_aliases(Counter, int)
#assert types_are_aliases(Counter, Counter)

check :: fn(ok: bool, code: int) -> int {
    if ok {
        return 0
    }
    return code
}

// Type values known only at run time
loosely :: fn(a: type, b: type) -> bool {
    return types_are_aliases(a, b)
}

main :: fn() -> int {
    errors := 0
    errors += check(types_are_aliases(Ind, int) && !types_are_aliases(Counter, int), 1)
    errors += check(loosely(Ind, int) && loosely(int, Index) && loosely(Counter, Counter), 2)
    errors += check(!loosely(Counter, int) && !loosely(u8, int), 3)
    errors += check(Index == int && Counter != int && Counter == Counter, 4)
    plain : type = Ind
    counted : type = Counter
    errors += check(plain == int && counted != int, 5)
    if errors == 0 {
        return 42
    }
    return errors
}
