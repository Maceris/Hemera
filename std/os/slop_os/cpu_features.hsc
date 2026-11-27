package slop_os

/**
 * A CPU feature the kernel detects once at boot and reports to every program, so programs don't probe the hardware
 * themselves.
 *
 * Each architecture's features have their own names here; a program only ever sees its own architecture's features
 * set. The values are part of the system ABI, each one a feature's bit index in CpuFeatures, so new features are only
 * ever appended, never renumbered: x86-64's take 0 to 255, AArch64's 256 to 511, RISC-V's 512 to 767, and 768 to
 * 1023 are kept for another architecture. Only what the CPU can do is a feature; what firmware gives, like RISC-V's
 * debug triggers, is found by the calls that use it.
 */
CpuFeature :: enum #backed_by(u16) {
    // x86-64-v2
    X86Cx16     = 0, /**< CMPXCHG16B, the 16-byte compare and exchange. */
    X86LahfSahf = 1, /**< LAHF and SAHF in 64-bit mode. */
    X86Popcnt   = 2, /**< POPCNT, counting a register's set bits. */
    X86Sse3     = 3, /**< SSE3. */
    X86Ssse3    = 4, /**< Supplemental SSE3. */
    X86Sse41    = 5, /**< SSE4.1. */
    X86Sse42    = 6, /**< SSE4.2. */
    // x86-64-v3
    X86Avx   = 7, /**< AVX, with the operating system's support for saving its registers. */
    X86Avx2  = 8, /**< AVX2. */
    X86Bmi1  = 9, /**< The first bit manipulation instructions (ANDN, BEXTR, BLSI, TZCNT and others). */
    X86Bmi2  = 10, /**< The second bit manipulation instructions (BZHI, PDEP, PEXT, SHLX and others). */
    X86F16c  = 11, /**< F16C, conversions between half and single precision floats. */
    X86Fma   = 12, /**< FMA3, fused multiply-add. */
    X86Lzcnt = 13, /**< LZCNT, counting a register's leading zeros. */
    X86Movbe = 14, /**< MOVBE, moving with a byte swap. */
    X86Xsave = 15, /**< XSAVE and XRSTOR, saving and restoring extended register state. */
    // x86-64-v4
    X86Avx512F  = 16, /**< AVX-512 Foundation. */
    X86Avx512Bw = 17, /**< AVX-512 byte and word instructions. */
    X86Avx512Cd = 18, /**< AVX-512 conflict detection. */
    X86Avx512Dq = 19, /**< AVX-512 doubleword and quadword instructions. */
    X86Avx512Vl = 20, /**< AVX-512 vector length extensions, for 128- and 256-bit vectors. */
    // Cryptography
    X86AesNi      = 21, /**< AES-NI, the AES round instructions. */
    X86Pclmulqdq  = 22, /**< PCLMULQDQ, carry-less multiplication. */
    X86Vaes       = 23, /**< VAES, the AES instructions on 256- and 512-bit vectors. */
    X86Vpclmulqdq = 24, /**< VPCLMULQDQ, carry-less multiplication on 256- and 512-bit vectors. */
    X86Sha        = 25, /**< The SHA-1 and SHA-256 instructions. */
    // Random numbers
    X86Rdrand = 26, /**< RDRAND, random numbers from the hardware generator. */
    X86Rdseed = 27, /**< RDSEED, seeds straight from the hardware entropy source. */
    // System features, which only the kernel uses
    X86NoExecute       = 28, /**< The no-execute page bit. */
    X86Syscall         = 29, /**< SYSCALL and SYSRET. */
    X86Apic            = 30, /**< A local APIC. */
    X86X2Apic          = 31, /**< x2APIC mode of the local APIC. */
    X86InvariantTsc    = 32, /**< A time stamp counter that runs at a constant rate in every power state. */
    X86TscDeadline     = 33, /**< The local APIC timer's TSC-deadline mode. */
    X86Pcid            = 34, /**< Process-context identifiers, tagging TLB entries by address space. */
    X86Invpcid         = 35, /**< INVPCID, invalidating TLB entries by process-context identifier. */
    X86Smep            = 36, /**< Supervisor mode execution prevention. */
    X86Smap            = 37, /**< Supervisor mode access prevention. */
    X86FsGsBase        = 38, /**< RDFSBASE, WRFSBASE, RDGSBASE and WRGSBASE. */
    X86Pages1G         = 39, /**< 1 GiB pages. */
    X86Pat             = 40, /**< The page attribute table. */
    X86Xsavec          = 41, /**< XSAVEC, the compacted form of XSAVE. */
    X86Xsaveopt        = 42, /**< XSAVEOPT, XSAVE that skips unmodified state. */
    X86FiveLevelPaging = 43, /**< Five-level paging, 57-bit virtual addresses. */
    // Control-flow integrity (the SlopOS repository's decisions/0186)
    X86ShadowStack = 44, /**< CET shadow stacks (CET_SS). */
    X86Ibt = 45, /**< CET indirect branch tracking (CET_IBT). */

    // AArch64 (ID_AA64PFR0_EL1, ID_AA64ISAR0_EL1 and ID_AA64ISAR1_EL1): floating point and Advanced SIMD
    Aarch64Fp = 256, /**< Floating point. */
    Aarch64AdvSimd = 257, /**< Advanced SIMD (NEON). */
    // ARMv8.1-A
    Aarch64Atomics = 258, /**< The LSE atomic instructions. */
    Aarch64Rdm = 259, /**< The rounding doubling multiply-accumulate instructions (SQRDMLAH, SQRDMLSH). */
    // ARMv8.2-A and later
    Aarch64DotProduct = 260, /**< The dot product instructions (SDOT, UDOT). */
    Aarch64Fp16 = 261, /**< Half precision floating point arithmetic. */
    Aarch64Sve = 262, /**< The Scalable Vector Extension. */
    // Cryptography
    Aarch64Aes    = 263, /**< The AES instructions. */
    Aarch64Pmull  = 264, /**< PMULL, polynomial multiplication of 64-bit values. */
    Aarch64Sha1   = 265, /**< The SHA-1 instructions. */
    Aarch64Sha256 = 266, /**< The SHA-256 instructions. */
    Aarch64Sha512 = 267, /**< The SHA-512 instructions. */
    Aarch64Sha3   = 268, /**< The SHA-3 instructions. */
    Aarch64Crc32  = 269, /**< The CRC32 instructions. */
    // Random numbers
    Aarch64Rng = 270, /**< RNDR and RNDRRS, random numbers from the hardware generator. */
    // Control-flow integrity
    Aarch64PointerAuthentication = 271, /**< Pointer authentication. */
    Aarch64Bti = 272, /**< Branch target identification. */
    // System features, which only the kernel uses
    Aarch64Pan                = 273, /**< Privileged Access Never. */
    Aarch64Asid16             = 274, /**< 16-bit address space identifiers. */
    Aarch64Pages1G            = 275, /**< 1 GiB blocks with 4 KiB pages. */
    Aarch64HardwareAccessFlag = 276, /**< The access flag kept by the hardware (FEAT_HAFDBS). */
    // Control-flow integrity, numbered after the rest (the SlopOS repository's decisions/0186)
    Aarch64Gcs = 277, /**< The Guarded Control Stack (FEAT_GCS), a shadow stack. */

    // RISC-V, from the device tree's riscv,isa-extensions or riscv,isa: the single-letter extensions
    RiscvM = 512, /**< M, integer multiplication and division. */
    RiscvA = 513, /**< A, atomics: load-reserved and store-conditional, and the AMOs. */
    RiscvF = 514, /**< F, single precision floating point. */
    RiscvD = 515, /**< D, double precision floating point. */
    RiscvC = 516, /**< C, compressed instructions. */
    RiscvV = 517, /**< V, the vector extension, with vectors of at least 128 bits. */
    // Bit manipulation and the other instructions RVA23U64 has
    RiscvZba         = 518, /**< Zba, address generation: sh1add, sh2add, sh3add and their .uw forms. */
    RiscvZbb         = 519, /**< Zbb, basic bit manipulation: clz, ctz, cpop, min, max, rotations, rev8 and others. */
    RiscvZbs         = 520, /**< Zbs, single-bit instructions: bset, bclr, binv, bext. */
    RiscvZicond      = 521, /**< Zicond, conditional zeroing: czero.eqz and czero.nez. */
    RiscvZcb         = 522, /**< Zcb, more compressed instructions. */
    RiscvZfa         = 523, /**< Zfa, more floating point instructions: fli, fminm, fround and others. */
    RiscvZfhmin      = 524, /**< Zfhmin, half precision floating point loads, stores and conversions. */
    RiscvZicboz      = 525, /**< Zicboz, cbo.zero, zeroing a cache block. */
    RiscvZihintpause = 526, /**< Zihintpause, pause, a hint that a spin loop waits. */
    RiscvZawrs       = 527, /**< Zawrs, wrs.nto and wrs.sto, waiting on a reservation set. */
    RiscvZimop       = 528, /**< Zimop, the may-be-operations, which shadow stack instructions are where Zicfiss is off. */
    // Atomics past A
    RiscvZacas = 529, /**< Zacas, atomic compare and swap, amocas. */
    // Cryptography
    RiscvZbc    = 530, /**< Zbc, carry-less multiplication: clmul, clmulh, clmulr. */
    RiscvZbkb   = 531, /**< Zbkb, bit manipulation for cryptography: pack, brev8, zip, unzip. */
    RiscvZknd   = 532, /**< Zknd, the AES decryption instructions on scalar registers. */
    RiscvZkne   = 533, /**< Zkne, the AES encryption instructions on scalar registers. */
    RiscvZknh   = 534, /**< Zknh, the SHA-256 and SHA-512 instructions on scalar registers. */
    RiscvZvbb   = 535, /**< Zvbb, vector bit manipulation. */
    RiscvZvbc   = 536, /**< Zvbc, vector carry-less multiplication. */
    RiscvZvkned = 537, /**< Zvkned, the AES instructions on vectors. */
    RiscvZvknhb = 538, /**< Zvknhb, the SHA-256 and SHA-512 instructions on vectors. */
    RiscvZvkg   = 539, /**< Zvkg, GHASH on vectors, for AES-GCM. */
    RiscvZkt    = 540, /**< Zkt, instructions whose time doesn't depend on the data they're given. */
    // Random numbers
    RiscvZkr = 541, /**< Zkr, the seed CSR, seeds straight from the hardware entropy source. */
    // Control-flow integrity (the SlopOS repository's decisions/0186)
    RiscvZicfilp = 542, /**< Zicfilp, landing pads: lpad, and indirect branches that must land on one. */
    RiscvZicfiss = 543, /**< Zicfiss, shadow stacks. */
    // System features, which only the kernel uses
    RiscvSv48     = 544, /**< Sv48, four levels of page tables, 48-bit virtual addresses. */
    RiscvSv57     = 545, /**< Sv57, five levels of page tables, 57-bit virtual addresses. */
    RiscvSvpbmt   = 546, /**< Svpbmt, a page's memory type in its page table entry. */
    RiscvSvnapot  = 547, /**< Svnapot, naturally aligned 64 KiB pages made of 4 KiB entries. */
    RiscvSvinval  = 548, /**< Svinval, sfence.vma split into finer-grained instructions. */
    RiscvSvadu    = 549, /**< Svadu, the accessed and dirty bits kept by the hardware rather than faulting. */
    RiscvSstc     = 550, /**< Sstc, the supervisor's own timer compare register, stimecmp. */
    RiscvSscofpmf = 551, /**< Sscofpmf, counter overflow interrupts and mode filtering. */
    RiscvSsaia    = 552, /**< Ssaia, the supervisor's part of the Advanced Interrupt Architecture (the IMSIC). */
}

/**
 * A set of CpuFeature values, as the startup block reports it: 1024 bits, one for each possible feature, 256 for each
 * architecture.
 *
 * Its layout is part of the system ABI, so it stays 128 bytes.
 */
CpuFeatures :: struct {
    /** The set's bits: feature n is bit n % 64 of bits[n / 64], set when the CPU has it. */
    bits : u64[16],
}

#assert size_of(CpuFeatures) == 128

/**
 * Tell whether a set of features has one.
 *
 * @param features The set to look in, only read.
 * @param feature The feature to look for. A feature of another architecture than the one running is never set, nor
 *     one whose value is past the set's 1024 bits.
 * @return True if the set has the feature, false if it doesn't.
 */
has_feature :: fn(features : ptr[CpuFeatures], feature : CpuFeature) -> bool {
    index :: cast[usize](cast[u16](feature))
    if index / 64 >= features.bits.count {
        return false
    }
    return (features.bits[index / 64] >> cast[u64](index % 64)) & 1 == 1
}

/**
 * Add a feature to a set; adding one it already has changes nothing.
 *
 * @param features The set to add to, changed in place.
 * @param feature The feature to add; one whose value is past the set's 1024 bits isn't, and changes nothing.
 */
add_feature :: fn(features : ptr[mut CpuFeatures], feature : CpuFeature) {
    index :: cast[usize](cast[u16](feature))
    if index / 64 >= features.bits.count {
        return void
    }
    features.bits[index / 64] |= cast[u64](1) << cast[u64](index % 64)
}
