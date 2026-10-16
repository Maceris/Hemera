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
copy :: fn(from: string, to: u8[]) -> usize {
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

main :: fn() -> int {
    return 0
}
