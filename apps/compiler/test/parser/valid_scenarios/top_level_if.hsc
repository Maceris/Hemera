package valid_scenarios

// A top-level #if before any definition can hold definitions
#if TARGET_ARCH == .x86_64 {
    WORD_SIZE :: 8
    import x86_64 from "base/intrinsics"
}
#else_if TARGET_ARCH == .arm64 {
    WORD_SIZE :: 8
}
#else {
    WORD_SIZE :: 4
}

VALUE :: 1

// And one after definitions can hold imports
#if OS == .Windows {
    import windows from "std/os"
    HANDLE :: distinct alias u64
}
