package intrinsics

/*
 * Returns the location that the current function call will return to once
 * done.
 * Intended for fiber schedulers.
 */
get_return_address : fn() -> rawptr : ---
/*
 * Sets the location that the current function will return to once done.
 * Only valid for functions that don't have any return values.
 * Intended for fiber schedulers, in general this is wildly unsafe to use.
 */
set_return_address : fn(base_pointer: rawptr) : ---
