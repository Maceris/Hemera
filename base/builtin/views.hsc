package builtin

/*
 * Views and strings over memory a program didn't get from Hemera: tables from firmware or a
 * bootloader, device memory, data from another language. Neither is checked: the caller makes
 * sure the elements are all there, and stay there while the view is used.
 *
 * A view and a string are laid out as the count, then the address of the first element.
 */

/*
 * A view of count elements of T, starting at data, so count × size_of(T) bytes. From a
 * ptr[mut T], the elements can be changed through the view.
 */
view_of :: fn[T](data: ptr[T], count: usize) -> T[] {
    return bit_cast[T[]](usize.[count, cast[usize](data)])
}

// The text of count bytes, starting at data.
string_of :: fn(data: ptr[u8], count: usize) -> string {
    return bit_cast[string](usize.[count, cast[usize](data)])
}
