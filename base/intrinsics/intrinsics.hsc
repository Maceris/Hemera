package intrinsics

/*
 * Returns the location that the current function call will return to once
 * done.
 * Intended for fiber schedulers.
 */
get_return_address : fn() -> rawptr : ---

/*
 * Fetch the current stack pointer. Intended for fiber schedulers.
 */
get_stack_pointer : fn() -> rawptr : ---
/*
 * Fetch the current stack base pointer. Intended for fiber schedulers.
 */
get_stack_base_pointer : fn() -> rawptr : ---

/*
 * Jump to an address in executable memory.
 * Intended for fiber schedulers.
 */
jump_to_address : fn(base_pointer: rawptr) : ---

mem_copy : fn(dest, source: rawptr, len: usize) : ---
mem_copy_non_overlapping : fn(dest, source: rawptr, len: usize) : ---
mem_zero : fn(target: rawptr, len: usize) : ---

/*
 * Sets the location that the current function will return to once done.
 * Only valid for functions that don't have any return values.
 * Intended for fiber schedulers, in general this is wildly unsafe to use.
 */
set_return_address : fn(base_pointer: rawptr) : ---
