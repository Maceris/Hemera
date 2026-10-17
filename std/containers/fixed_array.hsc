package containers

/*
 * Up to capacity values of T, in order, in the array itself: like a dynamic array that never
 * allocates, and fails to add once it's full.
 *
 *     ids : FixedArray[u32, 16]
 *     fixed_push(&ids, 7)          // false once it's full
 *     for id in fixed_view(&ids) {}
 */
FixedArray :: struct[T, capacity: usize] {
    items : T[capacity],
    count : usize,
}

// Add value at the end, unless it's full.
fixed_push :: fn[T, capacity: usize](array: ptr[mut FixedArray[T, capacity]], value #escaping : T) -> bool {
    if array.count >= capacity {
        return false
    }
    array.items[array.count] = value
    array.count += 1
    return true
}

// Take the last value, if there is one.
fixed_pop :: fn[T, capacity: usize](array: ptr[mut FixedArray[T, capacity]]) -> T? {
    if array.count == 0 || array.count > capacity {
        return null
    }
    last :: array.count - 1
    value :: array.items[last]
    array.count = last
    return value
}

/*
 * Remove the value at index by moving the last one into its place, so it doesn't keep the order.
 * False if there's nothing at index.
 */
fixed_remove_swap :: fn[T, capacity: usize](array: ptr[mut FixedArray[T, capacity]], index: usize) -> bool {
    if index >= array.count || array.count > capacity {
        return false
    }
    last :: array.count - 1
    array.items[index] = array.items[last]
    array.count = last
    return true
}

// The values it holds, as a view into it: valid until it changes.
fixed_view :: fn[T, capacity: usize](array: ptr[mut FixedArray[T, capacity]]) -> T[] {
    count :: if array.count < capacity { array.count } else { capacity }
    return view_of(&array.items[0], count)
}

fixed_clear :: fn[T, capacity: usize](array: ptr[mut FixedArray[T, capacity]]) {
    array.count = 0
}
