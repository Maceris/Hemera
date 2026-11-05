/*
 * docs/types.md, Optionals: constants holding optionals of structs, as members of structs and elements of arrays, some
 * Some and some None.
 */
package optional_constants

import testing from "std"

/** A share of the processor, a struct with fields of two sizes. */
Share :: struct {
    /** Any value. */
    priority : u32,
    /** Any value. */
    period : u64,
    /** Any value. */
    time : u64,
}

/** A Share, as a named constant. */
FAST :: Share.{priority = 200, period = 10, time = 1}

/** A struct with an optional Share among other fields. */
Entry :: struct {
    /** Any text. */
    name : string,
    /** Any value. */
    flag : bool,
    /** None when it's left out. */
    cpu : Share?,
}

/** The struct around an Entry, which has its shape too. */
Outer :: struct {
    /** Any value. */
    first : u8,
    /** An Entry, inside. */
    entry : Entry,
    /** Any value. */
    last : u16,
}

/** Entries whose Share is left out, a named constant, and a literal. */
ENTRIES :: Entry.[
    Entry.{name = "none"},
    Entry.{name = "named", flag = true, cpu = FAST},
    Entry.{name = "literal", cpu = Share.{priority = 7, period = 20, time = 3}},
]

/** An Entry with a Share, inside an Outer. */
OUTER :: Outer.{first = 1, entry = Entry.{name = "inner", cpu = FAST}, last = 0xbeef}

/** An optional Share, as an array's element type. */
MaybeShare :: Share?

/** Optional Shares, none on either side of one. */
SHARES :: MaybeShare.[null, FAST, null]

holds_optionals_in_struct_constants #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, ENTRIES[0].cpu is_none, "an optional left out of a constant's literal is none")
    testing.expect_eq(t, ENTRIES[0].name, "none", "the fields beside an empty optional are as given")
    named :: testing.require_some(t, ENTRIES[1].cpu, "an optional given a named constant holds it")?
    testing.expect(t, named.priority == 200 && named.period == 10 && named.time == 1, "it holds FAST's fields")
    testing.expect(t, ENTRIES[1].flag && ENTRIES[1].name == "named", "the fields beside a full optional are as given")
    literal :: testing.require_some(t, ENTRIES[2].cpu, "an optional given a literal holds it")?
    testing.expect(t, literal.priority == 7 && literal.period == 20 && literal.time == 3, "it holds the literal's fields")
    testing.expect_eq(t, ENTRIES[2].name, "literal", "the field beside it is as given")
    inner :: testing.require_some(t, OUTER.entry.cpu, "an optional in a struct inside a struct holds its value")?
    testing.expect_eq(t, inner.priority, 200, "it holds FAST's fields")
    testing.expect_eq(t, OUTER.first, 1, "the outer struct's field before it is as given")
    testing.expect_eq(t, OUTER.last, 0xbeef, "the outer struct's field after it is as given")
    testing.expect_eq(t, OUTER.entry.name, "inner", "the inner struct's other field is as given")
    return .Ok
}

holds_optionals_as_array_elements #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, SHARES[0] is_none, "a null element is none")
    testing.expect(t, SHARES[2] is_none, "a null element after a full one is none")
    share :: testing.require_some(t, SHARES[1], "an element given a constant holds it")?
    testing.expect_eq(t, share.priority, 200, "it holds FAST's fields")
    return .Ok
}
