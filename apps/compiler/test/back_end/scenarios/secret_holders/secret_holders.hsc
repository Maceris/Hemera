package secret_holders

import compiler from "base"
import runtime from "base"

/*
 * What holds a secret (docs/memory.md, Secrets): an optional or a result of a #secret type, whose tag is public and
 * whose value stays secret, given back from a #constant_time function and branched on by its caller; or_return's
 * fallback, which doesn't make what it gives a secret; and a #secret type's memory, zeroed before it's given back,
 * as an allocator that looks at what it's given back finds. main returns 42 if everything worked.
 */

Key :: distinct alias u8[16] #secret

// Whether an allocator was given back anything that wasn't zeros, and how many blocks it was given back.
Inspector :: struct {
    parent : runtime.Allocator,
    freed : int,
    dirty : int,
}

inspecting_function : runtime.AllocatorFn : fn(
    allocator_data: rawptr,
    size: usize,
    alignment: usize,
    old_memory: rawptr,
    old_size: usize,
    location := #caller_location,
) -> (mut u8[], runtime.AllocatorError?) {
    inspector :: cast[ptr[mut Inspector]](allocator_data)
    if old_memory != null && size == 0 {
        inspector.freed += 1
        bytes :: view_of(cast[ptr[u8]](old_memory), old_size)
        for byte in bytes {
            if byte != 0 {
                inspector.dirty += 1
                break
            }
        }
    }
    return inspector.parent.function(inspector.parent.data, size, alignment, old_memory, old_size, location)
}

make_key #constant_time :: fn(seed: u8) -> Key {
    key : Key
    for i in cast[usize](0)..<16 {
        key[i] = seed + cast[u8](i)
    }
    return key
}

// A key, if there is one: whether there is is public
key_for #constant_time :: fn(present: bool, seed: u8) -> Key? {
    if present {
        return make_key(seed)
    }
    return null
}

KeyError :: enum {
    Missing,
}

key_result #constant_time :: fn(present: bool, seed: u8) -> Result[Key, KeyError] {
    if present {
        return .Ok(make_key(seed))
    }
    return .Error(.Missing)
}

// The sum of a key's bytes, public by design here, to compare
sum_of #constant_time :: fn(key: Key) -> int {
    total := compiler.secret(cast[u32](0))
    for i in cast[usize](0)..<16 {
        total = total + cast[u32](key[i])
    }
    return cast[int](compiler.declassify(total))
}

// or_return's fallback is returned, not what it gives: found isn't a secret, so it can be pointed to
fallback #constant_time :: fn(present: bool, fallback_key: Key) -> Key? {
    found := maybe_number(present) or_return fallback_key
    pointer :: &found
    return make_key(cast[u8](pointer^))
}

maybe_number :: fn(present: bool) -> int? {
    if present {
        return 3
    }
    return null
}

main :: fn() -> int {
    // Branched on, then unwrapped: the tag is public
    first :: key_for(true, 1)
    if (first is_none) || (key_for(false, 1) is_some) {
        return 1
    }
    key :: first or_return 2
    if sum_of(key) != 136 {
        return 3
    }
    match key_result(true, 2) {
        case Ok(found) => {
            if sum_of(found) != 152 {
                return 4
            }
        }
        case Error(error) => return 5
    }
    if (key_result(false, 2) is_ok) {
        return 6
    }
    from_fallback :: fallback(false, make_key(9)) or_return 7
    if sum_of(from_fallback) != sum_of(make_key(9)) || sum_of(fallback(true, make_key(9)) or_return 8) != sum_of(make_key(3)) {
        return 9
    }

    // Freed, a #secret type's memory is zeros; anything else's is as it was
    inspector :: runtime.new(Inspector)
    defer runtime.free(inspector)
    inspector.parent = context.allocator
    inspecting :: runtime.Allocator.{inspecting_function, cast[rawptr](inspector)}
    push_context inspected (allocator = inspecting) {
        keys, error :: runtime.new_array(Key, 4)
        if error != null {
            return 10
        }
        for i in 0..<keys.count {
            keys[i] = make_key(7)
        }
        runtime.free_array(keys)
        one :: runtime.new(Key)
        one^ = make_key(8)
        runtime.free(one)
        list : Key[..]
        runtime.array_add(&list, make_key(9))
        runtime.array_free(&list)
        public :: runtime.new(u8[16])
        for i in 0..<16 {
            public[i] = 1
        }
        runtime.free(public)
    }
    // Three secret blocks given back clean, and the public one as it was
    if inspector.freed != 4 || inspector.dirty != 1 {
        return 11
    }
    return 42
}
