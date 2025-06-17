package memory

import runtime from "base"

new :: fn[T](
    T: type, 
    allocator := context.allocator,
    loc := #caller_location,
) -> (ptr[T], AllocatorError?) {
    return new_aligned(T, align_of(T), allocator, loc)
}

new_aligned :: fn[T](
    T: type,
    alignment: int,
    allocator := context.allocator,
    loc := #caller_location,
) -> (ptr[T], AllocatorError?) {
    return runtime.new_aligned(T, alignment, allocator, loc)
}
