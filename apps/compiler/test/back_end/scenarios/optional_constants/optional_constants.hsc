/*
 * docs/types.md, Optionals: constants holding optionals of structs, as members of structs and elements of arrays, some
 * Some and some None.
 */
package optional_constants

Share :: struct {
    priority : u32,
    period : u64,
    time : u64,
}

FAST :: Share.{priority = 200, period = 10, time = 1}

Entry :: struct {
    name : string,
    flag : bool,
    cpu : Share?,
}

// The struct around it, which has its shape too
Outer :: struct {
    first : u8,
    entry : Entry,
    last : u16,
}

ENTRIES :: Entry.[
    Entry.{name = "none"},
    Entry.{name = "named", flag = true, cpu = FAST},
    Entry.{name = "literal", cpu = Share.{priority = 7, period = 20, time = 3}},
]

OUTER :: Outer.{first = 1, entry = Entry.{name = "inner", cpu = FAST}, last = 0xbeef}

MaybeShare :: Share?

SHARES :: MaybeShare.[null, FAST, null]

main :: fn() -> int {
    if (ENTRIES[0].cpu is_some) || ENTRIES[0].name != "none" {
        return 1
    }
    named :: ENTRIES[1].cpu or_return 2
    if named.priority != 200 || named.period != 10 || named.time != 1 || !ENTRIES[1].flag || ENTRIES[1].name != "named" {
        return 3
    }
    literal :: ENTRIES[2].cpu or_return 4
    if literal.priority != 7 || literal.period != 20 || literal.time != 3 || ENTRIES[2].name != "literal" {
        return 5
    }
    inner :: OUTER.entry.cpu or_return 6
    if OUTER.first != 1 || OUTER.last != 0xbeef || inner.priority != 200 || OUTER.entry.name != "inner" {
        return 7
    }
    if (SHARES[0] is_some) || (SHARES[2] is_some) {
        return 8
    }
    share :: SHARES[1] or_return 9
    if share.priority != 200 {
        return 10
    }
    return 42
}
