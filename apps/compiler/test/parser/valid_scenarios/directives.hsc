package valid_scenarios

@Deprecated
old_function :: fn() {}

CarrierBlock :: struct #align(64) {
    stack_limit : rawptr,
}

Header :: struct #packed #align(8) {
    magic : u32,
}

Suit :: enum #backed_by(u8) {
    Clubs,
    Hearts,
}

timer_interrupt #calling_convention(.interrupt) :: fn(frame: ptr[x86_64.InterruptFrame]) {}

public_entry #export :: fn() {}

thread_create :: fn(function: ThreadFunction, data #escaping : any? = null, location := #caller_location) {
    is_even(#run square(13))
    log(#file_path)
}
