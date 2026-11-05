package secret_holders

import compiler from "base"
import runtime from "base"
import testing from "std"

/*
 * What holds a secret (docs/memory.md, Secrets): an optional or a result of a #secret type, whose tag is public and
 * whose value stays secret, given back from a #constant_time function and branched on by its caller; or_return's
 * fallback, which doesn't make what it gives a secret; and a #secret type's memory, zeroed before it's given back,
 * as an allocator that looks at what it's given back finds.
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

branches_on_a_secret_optionals_public_tag #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Branched on, then unwrapped: the tag is public
    first :: key_for(true, 1)
    testing.expect(t, first is_some, "a key asked for is there")
    testing.expect(t, key_for(false, 1) is_none, "a key not asked for isn't")
    key :: testing.require_some(t, first, "its value unwraps")?
    testing.expect_eq(t, sum_of(key), 136, "the key from 1 is 1 to 16, its secret value kept whole")
    return .Ok
}

branches_on_a_secret_results_public_tag #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    made :: key_result(true, 2)
    found :: testing.require_ok(t, made, "a key asked for is there")?
    testing.expect_eq(t, sum_of(found), 152, "the key from 2 is 2 to 17, its secret value kept whole")
    testing.expect_error(t, key_result(false, 2), KeyError.Missing, "a key not asked for is missing")
    return .Ok
}

returns_or_returns_fallback #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    from_fallback :: testing.require_some(t, fallback(false, make_key(9)), "or_return gives back its fallback key")?
    testing.expect_eq(t, sum_of(from_fallback), sum_of(make_key(9)), "the fallback is given back as it was")
    from_number :: testing.require_some(t, fallback(true, make_key(9)), "with a number found, a key is made from it")?
    testing.expect_eq(t, sum_of(from_number), sum_of(make_key(3)), "the key is made from the number found, 3")
    return .Ok
}

zeroes_a_secret_types_memory_when_its_freed #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    // Freed, a #secret type's memory is zeros; anything else's is as it was
    inspector :: runtime.new(Inspector)
    defer runtime.free(inspector)
    inspector.parent = context.allocator
    inspecting :: runtime.Allocator.{inspecting_function, cast[rawptr](inspector)}
    push_context inspected (allocator = inspecting) {
        keys, error :: runtime.new_array(Key, 4)
        testing.require(t, error == null, "four keys can be allocated")?
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
    testing.expect_eq(t, inspector.freed, 4, "an array of keys, a key, a dynamic array of keys and a public block are given back")
    testing.expect_eq(t, inspector.dirty, 1, "the three secret blocks are zeros, and only the public one is as it was")
    return .Ok
}
