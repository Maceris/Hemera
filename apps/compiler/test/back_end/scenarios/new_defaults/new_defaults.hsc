/*
 * What starts with its fields' defaults (docs/types.md, Structs): new's and new_array's values, a static array of
 * structs, a struct holding one, one holding a relative pointer, and a generic's variable; and has_defaults, which tells new which types have any.
 */
package new_defaults

import runtime from "base"
import testing from "std"

/** A struct whose fields both have defaults. */
Setting :: struct {
    /** Defaults to 7. */
    level : u32 = 7,
    /** Defaults to "setting". */
    name : string = "setting",
}

/** A struct with no defaults of its own, holding structs that have them. */
Holder :: struct {
    /** No default: zero. */
    count : int,
    /** Each Setting's defaults. */
    settings : Setting[3],
}

/** A struct with no defaults anywhere. */
Plain :: struct {
    /** No default: zero. */
    a : u32,
    /** No default: zero. */
    b : f64,
}

/** A distinct alias of Setting, which keeps its defaults. */
Level :: distinct alias Setting

/* Included with using, named or not, and an anonymous struct: their members' defaults are the struct's */

/** Setting included by using, under a name. */
Named :: struct {
    /** Setting's defaults, its members reachable through Named. */
    using setting : Setting,
    /** No default: zero. */
    extra : u32,
}
/** Setting included by using, without a name. */
Unnamed :: struct {
    using Setting,
    /** No default: zero. */
    extra : u32,
}
/** An anonymous struct with a default, included in another. */
Anonymous :: struct {
    _ : struct {
        /** Defaults to 5. */
        depth : u32 = 5,
    },
    /** No default: zero. */
    extra : u32,
}

/** A struct holding a relative pointer, which can't be copied, so new writes its defaults where it is. */
Ring :: struct {
    /** Defaults to 16. */
    size : u32 = 16,
    /** No default: none. */
    next : relptr32[u32]?,
}

/**
 * Make a variable of a type, as a generic would, to show it starts with the type's defaults, whatever the type is.
 *
 * @param T The type.
 * @return A T as a variable of it starts.
 */
starting :: fn[T](T: type) -> T {
    initial : T
    return initial
}

/** Known before the program runs, as a generic's #if or a constant would ask. */
HOLDER_HAS_DEFAULTS :: has_defaults(Holder)

tells_which_types_have_defaults #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, has_defaults(Setting) && has_defaults(Setting[2]), "a struct with defaults, and an array of them, have some")
    testing.expect(t, HOLDER_HAS_DEFAULTS, "a struct holding structs with defaults has them, known as a constant")
    testing.expect(t, has_defaults(Level), "a distinct alias keeps its struct's defaults")
    testing.expect(t, !has_defaults(Plain) && !has_defaults(u32), "a struct without defaults, and a number, start as zeroes")
    testing.expect(t, !has_defaults(Setting[..]) && !has_defaults(ptr[Setting]), "a dynamic array or a pointer starts empty, whatever it holds")
    testing.expect(t, has_defaults(Named) && has_defaults(Unnamed) && has_defaults(Anonymous), "members included by using, or anonymous, bring their defaults")
    return .Ok
}

new_gives_defaults #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    one :: runtime.new(Setting)
    defer runtime.free(one)
    testing.expect_eq(t, one.level, 7, "new starts a struct with its defaults")
    testing.expect_eq(t, one.name, "setting", "new starts every field with its default")

    aligned, aligned_error :: runtime.new_aligned(Setting, 64)
    testing.require(t, aligned_error == null, "a 64-byte-aligned Setting can be allocated")?
    defer runtime.free_aligned(aligned, 64)
    testing.expect_eq(t, aligned.level, 7, "new_aligned starts it with its defaults too")

    many, many_error :: runtime.new_array(Setting, 5)
    testing.require(t, many_error == null, "five Settings can be allocated")?
    defer runtime.free_array(many)
    testing.expect_eq(t, many.count, 5, "new_array gives as many as asked for")
    for setting in many {
        testing.expect(t, setting.level == 7 && setting.name == "setting", "new_array starts every element with its defaults")
    }

    holder :: runtime.new(Holder)
    defer runtime.free(holder)
    testing.expect_eq(t, holder.count, 0, "a field without a default is zeroed")
    testing.expect_eq(t, holder.settings[2].level, 7, "structs held in an array field get their defaults")

    ring :: runtime.new(Ring)
    defer runtime.free(ring)
    rings, rings_error :: runtime.new_array(Ring, 2)
    testing.require(t, rings_error == null, "two Rings can be allocated")?
    defer runtime.free_array(rings)
    testing.expect_eq(t, ring.size, 16, "new writes defaults in place for a struct holding a relative pointer")
    testing.expect(t, ring.next is_none, "the relative pointer, without a default, starts empty")
    testing.expect(t, rings.count == 2 && rings[1].size == 16, "new_array writes them in place for each element")

    testing.expect(t, runtime.new(Named).level == 7 && runtime.new(Unnamed).level == 7, "new gives members included by using their defaults")
    testing.expect_eq(t, runtime.new(Anonymous).depth, 5, "new gives an anonymous struct's members their defaults")

    // Types without defaults are still zeroed
    plain :: runtime.new(Plain)
    defer runtime.free(plain)
    bytes, bytes_error :: runtime.new_array(u8, 64)
    testing.require(t, bytes_error == null, "64 bytes can be allocated")?
    defer runtime.free_array(bytes)
    testing.expect_eq(t, plain.a, 0, "a struct without defaults is zeroed")
    testing.expect(t, bytes.count == 64 && bytes[63] == 0, "bytes are zeroed to the last")
    return .Ok
}

variables_start_with_defaults #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    settings : Setting[4]
    for setting in settings {
        testing.expect_eq(t, setting.level, 7, "each struct of a static array variable starts with its defaults")
    }
    local : Holder
    testing.expect_eq(t, local.settings[0].name, "setting", "a struct variable's array of structs starts with their defaults")
    testing.expect_eq(t, local.settings[2].level, 7, "to the array's last element")
    testing.expect_eq(t, starting(Setting).level, 7, "a generic's variable of a struct starts with its defaults")
    testing.expect_eq(t, starting(Setting[2])[1].level, 7, "a generic's variable of an array of structs does too")

    named : Named
    unnamed : Unnamed
    anonymous : Anonymous
    testing.expect_eq(t, named.setting.level, 7, "a member included by using, by name, starts with its defaults")
    testing.expect(t, unnamed.level == 7 && unnamed.name == "setting", "a member included by using, without a name, starts with its defaults")
    testing.expect_eq(t, anonymous.depth, 5, "an anonymous struct's members start with their defaults")
    return .Ok
}

literals_fill_in_defaults #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    named_literal := Named.{extra = 1}
    held_literal := Holder.{count = 2}
    anonymous_literal := Anonymous.{extra = 1}
    testing.expect_eq(t, named_literal.level, 7, "a literal leaving out a member included by using gives it its defaults")
    testing.expect_eq(t, held_literal.settings[2].level, 7, "a literal leaving out an array of structs gives them their defaults")
    testing.expect_eq(t, anonymous_literal.depth, 5, "a literal leaving out an anonymous struct gives it its defaults")
    // What's given wins over the defaults it's inside
    given := Unnamed.{level = 1}
    testing.expect_eq(t, given.level, 1, "a field given in the literal wins over its default")
    testing.expect_eq(t, given.name, "setting", "the fields beside it keep their defaults")
    return .Ok
}
