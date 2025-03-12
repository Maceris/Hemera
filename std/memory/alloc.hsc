package memory

import "base:runtime"

new :: fn<T>(
    T: type, 
    allocator := context.allocator,
    loc := #caller_location,
) -> ptr<T>, Allocator_Error {
    return new_aligned(T, align_of(T), allocator, loc)
}

new_aligned :: fn<T>(
    T: type,
    alignment: int,
    allocator := context.allocator,
    loc := #caller_location,
) -> ptr<T>, Allocator_Error {
    return runtime.new_aligned(T, alignment, allocator, loc)
}
