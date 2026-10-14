package if_chain

#if TARGET_ARCH == .x86_64 {
    WORD_SIZE :: 8
}
#else_if TARGET_ARCH == .arm64 {
    WORD_SIZE :: 8
}
#else {
    WORD_SIZE :: 4
}
