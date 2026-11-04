package compiler

/*
 * Owned types (docs/memory.md, Owned Types): each value of an #owned type has one owner, which
 * releases it or moves it on, and the compiler checks every path does. These are how a type's own
 * functions make and end owners outside those rules, and how general code releases one.
 */

/**
 * End an owner without anything happening: nothing releases what it owned.
 *
 * @tparam T The owned type.
 * @param value The owner, moved in and dropped. Whatever it held, like an open file, is left as it is, so something
 *     else has to be responsible for it.
 */
forget :: fn[T](value: T) {
}

/**
 * Make a second owner of the same value, without its type knowing: for a type's own share function, which counts
 * the owners itself.
 *
 * @tparam T The owned type.
 * @param value The owner to copy, which stays an owner too.
 * @return A copy of it, a second owner of what it holds; both have to be released or moved on.
 */
duplicate :: fn[T](value: ptr[T]) -> T {
    return value^
}

/**
 * Move out what a place owns, a field or an element, leaving it empty.
 *
 * @tparam T The owned type.
 * @param place Where the owner is; it's left zero, which owns nothing.
 * @return What place held, now owned by the caller.
 */
take :: fn[T](place: ptr[mut T]) -> T {
    value :: place^
    empty : T
    place^ = empty
    return value
}

/**
 * Release value with the function its type names in #owned(...), so general code can release any owner.
 *
 * @tparam T The owned type, which has to name a release function.
 * @param value The owner, moved in and released.
 */
release : fn[T](value: T) : ---
