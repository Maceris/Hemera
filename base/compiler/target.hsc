package compiler

/** The processor architectures a target can be compiled for, which TARGET_ARCH is one of. */
Architecture :: enum {
    /** 32-bit ARM. */
    arm,
    /** 64-bit ARM, AArch64. */
    arm64,
    /** 64-bit RISC-V. */
    riscv64,
    /** 32-bit x86. */
    x86,
    /** 64-bit x86, x86-64. */
    x86_64,
}

/** The operating systems a target can be compiled for, which OS is one of. */
OperatingSystem :: enum {
    /** Linux, whose programs Hemera starts without the C library unless they call C. */
    Linux,
    /** macOS. */
    Mac,
    /** Freestanding, with no operating system underneath, like a kernel. */
    None,
    /** lol. lmao, even. */
    SlopOS,
    /** A UEFI application, like a bootloader, using boot services instead of an operating system. */
    UEFI,
    /** Windows. */
    Windows,
}
