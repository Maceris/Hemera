/*
 * Type values compared with == and types_are_aliases, which both follow plain aliases and stop at distinct ones, at
 * compile time and at run time (docs/types.md, Comparing Type Values).
 */
package type_values

import testing from "std"

Index :: alias int
Ind :: alias Index
Counter :: distinct alias int

#assert int == int
#assert Index == int && Ind == int
#assert Counter != int
#assert types_are_aliases(Index, int) && types_are_aliases(Ind, int)
#assert !types_are_aliases(Counter, int)
#assert types_are_aliases(Counter, Counter)

// Type values known only at run time
loosely :: fn(a: type, b: type) -> bool {
    return types_are_aliases(a, b)
}

follows_plain_aliases_and_stops_at_distinct_ones #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, types_are_aliases(Ind, int), "an alias of an alias of int is int")
    testing.expect(t, !types_are_aliases(Counter, int), "a distinct alias isn't what it's made from")
    testing.expect(t, Index == int && Counter != int && Counter == Counter, "== follows plain aliases and stops at distinct ones")
    return .Ok
}

compares_types_known_only_at_run_time #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, loosely(Ind, int) && loosely(int, Index), "plain aliases are aliases at run time, either way round")
    testing.expect(t, loosely(Counter, Counter), "a distinct type is an alias of itself")
    testing.expect(t, !loosely(Counter, int), "a distinct alias isn't what it's made from, at run time either")
    testing.expect(t, !loosely(u8, int), "different types aren't aliases")
    plain : type = Ind
    counted : type = Counter
    testing.expect(t, plain == int, "a type variable holding an alias of int is int")
    testing.expect(t, counted != int, "one holding a distinct alias isn't")
    return .Ok
}
