package maps

import compiler from "base"
import runtime from "base"

/**
 * A map from keys of K to values of V, which finds each key by hash, a function it's made with.
 *
 * There's no overloading, so the map's type says which (docs/types.md, Checked Bodies):
 *
 *     ages : HashMap[string, int, hash_string]
 *     map_put(&ages, "Ada", 36)
 *     age :: map_get(&ages, "Ada")      // null if it isn't there
 *     map_free(&ages)
 *
 * A type alias names a combination that's used often:
 *
 *     StringMap :: alias[V] HashMap[string, V, hash_string]
 *
 * Its slots are open addressed, probed in order from where a key hashes to, and it grows to twice as many when three
 * quarters are full. Keys and values are kept by value, so what they point to, like a string key's text, has to
 * outlive the map. A zeroed HashMap is empty, with no slots, and allocates nothing until something is put in it. Its
 * slots come from context.allocator, which has to be the same allocator whenever it grows and when it's freed. Nothing
 * in it is locked, so threads sharing one need a lock.
 *
 * @tparam K The keys' type, compared with ==.
 * @tparam V The values' type.
 * @tparam hash The map's hash function.
 */
HashMap :: struct[K: compiler.Equatable, V, hash: fn(key: K) -> u64] {
    /** Each slot's key, where used says it holds one. */
    keys : mut K[],
    /** Each slot's value, where used says it holds one. */
    values : mut V[],
    /** Whether each slot holds a key. keys, values and used have the same count: the map's slots, 0 or at least 8. */
    used : mut bool[],
    /** How many keys the map holds, less than three quarters of its slots. */
    count : usize,
}

/**
 * Hash a string's bytes with FNV-1a, for a HashMap with string keys.
 *
 * @param text Any string, its bytes only read; an empty one hashes to FNV-1a's offset basis, 0xcbf29ce484222325.
 * @return The 64-bit FNV-1a hash of its bytes: the same for the same bytes, in every program, so not for keys an
 *     attacker chooses to collide.
 */
hash_string :: fn(text: string) -> u64 {
    result : u64 = 0xcbf29ce484222325
    for character in text {
        result = (result ~ cast[u64](character)) * 0x100000001b3
    }
    return result
}

/**
 * Hash an integer, mixing its bits so that nearby values land far apart, for a HashMap with integer keys.
 *
 * It's MurmurHash3's 64-bit finalizer, which maps distinct 64-bit values to distinct hashes.
 *
 * @tparam T The integer's type, of up to 64 bits, converted to u64 first.
 * @param value Any value of T. It's converted to u64 with cast, so values that convert to the same u64 hash alike.
 * @return Its hash: the same for the same value, in every program.
 */
hash_integer :: fn[T: compiler.Integer](value: T) -> u64 {
    mixed : u64 = cast[u64](value)
    mixed = (mixed ~ (mixed >> 33)) * 0xff51afd7ed558ccd
    mixed = (mixed ~ (mixed >> 33)) * 0xc4ceb9fe1a85ec53
    return mixed ~ (mixed >> 33)
}

/**
 * Find where a key is, or the free slot it would go in.
 *
 * The map is never full, so there's always a free slot to stop at.
 *
 * @tparam K The keys' type, compared with ==.
 * @tparam V The values' type.
 * @tparam hash The map's hash function.
 * @param map A map to look in, only read; one with no slots has no key.
 * @param key The key to look for, found by its hash and compared with ==.
 * @return The slot's index: key's, or the free one it would go in; 0 when the map has no slots.
 * @return True if key is there; false if it isn't, or the map has no slots.
 */
map_slot :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[HashMap[K, V, hash]], key: K) -> (usize, bool) {
    used :: map.used
    keys :: map.keys
    if used.count == 0 {
        return 0, false
    }
    start :: cast[usize](hash(key)) % used.count
    for step in 0..<used.count {
        at :: (start + step) % used.count
        if !used[at] {
            return at, false
        }
        if at < keys.count && keys[at] == key {
            return at, true
        }
    }
    return 0, false
}

/**
 * Look up the value for a key.
 *
 * @tparam K The keys' type, compared with ==.
 * @tparam V The values' type.
 * @tparam hash The map's hash function.
 * @param map A map to look in, only read.
 * @param key The key to look for, found by its hash and compared with ==.
 * @return A copy of key's value; null if the map doesn't have it.
 */
map_get :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[HashMap[K, V, hash]], key: K) -> V? {
    at, found :: map_slot(map, key)
    values :: map.values
    if !found || at >= values.count {
        return null
    }
    return values[at]
}

/**
 * Tell whether the map has a key.
 *
 * @tparam K The keys' type, compared with ==.
 * @tparam V The values' type.
 * @tparam hash The map's hash function.
 * @param map A map to look in, only read.
 * @param key The key to look for, found by its hash and compared with ==.
 * @return True if the map has it.
 */
map_has :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[HashMap[K, V, hash]], key: K) -> bool {
    _, found :: map_slot(map, key)
    return found
}

/**
 * Set a key's value, adding the key if the map doesn't have it.
 *
 * The map grows first when adding would make it more than three quarters full, which moves every key and value. If
 * the memory for that can't be had, the assertion fails ("a hash map couldn't grow: out of memory"); map_try_put
 * gives the error instead.
 *
 * @tparam K The keys' type, compared with ==.
 * @tparam V The values' type.
 * @tparam hash The map's hash function.
 * @param map A map, zeroed or from earlier calls here. Growing moves its keys and values to new slots from
 *     context.allocator, and adding a key adds one to its count.
 * @param key The key, kept by value; what it points to has to outlive the map. A key already there isn't replaced,
 *     only its value.
 * @param value The value, kept by value, replacing any the key had.
 * @param location Where the call is, for the report if growing fails.
 */
map_put :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[mut HashMap[K, V, hash]], key #escaping : K,
    value #escaping : V, location := #caller_location) {

    if (map.count + 1) * 4 > map.used.count * 3 {
        slots : usize = 8
        if map.used.count >= slots {
            slots = map.used.count * 2
        }
        map_resize(map, slots, location)
    }
    at, found :: map_slot(map, key)
    used :: map.used
    keys :: map.keys
    values :: map.values
    if at >= used.count || at >= keys.count || at >= values.count {
        return void
    }
    values[at] = value
    if !found {
        keys[at] = key
        used[at] = true
        map.count += 1
    }
}

/**
 * Take a key out, with its value, if the map has it.
 *
 * The keys after it that would have been found from its slot or before move back, so finding them still stops at the
 * first free slot. The map never shrinks.
 *
 * @tparam K The keys' type, compared with ==.
 * @tparam V The values' type.
 * @tparam hash The map's hash function.
 * @param map A map to take the key out of. When it has it, its count shrinks by one, and keys after it may move to
 *     other slots.
 * @param key The key to take out, found by its hash and compared with ==.
 * @return True if the map had it; false if it didn't, leaving the map unchanged.
 */
map_remove :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[mut HashMap[K, V, hash]], key: K) -> bool {
    at, found :: map_slot(map, key)
    used :: map.used
    keys :: map.keys
    values :: map.values
    if !found || used.count == 0 || keys.count != used.count || values.count != used.count || at >= used.count {
        return false
    }
    hole := at
    next := (at + 1) % used.count
    for step in 0..<used.count {
        if !used[next] || hole >= used.count {
            break
        }
        // Where the key in next would be found from: it can move to the hole if that's on its way
        home :: cast[usize](hash(keys[next])) % used.count
        movable :: if hole <= next { home <= hole || home > next } else { home <= hole && home > next }
        if movable {
            keys[hole] = keys[next]
            values[hole] = values[next]
            used[hole] = true
            used[next] = false
            hole = next
        }
        next = (next + 1) % used.count
    }
    if hole < used.count {
        used[hole] = false
    }
    map.count -= 1
    return true
}

/**
 * Empty the map, keeping its slots for what's added next. Keys and values aren't released, only forgotten.
 *
 * @tparam K The keys' type, compared with ==.
 * @tparam V The values' type.
 * @tparam hash The map's hash function.
 * @param map A map to empty: its count becomes 0 and every slot is free, but the slots stay allocated.
 */
map_clear :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[mut HashMap[K, V, hash]]) {
    used :: map.used
    for slot in 0..<used.count {
        used[slot] = false
    }
    map.count = 0
}

/**
 * Give back the map's slots to context.allocator, leaving it empty and zeroed, ready to use again.
 *
 * Keys and values aren't released, only forgotten: what they point to is the caller's to free.
 *
 * @tparam K The keys' type, compared with ==.
 * @tparam V The values' type.
 * @tparam hash The map's hash function.
 * @param map The map, whose slots came from the same context.allocator.
 */
map_free :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[mut HashMap[K, V, hash]]) {
    runtime.free_array(map.keys)
    runtime.free_array(map.values)
    runtime.free_array(map.used)
    empty : HashMap[K, V, hash]
    map^ = empty
}

/**
 * Move everything into a new set of slots, from context.allocator, freeing the old ones.
 *
 * If the memory can't be had, the assertion fails ("a hash map couldn't grow: out of memory"), and the map is left as
 * it was.
 *
 * @tparam K The keys' type, compared with ==.
 * @tparam V The values' type.
 * @tparam hash The map's hash function.
 * @param map A map whose slots came from context.allocator, or that has none yet. Its keys and values move to the new
 *     slots, and the old ones are freed.
 * @param slots How many slots to have. It should be more than four thirds of what the map holds, or moving the keys in
 *     grows it again.
 * @param location Where the call is, for the report if it fails.
 */
map_resize :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[mut HashMap[K, V, hash]], slots: usize,
    location := #caller_location) {

    error :: map_try_resize(map, slots, location)
    runtime.assert(error == null, "a hash map couldn't grow: out of memory", location)
}

/**
 * Set a key's value, as map_put does, but give an error rather than stopping when growing needs memory the allocator
 * doesn't have.
 *
 * It's for code that can't stop, like a kernel's on a request from user space.
 *
 * @tparam K The keys' type, compared with ==.
 * @tparam V The values' type.
 * @tparam hash The map's hash function.
 * @param map A map, zeroed or from earlier calls here. Growing moves its keys and values to new slots from
 *     context.allocator, and adding a key adds one to its count.
 * @param key The key, kept by value; what it points to has to outlive the map.
 * @param value The value, kept by value, replacing any the key had.
 * @param location Where the call is, the caller's by default; it's passed on, but an error is returned rather than
 *     reported.
 * @return Null once the value is set; OutOfMemory if the map needed to grow and the memory couldn't be had, leaving
 *     the map as it was, the key not added.
 */
map_try_put :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[mut HashMap[K, V, hash]], key #escaping : K,
    value #escaping : V, location := #caller_location) -> runtime.AllocatorError? {

    if (map.count + 1) * 4 > map.used.count * 3 {
        slots : usize = 8
        if map.used.count >= slots {
            slots = map.used.count * 2
        }
        error :: map_try_resize(map, slots, location)
        if error != null {
            return error
        }
    }
    map_put(map, key, value, location)
    return null
}

/**
 * Move everything into a new set of slots, as map_resize does, but give an error rather than stopping without the
 * memory.
 *
 * @tparam K The keys' type, compared with ==.
 * @tparam V The values' type.
 * @tparam hash The map's hash function.
 * @param map A map whose slots came from context.allocator, or that has none yet. Once the new slots are had, its keys
 *     and values move to them and the old ones are freed.
 * @param slots How many slots to have, more than four thirds of what the map holds.
 * @param location Where the call is, for the report if moving the keys in makes the map grow again, as too few slots
 *     do, and that fails.
 * @return Null once it's moved; OutOfMemory if any of the new slots' arrays couldn't be allocated, leaving the map as
 *     it was.
 */
map_try_resize :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[mut HashMap[K, V, hash]], slots: usize,
    location := #caller_location) -> runtime.AllocatorError? {

    keys, keys_error :: runtime.new_array(K, slots)
    values, values_error :: runtime.new_array(V, slots)
    used, used_error :: runtime.new_array(bool, slots)
    if keys_error != null || values_error != null || used_error != null {
        runtime.free_array(keys)
        runtime.free_array(values)
        runtime.free_array(used)
        return runtime.AllocatorError.OutOfMemory
    }
    for slot in 0..<used.count {
        used[slot] = false
    }
    old :: map^
    map.keys = keys
    map.values = values
    map.used = used
    map.count = 0
    for slot in 0..<old.used.count {
        if old.used[slot] && slot < old.keys.count && slot < old.values.count {
            map_put(map, old.keys[slot], old.values[slot], location)
        }
    }
    runtime.free_array(old.keys)
    runtime.free_array(old.values)
    runtime.free_array(old.used)
    return null
}
