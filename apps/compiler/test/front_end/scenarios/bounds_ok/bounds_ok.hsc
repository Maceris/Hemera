package bounds_ok

/*
 * What docs/types.md, Bounds Checking, proves: none of this is reported.
 */

import runtime from "base"

Event :: enum { Nmi, DoubleFault, MachineCheck }

TABLE :: "0123456789abcdef"

// The docs' examples
examples :: fn(resizable: i8[..], view: i8[], fixed: i8[5], unknown: usize) -> i8 {
    known : usize = 4
    result : i8 = 0
    if known < resizable.count {
        result = resizable[known]
    }
    result = fixed[known]
    if unknown >= fixed.count {
        return result
    }
    result = fixed[unknown]
    for value, index in view {
        result = view[index]
    }
    return result
}

slices :: fn(resizable: i8[..], fixed: i8[10], a: usize, b: usize) -> usize {
    whole := resizable[0..<resizable.count]
    result : i8[] = fixed[2..<5]
    result = fixed[2..=5]
    if a <= b && b <= resizable.count {
        result = resizable[a..<b]
    }
    return whole.count + result.count
}

// Counting down, and up while below the count
down :: fn(values: int[]) -> int {
    total := values.count
    sum := 0
    loop {
        sum += values[total - 1]
        total -= 1
    }
    while total > 0
    return sum
}

up :: fn(values: int[]) -> int {
    i : usize = 0
    sum := 0
    loop {
        sum += values[i]
        i += 1
    }
    while i < values.count
    return sum
}

// What a loop leaves bounded
last_part :: fn(path: string) -> string {
    start : usize = 0
    for character, i in path {
        if character == '/' {
            start = i + 1
        }
    }
    return path[start..<path.count]
}

// A count kept below the room there is
copy :: fn(from: string, to: mut u8[]) -> usize {
    count : usize = 0
    for character in from {
        if count < to.count {
            to[count] = cast[u8](character)
            count += 1
        }
    }
    return count
}

// What an assert says, a bounded index plus a bounded offset, enums, masks and remainders
pieces :: fn(values: int[], count: usize, at: usize, event: Event, hash: u64) -> int {
    runtime.assert(count <= values.count, "count fits")
    total := 0
    for i in 0..<count {
        total += values[i]
    }
    stacks : int[3]
    total += stacks[cast[u8](event)] + stacks[cast[u8](Event.MachineCheck)]
    table : int[16]
    total += table[hash & 15] + table[hash % 16]
    digit :: TABLE[hash % 16]
    if at < values.count && at + 4 <= values.count {
        for k in 0..<cast[usize](4) {
            total += values[at + k]
        }
    }
    return total
}

// view_of's count, and a slice's
made :: fn(values: int[], count: usize) -> int {
    if values.count == 0 {
        return 0
    }
    some :: view_of(&values[0], count)
    total := 0
    for i in 0..<count {
        total += some[i]
    }
    if count <= values.count {
        front :: values[0..<count]
        for i in 0..<count {
            total += front[i]
        }
    }
    return total
}

// An unsigned remainder is below its divisor whatever was divided, wrapped or not
wrapped :: fn(ring: ptr[mut Ring], head: u64, i: u64) -> int {
    return ring.items[(head + i) % 8]
}

Ring :: struct {
    items : int[8],
    count : usize,
}

// A field counted down, or given a value, keeps what was known about it
counted :: fn(ring: ptr[mut Ring]) -> int {
    if ring.count == 0 || ring.count > 8 {
        return 0
    }
    ring.count -= 1
    last :: ring.items[ring.count]
    ring.count = 3
    return last + ring.items[ring.count]
}

main :: fn() -> int {
    return 0
}

// Fields reached through an element at a constant or a local's index (names[2].count, names[i].count)
first_letters :: fn(names: string[], into: mut u8[]) -> usize {
    count : usize = 0
    for i in 0..<names.count {
        if names[i].count > 0 && count < into.count {
            into[count] = cast[u8](names[i][0])
            count += 1
        }
    }
    if names.count > 2 && names[2].count > 1 {
        return cast[usize](names[2][1])
    }
    return count
}

// Scaled indexes: a constant times a loop's name, either way around, plus a constant (4 * i + 3)
words_of :: fn(bytes: ptr[u8[64]], words: ptr[mut u32[16]]) {
    for i in 0..<16 {
        words[i] = cast[u32](bytes[4 * i]) | (cast[u32](bytes[i * 4 + 1]) << 8) | (cast[u32](bytes[2 + 4 * i]) << 16)
            | (cast[u32](bytes[4 * i + 3]) << 24)
    }
}

// A bounded value times a constant, from a loop's name that starts at 0, then a remainder
rounds :: fn(table: ptr[u8[160]]) -> u32 {
    total : u32 = 0
    for round in 0..<12 {
        s := (round % 10) * 16
        total += cast[u32](table[(s + 15) % 160])
    }
    return total
}

// A slice ending at a remainder, which is at most the count
first_part :: fn(buffer: ptr[u8[1000]], count: usize) -> u8[] {
    return buffer[0..<count % 1001]
}

// A difference against a constant, like count - at >= 16, once at is known to be at most count
blocks_of :: fn(data: u8[]) -> u32 {
    total : u32 = 0
    at : usize = 0
    loop {
        total += cast[u32](data[at + 15])
        at += 16
    }
    while data.count - at >= 16
    if 4 <= data.count - at {
        total += cast[u32](data[at + 3])
    }
    return total
}

// Sums of scaled loop names, like 16 * b + 4 * j + k
tiles :: fn(grid: ptr[u8[64]]) -> u32 {
    total : u32 = 0
    for b in 0..<4 {
        for j in 0..<4 {
            for k in 0..<4 {
                total += cast[u32](grid[16 * b + 4 * j + k])
            }
        }
    }
    return total
}

// A floored remainder by a constant is never negative, even of a signed value
floored :: fn(ring: ptr[int[16]], i: int) -> int {
    return ring[i %% 16]
}
