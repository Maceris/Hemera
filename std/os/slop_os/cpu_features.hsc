package slop_os

/**
 * A CPU feature the kernel detects once at boot and reports to every program, so programs don't probe the hardware
 * themselves.
 *
 * Each architecture's features have their own names here; a program only ever sees its own architecture's features
 * set. The values are part of the system ABI, each one a feature's bit index in CpuFeatures, so new features are only
 * ever appended, never renumbered: x86-64's take 0 to 63, AArch64's 64 to 127.
 */
CpuFeature :: enum #backed_by(u16) {
    // x86-64-v2
    X86Cx16 = 0, /**< CMPXCHG16B, the 16-byte compare and exchange. */
    X86LahfSahf = 1, /**< LAHF and SAHF in 64-bit mode. */
    X86Popcnt = 2, /**< POPCNT, counting a register's set bits. */
    X86Sse3 = 3, /**< SSE3. */
    X86Ssse3 = 4, /**< Supplemental SSE3. */
    X86Sse41 = 5, /**< SSE4.1. */
    X86Sse42 = 6, /**< SSE4.2. */
    // x86-64-v3
    X86Avx = 7, /**< AVX, with the operating system's support for saving its registers. */
    X86Avx2 = 8, /**< AVX2. */
    X86Bmi1 = 9, /**< The first bit manipulation instructions (ANDN, BEXTR, BLSI, TZCNT and others). */
    X86Bmi2 = 10, /**< The second bit manipulation instructions (BZHI, PDEP, PEXT, SHLX and others). */
    X86F16c = 11, /**< F16C, conversions between half and single precision floats. */
    X86Fma = 12, /**< FMA3, fused multiply-add. */
    X86Lzcnt = 13, /**< LZCNT, counting a register's leading zeros. */
    X86Movbe = 14, /**< MOVBE, moving with a byte swap. */
    X86Xsave = 15, /**< XSAVE and XRSTOR, saving and restoring extended register state. */
    // x86-64-v4
    X86Avx512F = 16, /**< AVX-512 Foundation. */
    X86Avx512Bw = 17, /**< AVX-512 byte and word instructions. */
    X86Avx512Cd = 18, /**< AVX-512 conflict detection. */
    X86Avx512Dq = 19, /**< AVX-512 doubleword and quadword instructions. */
    X86Avx512Vl = 20, /**< AVX-512 vector length extensions, for 128- and 256-bit vectors. */
    // Cryptography
    X86AesNi = 21, /**< AES-NI, the AES round instructions. */
    X86Pclmulqdq = 22, /**< PCLMULQDQ, carry-less multiplication. */
    X86Vaes = 23, /**< VAES, the AES instructions on 256- and 512-bit vectors. */
    X86Vpclmulqdq = 24, /**< VPCLMULQDQ, carry-less multiplication on 256- and 512-bit vectors. */
    X86Sha = 25, /**< The SHA-1 and SHA-256 instructions. */
    // Random numbers
    X86Rdrand = 26, /**< RDRAND, random numbers from the hardware generator. */
    X86Rdseed = 27, /**< RDSEED, seeds straight from the hardware entropy source. */
    // System features, which only the kernel uses
    X86NoExecute = 28, /**< The no-execute page bit. */
    X86Syscall = 29, /**< SYSCALL and SYSRET. */
    X86Apic = 30, /**< A local APIC. */
    X86X2Apic = 31, /**< x2APIC mode of the local APIC. */
    X86InvariantTsc = 32, /**< A time stamp counter that runs at a constant rate in every power state. */
    X86TscDeadline = 33, /**< The local APIC timer's TSC-deadline mode. */
    X86Pcid = 34, /**< Process-context identifiers, tagging TLB entries by address space. */
    X86Invpcid = 35, /**< INVPCID, invalidating TLB entries by process-context identifier. */
    X86Smep = 36, /**< Supervisor mode execution prevention. */
    X86Smap = 37, /**< Supervisor mode access prevention. */
    X86FsGsBase = 38, /**< RDFSBASE, WRFSBASE, RDGSBASE and WRGSBASE. */
    X86Pages1G = 39, /**< 1 GiB pages. */
    X86Pat = 40, /**< The page attribute table. */
    X86Xsavec = 41, /**< XSAVEC, the compacted form of XSAVE. */
    X86Xsaveopt = 42, /**< XSAVEOPT, XSAVE that skips unmodified state. */
    X86FiveLevelPaging = 43, /**< Five-level paging, 57-bit virtual addresses. */
    // Control-flow integrity (the SlopOS repository's decisions/0186)
    X86ShadowStack = 44, /**< CET shadow stacks (CET_SS). */
    X86Ibt = 45, /**< CET indirect branch tracking (CET_IBT). */

    // AArch64 (ID_AA64PFR0_EL1, ID_AA64ISAR0_EL1 and ID_AA64ISAR1_EL1): floating point and Advanced SIMD
    Aarch64Fp = 64, /**< Floating point. */
    Aarch64AdvSimd = 65, /**< Advanced SIMD (NEON). */
    // ARMv8.1-A
    Aarch64Atomics = 66, /**< The LSE atomic instructions. */
    Aarch64Rdm = 67, /**< The rounding doubling multiply-accumulate instructions (SQRDMLAH, SQRDMLSH). */
    // ARMv8.2-A and later
    Aarch64DotProduct = 68, /**< The dot product instructions (SDOT, UDOT). */
    Aarch64Fp16 = 69, /**< Half precision floating point arithmetic. */
    Aarch64Sve = 70, /**< The Scalable Vector Extension. */
    // Cryptography
    Aarch64Aes = 71, /**< The AES instructions. */
    Aarch64Pmull = 72, /**< PMULL, polynomial multiplication of 64-bit values. */
    Aarch64Sha1 = 73, /**< The SHA-1 instructions. */
    Aarch64Sha256 = 74, /**< The SHA-256 instructions. */
    Aarch64Sha512 = 75, /**< The SHA-512 instructions. */
    Aarch64Sha3 = 76, /**< The SHA-3 instructions. */
    Aarch64Crc32 = 77, /**< The CRC32 instructions. */
    // Random numbers
    Aarch64Rng = 78, /**< RNDR and RNDRRS, random numbers from the hardware generator. */
    // Control-flow integrity
    Aarch64PointerAuthentication = 79, /**< Pointer authentication. */
    Aarch64Bti = 80, /**< Branch target identification. */
    // System features, which only the kernel uses
    Aarch64Pan = 81, /**< Privileged Access Never. */
    Aarch64Asid16 = 82, /**< 16-bit address space identifiers. */
    Aarch64Pages1G = 83, /**< 1 GiB blocks with 4 KiB pages. */
    Aarch64HardwareAccessFlag = 84, /**< The access flag kept by the hardware (FEAT_HAFDBS). */
    // Control-flow integrity, numbered after the rest (the SlopOS repository's decisions/0186)
    Aarch64Gcs = 85, /**< The Guarded Control Stack (FEAT_GCS), a shadow stack. */
}

/**
 * A set of CpuFeature values, as the startup block reports it: 256 bits, one for each possible feature.
 *
 * Its layout is part of the system ABI, so it stays 32 bytes.
 */
CpuFeatures :: struct {
    /** The set's bits: feature n is bit n % 64 of bits[n / 64], set when the CPU has it. */
    bits : u64[4],
}

#assert size_of(CpuFeatures) == 32

/**
 * Tell whether a set of features has one.
 *
 * @param features The set to look in, only read.
 * @param feature The feature to look for. A feature of another architecture than the one running is never set.
 * @return True if the set has the feature, false if it doesn't.
 */
has_feature :: fn(features: ptr[CpuFeatures], feature: CpuFeature) -> bool {
    index :: cast[u16](feature)
    return (features.bits[index / 64] >> (index % 64)) & 1 == 1
}

/**
 * Add a feature to a set; adding one it already has changes nothing.
 *
 * @param features The set to add to, changed in place.
 * @param feature The feature to add.
 */
add_feature :: fn(features: ptr[mut CpuFeatures], feature: CpuFeature) {
    index :: cast[u16](feature)
    features.bits[index / 64] |= cast[u64](1) << (index % 64)
}
