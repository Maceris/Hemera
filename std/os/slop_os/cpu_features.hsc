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
