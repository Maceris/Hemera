package builtin

/*
 * Views and strings over memory a program didn't get from Hemera: tables from firmware or a
 * bootloader, device memory, data from another language. Neither is checked: the caller makes
 * sure the elements are all there, and stay there while the view is used.
 *
 * A view and a string are laid out as the count, then the address of the first element.
 */

/**
 * Make a view of elements in memory a program didn't get from Hemera, like a table firmware wrote.
 *
 * Nothing is checked, as with a cast to a pointer: the caller makes sure the elements are all there, and stay there
 * while the view is used.
 *
 * @tparam T The elements' type.
 * @param data The first element. From a ptr[mut T], the elements can be changed through the view.
 * @param count How many elements, not bytes: the view covers count × size_of(T) bytes. 0 gives an empty view.
 * @return A view of count elements of T starting at data, sharing that memory, not a copy.
 */
view_of :: fn[T](data: ptr[T], count: usize) -> T[] {
    return bit_cast[T[]](usize.[count, cast[usize](data)])
}

/**
 * Make a string of bytes in memory a program didn't get from Hemera, like a name a bootloader passed.
 *
 * Nothing is checked: not that the bytes are there, nor that they're UTF-8. The caller makes sure they stay there
 * while the string is used.
 *
 * @param data Where the string's first byte is; it isn't read here, and may be null when count is 0.
 * @param count How many bytes, without any terminating 0. 0 gives an empty string.
 * @return The string of those bytes, sharing that memory, not a copy.
 */
string_of :: fn(data: ptr[u8], count: usize) -> string {
    return bit_cast[string](usize.[count, cast[usize](data)])
}

/**
 * Give a string's bytes, as a view of them, for code that works with bytes.
 *
 * @param text The string; it isn't copied.
 * @return A view of its count bytes: the same memory, good for as long as the string's memory is, which the compiler
 *     checks.
 */
string_bytes :: fn(text: string) -> u8[] {
    return bit_cast[u8[]](usize.[text.count, cast[usize](text.data)])
}
