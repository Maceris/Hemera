package call_without_context

helper :: fn() {
}

f #calling_convention(.entry) :: fn() {
    // Only intrinsics can be called until a context is pushed
    helper()
}
