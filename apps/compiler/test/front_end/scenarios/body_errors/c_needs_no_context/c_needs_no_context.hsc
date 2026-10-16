package c_needs_no_context

// A .c function that foreign code calls needs #no_context until callback shims exist
callback #calling_convention(.c) :: fn(n: int) -> int {
    return n
}
