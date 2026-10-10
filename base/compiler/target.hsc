package compiler

Architecture :: enum {
    arm,
    arm64,
    x86,
    x86_64,
}

OperatingSystem :: enum {
    Linux,
    Mac,
    // Freestanding, with no operating system underneath, like a kernel.
    None,
    // lol. lmao, even.
    SlopOS,
    // A UEFI application, like a bootloader, using boot services instead of an operating system.
    UEFI,
    Windows,
}
