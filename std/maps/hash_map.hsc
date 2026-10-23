package maps

import compiler from "base"
import runtime from "base"

/*
 * A map from keys of K to values of V, which finds each key by hash, a function it's made with.
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
 * Its slots are open addressed, probed in order from where a key hashes to, and it grows to twice as
 * many when three quarters are full. Keys and values are kept by value, so what they point to, like a
 * string key's text, has to outlive the map. A zeroed HashMap is empty.
 */
HashMap :: struct[K: compiler.Equatable, V, hash: fn(key: K) -> u64] {
    keys : K[],
    values : V[],
    // Whether each slot holds a key
    used : bool[],
    count : usize,
}

// FNV-1a over a string's bytes.
hash_string :: fn(text: string) -> u64 {
    result : u64 = 0xcbf29ce484222325
    for character in text {
        result = (result ~ cast[u64](character)) * 0x100000001b3
    }
    return result
}

// An integer's bits, mixed so that nearby values land far apart.
hash_integer :: fn[T: compiler.Integer](value: T) -> u64 {
    mixed : u64 = cast[u64](value)
    mixed = (mixed ~ (mixed >> 33)) * 0xff51afd7ed558ccd
    mixed = (mixed ~ (mixed >> 33)) * 0xc4ceb9fe1a85ec53
    return mixed ~ (mixed >> 33)
}

/*
 * Where key is, or the free slot it would go in, and whether it's there. The map is never full, so
 * there's always a free slot to stop at.
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

// The value for key, or null if the map doesn't have it.
map_get :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[HashMap[K, V, hash]], key: K) -> V? {
    at, found :: map_slot(map, key)
    values :: map.values
    if !found || at >= values.count {
        return null
    }
    return values[at]
}

map_has :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[HashMap[K, V, hash]], key: K) -> bool {
    _, found :: map_slot(map, key)
    return found
}

// Sets key's value, adding key if the map doesn't have it.
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

/*
 * Takes key out, if the map has it, and whether it did. The keys after it that would have been found
 * from its slot or before move back, so finding them still stops at the first free slot.
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

// Empties the map, keeping its slots for what's added next.
map_clear :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[mut HashMap[K, V, hash]]) {
    used :: map.used
    for slot in 0..<used.count {
        used[slot] = false
    }
    map.count = 0
}

// Gives back the map's slots, leaving it empty.
map_free :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[mut HashMap[K, V, hash]]) {
    runtime.free_array(map.keys)
    runtime.free_array(map.values)
    runtime.free_array(map.used)
    empty : HashMap[K, V, hash]
    map^ = empty
}

// Moves everything into a new set of slots, which have to be more than it holds.
map_resize :: fn[K: compiler.Equatable, V, hash: fn(key: K) -> u64](map: ptr[mut HashMap[K, V, hash]], slots: usize,
    location := #caller_location) {

    error :: map_try_resize(map, slots, location)
    runtime.assert(error == null, "a hash map couldn't grow: out of memory", location)
}

/*
 * Like map_put, but where growing needs memory the allocator doesn't have, gives its error and leaves the
 * map as it was, for code that can't stop, like a kernel's on a request from user space.
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

// Like map_resize, but without the memory, gives the allocator's error and leaves the map as it was.
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
