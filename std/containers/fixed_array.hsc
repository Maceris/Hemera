package containers

import compiler from "base"

/**
 * Up to capacity values of T, in order, in the array itself: like a dynamic array that never allocates, and fails to
 * add once it's full.
 *
 * Its zero value is empty. Nothing in it is atomic, so threads sharing one need a lock.
 *
 *     ids : FixedArray[u32, 16]
 *     fixed_push(&ids, 7)          // false once it's full
 *     for id in fixed_view(&ids) {}
 *
 * @tparam T The values' type.
 * @tparam capacity The most values it holds: at least 1. They're kept in the array itself, so it's capacity values
 *     large.
 */
FixedArray :: struct[T, capacity: usize] where compiler.AtLeastOne(capacity) {
    /** The values: the first count of them are in use, the rest left as they were. */
    items : T[capacity],
    /** How many values it holds, from 0 to capacity. */
    count : usize,
}

/**
 * Add a value at the end, unless it's full.
 *
 * @tparam T The values' type.
 * @tparam capacity The most values it holds.
 * @param array An array to add to; when it has room, its count grows by one.
 * @param value The value, copied in.
 * @return True if it was added; false if the array was full, leaving it unchanged.
 */
fixed_push :: fn[T, capacity: usize](array: ptr[mut FixedArray[T, capacity]], value #escaping : T) -> bool {
    if array.count >= capacity {
        return false
    }
    array.items[array.count] = value
    array.count += 1
    return true
}

/**
 * Take the last value, if there is one.
 *
 * @tparam T The values' type.
 * @tparam capacity The most values it holds.
 * @param array An array to take from; when it isn't empty, its count shrinks by one.
 * @return The last value, removed; null if the array is empty.
 */
fixed_pop :: fn[T, capacity: usize](array: ptr[mut FixedArray[T, capacity]]) -> T? {
    if array.count == 0 || array.count > capacity {
        return null
    }
    last :: array.count - 1
    value :: array.items[last]
    array.count = last
    return value
}

/**
 * Remove the value at an index by moving the last one into its place, so it doesn't keep the order but takes constant
 * time.
 *
 * @tparam T The values' type.
 * @tparam capacity The most values it holds.
 * @param array An array to remove from; when index is in it, its count shrinks by one and its last value moves to
 *     index.
 * @param index The value's index, below the count.
 * @return True if it was removed; false if there's nothing at index, leaving the array unchanged.
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

/**
 * View the values the array holds, without copying them.
 *
 * @tparam T The values' type.
 * @tparam capacity The most values it holds.
 * @param array An array to view; viewing it doesn't change it.
 * @return A view into it of its count values, in order, empty for an empty array: valid until it changes, and no
 *     longer than the array lives.
 */
fixed_view :: fn[T, capacity: usize](array: ptr[mut FixedArray[T, capacity]]) -> T[] {
    count :: if array.count < capacity { array.count } else { capacity }
    return view_of(&array.items[0], count)
}

/**
 * Empty the array. The values aren't cleared or released, only forgotten.
 *
 * @tparam T The values' type.
 * @tparam capacity The most values it holds.
 * @param array An array to empty; its count becomes 0.
 */
fixed_clear :: fn[T, capacity: usize](array: ptr[mut FixedArray[T, capacity]]) {
    array.count = 0
}
