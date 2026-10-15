package no_context

f #calling_convention(.entry) :: fn() {
    // An entry function has no context until it pushes one
    level := context.log_level
}
