/*
 * What starts with its fields' defaults (docs/types.md, Structs): new's and new_array's values, a static array of
 * structs, a struct holding one, one holding a relative pointer, and a generic's variable; and has_defaults, which tells new which types have any.
 * main returns 42 if they all did, or the number of the first that didn't.
 */
package new_defaults

import runtime from "base"

Setting :: struct {
    level : u32 = 7,
    name : string = "setting",
}

Holder :: struct {
    count : int,
    settings : Setting[3],
}

Plain :: struct {
    a : u32,
    b : f64,
}

Level :: distinct alias Setting

// Its relative pointer can't be copied, so new writes its defaults where it is
Ring :: struct {
    size : u32 = 16,
    next : relptr32[u32]?,
}

// A T as a variable starts: its defaults, whatever T is
starting :: fn[T](T: type) -> T {
    initial : T
    return initial
}

// Known before the program runs, as a generic's #if or a constant would ask
HOLDER_HAS_DEFAULTS :: has_defaults(Holder)

main :: fn() -> int {
    if !has_defaults(Setting) || !has_defaults(Setting[2]) || !HOLDER_HAS_DEFAULTS || !has_defaults(Level) {
        return 1
    }
    if has_defaults(Plain) || has_defaults(u32) || has_defaults(Setting[..]) || has_defaults(ptr[Setting]) {
        return 2
    }

    one :: runtime.new(Setting)
    if one.level != 7 || one.name != "setting" {
        return 3
    }
    aligned, aligned_error :: runtime.new_aligned(Setting, 64)
    if aligned_error != null || aligned.level != 7 {
        return 4
    }
    many, many_error :: runtime.new_array(Setting, 5)
    if many_error != null || many.count != 5 {
        return 5
    }
    for setting in many {
        if setting.level != 7 || setting.name != "setting" {
            return 6
        }
    }
    holder :: runtime.new(Holder)
    if holder.count != 0 || holder.settings[2].level != 7 {
        return 7
    }

    ring :: runtime.new(Ring)
    rings, rings_error :: runtime.new_array(Ring, 2)
    if ring.size != 16 || (ring.next is_some) || rings_error != null || rings.count != 2 || rings[1].size != 16 {
        return 12
    }

    // Variables too: a static array of them, a struct holding one, and a generic's
    settings : Setting[4]
    for setting in settings {
        if setting.level != 7 {
            return 8
        }
    }
    local : Holder
    if local.settings[0].name != "setting" || local.settings[2].level != 7 {
        return 9
    }
    if starting(Setting).level != 7 || starting(Setting[2])[1].level != 7 {
        return 10
    }

    // Types without defaults are still zeroed
    plain :: runtime.new(Plain)
    bytes, bytes_error :: runtime.new_array(u8, 64)
    if plain.a != 0 || bytes_error != null || bytes.count != 64 || bytes[63] != 0 {
        return 11
    }

    runtime.free(one)
    runtime.free_aligned(aligned, 64)
    runtime.free_array(many)
    runtime.free(holder)
    runtime.free(plain)
    runtime.free_array(bytes)
    runtime.free(ring)
    runtime.free_array(rings)
    return 42
}
