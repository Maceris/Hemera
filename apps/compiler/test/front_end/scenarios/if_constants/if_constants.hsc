package if_constants

KERNEL :: true

#if KERNEL && TARGET_ARCH == .x86_64 {
    IN_KERNEL :: 1
}
#else {
    IN_KERNEL :: 2
}

// The tests build for Windows, so this is never declared, and nothing uses it
#if OS == .Linux {
    ONLY_LINUX :: 1
}

USES :: IN_KERNEL
