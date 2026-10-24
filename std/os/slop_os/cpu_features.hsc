package slop_os

/*
 * The CPU features the kernel detects once at boot and reports to every program, so programs
 * don't probe the hardware themselves. Each architecture's features have their own names here;
 * the values are part of the system ABI, so new features are only ever appended.
 */
CpuFeature :: enum #backed_by(u16) {
    // x86-64-v2
    X86Cx16 = 0,
    X86LahfSahf = 1,
    X86Popcnt = 2,
    X86Sse3 = 3,
    X86Ssse3 = 4,
    X86Sse41 = 5,
    X86Sse42 = 6,
    // x86-64-v3
    X86Avx = 7,
    X86Avx2 = 8,
    X86Bmi1 = 9,
    X86Bmi2 = 10,
    X86F16c = 11,
    X86Fma = 12,
    X86Lzcnt = 13,
    X86Movbe = 14,
    X86Xsave = 15,
    // x86-64-v4
    X86Avx512F = 16,
    X86Avx512Bw = 17,
    X86Avx512Cd = 18,
    X86Avx512Dq = 19,
    X86Avx512Vl = 20,
    // Cryptography
    X86AesNi = 21,
    X86Pclmulqdq = 22,
    X86Vaes = 23,
    X86Vpclmulqdq = 24,
    X86Sha = 25,
    // Random numbers
    X86Rdrand = 26,
    X86Rdseed = 27,
    // System features, which only the kernel uses
    X86NoExecute = 28,
    X86Syscall = 29,
    X86Apic = 30,
    X86X2Apic = 31,
    X86InvariantTsc = 32,
    X86TscDeadline = 33,
    X86Pcid = 34,
    X86Invpcid = 35,
    X86Smep = 36,
    X86Smap = 37,
    X86FsGsBase = 38,
    X86Pages1G = 39,
    X86Pat = 40,
    X86Xsavec = 41,
    X86Xsaveopt = 42,
    X86FiveLevelPaging = 43,

    // AArch64 (ID_AA64PFR0_EL1, ID_AA64ISAR0_EL1 and ID_AA64ISAR1_EL1): floating point and Advanced SIMD
    Aarch64Fp = 64,
    Aarch64AdvSimd = 65,
    // ARMv8.1-A: the LSE atomics, and rounding doubling multiplies
    Aarch64Atomics = 66,
    Aarch64Rdm = 67,
    // ARMv8.2-A and later
    Aarch64DotProduct = 68,
    Aarch64Fp16 = 69,
    Aarch64Sve = 70,
    // Cryptography
    Aarch64Aes = 71,
    Aarch64Pmull = 72,
    Aarch64Sha1 = 73,
    Aarch64Sha256 = 74,
    Aarch64Sha512 = 75,
    Aarch64Sha3 = 76,
    Aarch64Crc32 = 77,
    // Random numbers
    Aarch64Rng = 78,
    // Control-flow integrity: pointer authentication and branch target identification
    Aarch64PointerAuthentication = 79,
    Aarch64Bti = 80,
    // System features, which only the kernel uses: Privileged Access Never, 16-bit ASIDs, and 1 GiB
    // blocks with 4 KiB pages
    Aarch64Pan = 81,
    Aarch64Asid16 = 82,
    Aarch64Pages1G = 83,
}

// A set of CpuFeature values.
CpuFeatures :: struct {
    bits : u64[4],
}

#assert size_of(CpuFeatures) == 32

has_feature :: fn(features: ptr[CpuFeatures], feature: CpuFeature) -> bool {
    index :: cast[u16](feature)
    return (features.bits[index / 64] >> (index % 64)) & 1 == 1
}

add_feature :: fn(features: ptr[mut CpuFeatures], feature: CpuFeature) {
    index :: cast[u16](feature)
    features.bits[index / 64] |= cast[u64](1) << (index % 64)
}
