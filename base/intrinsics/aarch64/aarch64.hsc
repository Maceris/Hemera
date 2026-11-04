package aarch64

/*
 * System instructions for AArch64, for the runtime and for kernels and other freestanding code.
 *
 * Each function is one instruction, named after it, or one of a family that takes what the
 * instruction encodes as a compile-time argument (a system register, a barrier's domain). Most of
 * them fault at EL0. Only exists when TARGET_ARCH == .arm64, where intrinsics' platform.hsc imports
 * it, so use it from architecture-specific code only.
 */

/**
 * The system registers read_system_register and write_system_register reach by name, each the
 * register's encoding: op0 << 14 | op1 << 11 | CRn << 7 | CRm << 3 | op2, as in the instruction.
 * Others are reached with read_system_register_encoded and write_system_register_encoded.
 */
SystemRegister :: enum #backed_by(u32) {
    /** Which CPU this is: implementer, part and revision. */
    MIDR_EL1 = 0xc000,
    /** This CPU's affinity levels, for telling CPUs apart. */
    MPIDR_EL1 = 0xc005,
    /** Processor features: which exception levels exist, and floating point, SIMD and GIC support. */
    ID_AA64PFR0_EL1 = 0xc020,
    /** Instruction set features: atomics, CRC, AES, SHA, and RNDR (bits 60 to 63). */
    ID_AA64ISAR0_EL1 = 0xc030,
    /** More instruction set features, like pointer authentication. */
    ID_AA64ISAR1_EL1 = 0xc031,
    /** Memory model features: physical address size, granules and ASID bits. */
    ID_AA64MMFR0_EL1 = 0xc038,
    /** More memory model features, like hardware access and dirty flags, and PAN. */
    ID_AA64MMFR1_EL1 = 0xc039,
    /** System control: the MMU (bit 0), alignment checks, caches, WXN. */
    SCTLR_EL1 = 0xc080,
    /** Whether floating point and SIMD trap (FPEN, bits 20 and 21). */
    CPACR_EL1 = 0xc082,
    /** The lower half's translation table, and its ASID. */
    TTBR0_EL1 = 0xc100,
    /** The upper half's translation table. */
    TTBR1_EL1 = 0xc101,
    /** Translation control: each half's size, granule, cacheability and shareability. */
    TCR_EL1 = 0xc102,
    /** The PSTATE an exception to EL1 saved, which eret restores. */
    SPSR_EL1 = 0xc200,
    /** Where an exception to EL1 returns to with eret. */
    ELR_EL1 = 0xc201,
    /** The EL0 stack pointer, as EL1 sees it. */
    SP_EL0 = 0xc208,
    /** Which stack pointer EL1 uses: 0 for SP_EL0, 1 for SP_EL1. */
    SPSel = 0xc210,
    /** The exception level, in bits 2 and 3. */
    CurrentEL = 0xc212,
    /** The interrupt masks: debug, SError, IRQ and FIQ (bits 9 to 6). */
    DAIF = 0xda11,
    /** GICv3: the priority mask. */
    ICC_PMR_EL1 = 0xc230,
    /** Floating point control: rounding mode, and which exceptions trap. */
    FPCR = 0xda20,
    /** Floating point status: the cumulative exception flags. */
    FPSR = 0xda21,
    /** Why the last exception was taken. */
    ESR_EL1 = 0xc290,
    /** The address that faulted. */
    FAR_EL1 = 0xc300,
    /** The result of an address translation instruction (at_*). */
    PAR_EL1 = 0xc3a0,
    /** The memory attributes translation table entries index. */
    MAIR_EL1 = 0xc510,
    /** The exception vector table (vector_table). */
    VBAR_EL1 = 0xc600,
    /** Which interrupts are pending. */
    ISR_EL1 = 0xc608,
    /** GICv3: deactivates an interrupt, when EOI and deactivation are split. */
    ICC_DIR_EL1 = 0xc659,
    /** GICv3: the running priority. */
    ICC_RPR_EL1 = 0xc65b,
    /** GICv3: sends a software-generated interrupt to other CPUs. */
    ICC_SGI1R_EL1 = 0xc65d,
    /** GICv3: acknowledges the highest-priority pending interrupt, giving its ID. */
    ICC_IAR1_EL1 = 0xc660,
    /** GICv3: ends an interrupt. */
    ICC_EOIR1_EL1 = 0xc661,
    /** GICv3: the binary point, splitting priorities into groups that preempt each other. */
    ICC_BPR1_EL1 = 0xc663,
    /** GICv3: CPU interface control, like whether EOI and deactivation are split. */
    ICC_CTLR_EL1 = 0xc664,
    /** GICv3: enables the system register interface. */
    ICC_SRE_EL1 = 0xc665,
    /** GICv3: enables group 1 interrupts. */
    ICC_IGRPEN1_EL1 = 0xc667,
    /** The current process's ID, for debuggers and tracing. */
    CONTEXTIDR_EL1 = 0xc681,
    /** Free for the kernel, like a per-CPU pointer. */
    TPIDR_EL1 = 0xc684,
    /** Free for user code, like its thread pointer. */
    TPIDR_EL0 = 0xde82,
    /** Read-only to user code. */
    TPIDRRO_EL0 = 0xde83,
    /** Which timer registers user code may read. */
    CNTKCTL_EL1 = 0xc708,
    /** The generic timer's frequency, in hertz. */
    CNTFRQ_EL0 = 0xdf00,
    /** The physical count. */
    CNTPCT_EL0 = 0xdf01,
    /** The virtual count. */
    CNTVCT_EL0 = 0xdf02,
    /** The physical timer's countdown: ticks until it fires. */
    CNTP_TVAL_EL0 = 0xdf10,
    /** The physical timer's control: enable, mask, and whether it fired. */
    CNTP_CTL_EL0 = 0xdf11,
    /** The physical timer's compare value: the count it fires at. */
    CNTP_CVAL_EL0 = 0xdf12,
    /** The virtual timer's countdown: ticks until it fires. */
    CNTV_TVAL_EL0 = 0xdf18,
    /** The virtual timer's control: enable, mask, and whether it fired. */
    CNTV_CTL_EL0 = 0xdf19,
    /** The virtual timer's compare value: the count it fires at. */
    CNTV_CVAL_EL0 = 0xdf1a,
    /** Debug control: single-step, breakpoints and watchpoints enabled for EL1 and EL0. */
    MDSCR_EL1 = 0x8012,
}

/**
 * The domains of dsb and dmb, each its CRm value: the full system (SY), or the inner shareable (ISH),
 * outer shareable (OSH) or non-shareable (NSH) domain, for all accesses or only stores (ST) or loads (LD).
 */
BarrierDomain :: enum #backed_by(u8) {
    OSHLD = 1, /**< The outer shareable domain, ordering loads before later accesses. */
    OSHST = 2, /**< The outer shareable domain, stores only. */
    OSH = 3, /**< The outer shareable domain, every access. */
    NSHLD = 5, /**< This CPU only, ordering loads before later accesses. */
    NSHST = 6, /**< This CPU only, stores only. */
    NSH = 7, /**< This CPU only, every access. */
    ISHLD = 9, /**< The inner shareable domain, the CPUs running one OS, ordering loads before later accesses. */
    ISHST = 10, /**< The inner shareable domain, stores only. */
    ISH = 11, /**< The inner shareable domain, every access: what TLB maintenance on every CPU needs. */
    LD = 13, /**< The full system, ordering loads before later accesses. */
    ST = 14, /**< The full system, stores only. */
    SY = 15, /**< The full system, every access, devices included. */
}

/**
 * The interrupted code's registers, saved by the generated code of entry functions
 * (#calling_convention(.entry), through vector_table) and restored by return_to_user, from the lowest
 * address up: 304 bytes. Its layout is part of the calling convention version.
 */
RegisterFrame :: struct {
    /** x0 to x30, by number: x[8] is a system call's number and x[0] to x[5] its arguments. */
    x : u64[31],
    /** The EL0 stack pointer, the user's. */
    sp_el0 : u64,
    /** Where the exception returns to, ELR_EL1. */
    elr : u64,
    /** The PSTATE it returns with, SPSR_EL1. */
    spsr : u64,
    /** Why it was taken, ESR_EL1; its class is bits 26 to 31 (ESR_CLASS_*). */
    esr : u64,
    /** The address that faulted, FAR_EL1, for the exceptions that have one; otherwise meaningless. */
    far : u64,
    /** Which of the vector table's 16 entries it came through: a VECTOR_* plus an ExceptionKind. */
    vector : u64,
    /** Unused, keeping the frame a multiple of 16 bytes, as the stack pointer has to be. */
    padding : u64,
}

// RegisterFrame.vector: where the exception came from, plus its ExceptionKind.
/** From EL1 running on SP_EL0. */
VECTOR_CURRENT_SP0 : u64 : 0
/** From EL1 running on SP_EL1. */
VECTOR_CURRENT_SPX : u64 : 4
/** From EL0 running AArch64: user code. */
VECTOR_LOWER_AARCH64 : u64 : 8
/** From EL0 running AArch32. */
VECTOR_LOWER_AARCH32 : u64 : 12

/** What kind of exception it was, added to a VECTOR_* in RegisterFrame.vector. */
ExceptionKind :: enum #backed_by(u8) {
    /** Caused by an instruction: a system call, an abort, a breakpoint; ESR_EL1 says which. */
    Synchronous = 0,
    /** An interrupt. */
    Irq = 1,
    /** A fast interrupt. */
    Fiq = 2,
    /** A system error, like an asynchronous external abort. */
    SError = 3,
}

// ESR_EL1's exception class (bits 26 to 31) for the exceptions a kernel sees most.
/** An svc instruction from AArch64: a system call. */
ESR_CLASS_SVC : u64 : 0x15
/** An instruction abort from a lower exception level, like user code jumping to unmapped memory. */
ESR_CLASS_INSTRUCTION_ABORT_LOWER : u64 : 0x20
/** An instruction abort at the same exception level. */
ESR_CLASS_INSTRUCTION_ABORT : u64 : 0x21
/** A data abort from a lower exception level, like a user page fault. */
ESR_CLASS_DATA_ABORT_LOWER : u64 : 0x24
/** A data abort at the same exception level. */
ESR_CLASS_DATA_ABORT : u64 : 0x25
/** A brk instruction from AArch64. */
ESR_CLASS_BRK : u64 : 0x3c

/** The 2 KiB-aligned vector table vector_table makes, for VBAR_EL1: 16 entries of 32 instructions. */
VectorTable :: struct {
    /** The entries' instructions, 32 for each in turn. */
    instructions : u32[512],
}

// daif_set and daif_clear's mask bits.
/** Masks FIQs. */
DAIF_FIQ : u8 : 1
/** Masks IRQs. */
DAIF_IRQ : u8 : 2
/** Masks SErrors. */
DAIF_SERROR : u8 : 4
/** Masks debug exceptions. */
DAIF_DEBUG : u8 : 8

// System calls, from user mode

/**
 * Make a system call with Linux's AArch64 convention: svc #0, the number in x8, up to six arguments in x0 to
 * x5, and the result in x0. It doesn't use the stack, so it works on a fiber's small one.
 *
 * @param number The system call's number, in x8.
 * @param a The first argument, in x0; 0 when the call takes fewer.
 * @param b The second argument, in x1.
 * @param c The third argument, in x2.
 * @param d The fourth argument, in x3.
 * @param e The fifth argument, in x4.
 * @param f The sixth argument, in x5.
 * @return x0 after the call: -4095 to -1, as an i64, are errors (-errno), and anything else is the call's result.
 */
syscall : fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> u64 : ---

/** What system_call gives: x0, x1 and x2 after the call, whose meaning is the kernel's. */
SystemCallResult :: struct {
    x0 : u64, /**< x0 after the call. */
    x1 : u64, /**< x1 after the call. */
    x2 : u64, /**< x2 after the call. */
}

/**
 * Make a system call that answers in up to three registers, like SlopOS's: svc #0, the number in x8, up to six
 * arguments in x0 to x5, and x0, x1 and x2 after it. Every other register is kept. It doesn't use the stack.
 *
 * @param number The system call's number, in x8.
 * @param a The first argument, in x0; 0 when the call takes fewer.
 * @param b The second argument, in x1.
 * @param c The third argument, in x2.
 * @param d The fourth argument, in x3.
 * @param e The fifth argument, in x4.
 * @param f The sixth argument, in x5.
 * @return The three registers the kernel answered in.
 */
system_call : fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> SystemCallResult : ---

/**
 * Start a thread with Linux's clone, which starts on stack by calling entry(argument), with the C convention.
 *
 * @param flags clone's flags. With CLONE_PARENT_SETTID and CLONE_CHILD_CLEARTID, the kernel stores the new thread's ID
 *     through parent_tid, and clears it through child_tid once the thread has exited.
 * @param stack The top of the new thread's stack, 16-byte aligned, which the caller allocated and keeps until the
 *     thread has exited.
 * @param parent_tid Where the kernel stores the new thread's ID before this returns.
 * @param child_tid Where the kernel writes 0 once the thread has exited, waking futex waiters there, so a joiner waits
 *     on it.
 * @param entry The function the thread runs, with the C convention; it must end the thread with the exit system call
 *     rather than return.
 * @param argument What entry is given as its one argument.
 * @return The new thread's ID, or -errno if clone failed, in which case no thread started.
 */
clone_thread : fn(flags: u64, stack: rawptr, parent_tid: ptr[mut u32], child_tid: ptr[mut u32], entry: rawptr,
    argument: rawptr) -> i64 : ---

// System registers

/**
 * Read a system register (mrs).
 *
 * @tparam system_register The register, as a compile-time value, since it's part of the instruction.
 * @param system_register The register; a constant, like .CNTVCT_EL0.
 * @return Its 64 bits.
 */
read_system_register : fn[system_register](system_register: SystemRegister) -> u64 : ---
/**
 * Set a system register (msr). Changes that affect the instructions after it need an isb.
 *
 * @tparam system_register The register, as a compile-time value, since it's part of the instruction.
 * @param system_register The register; a constant, like .VBAR_EL1.
 * @param value Its new 64 bits.
 */
write_system_register : fn[system_register](system_register: SystemRegister, value: u64) : ---
/**
 * Read a system register SystemRegister doesn't name, by its encoding's parts (mrs). Each part is a compile-time
 * constant, since it's part of the instruction.
 *
 * @tparam op0 The op0 field, as a compile-time value.
 * @tparam op1 The op1 field, as a compile-time value.
 * @tparam crn The CRn field, as a compile-time value.
 * @tparam crm The CRm field, as a compile-time value.
 * @tparam op2 The op2 field, as a compile-time value.
 * @param op0 The op0 field, 2 or 3 for system registers.
 * @param op1 The op1 field, 0 to 7.
 * @param crn The CRn field, 0 to 15.
 * @param crm The CRm field, 0 to 15.
 * @param op2 The op2 field, 0 to 7.
 * @return The register's 64 bits.
 */
read_system_register_encoded : fn[op0, op1, crn, crm, op2](op0: u8, op1: u8, crn: u8, crm: u8, op2: u8) -> u64 : ---
/**
 * Set a system register SystemRegister doesn't name, by its encoding's parts (msr). Each part is a compile-time
 * constant, since it's part of the instruction.
 *
 * @tparam op0 The op0 field, as a compile-time value.
 * @tparam op1 The op1 field, as a compile-time value.
 * @tparam crn The CRn field, as a compile-time value.
 * @tparam crm The CRm field, as a compile-time value.
 * @tparam op2 The op2 field, as a compile-time value.
 * @param op0 The op0 field, 2 or 3 for system registers.
 * @param op1 The op1 field, 0 to 7.
 * @param crn The CRn field, 0 to 15.
 * @param crm The CRm field, 0 to 15.
 * @param op2 The op2 field, 0 to 7.
 * @param value The register's new 64 bits.
 */
write_system_register_encoded : fn[op0, op1, crn, crm, op2](op0: u8, op1: u8, crn: u8, crm: u8, op2: u8, value: u64) : ---

/**
 * Mask exceptions: set the DAIF bits in mask, as msr daifset does.
 *
 * @tparam mask The bits, as a compile-time value, since they're part of the instruction.
 * @param mask DAIF_* bits or'ed together, a constant from 0 to 15; bits not in it are left as they are.
 */
daif_set : fn[mask](mask: u8) : ---
/**
 * Unmask exceptions: clear the DAIF bits in mask, as msr daifclr does.
 *
 * @tparam mask The bits, as a compile-time value, since they're part of the instruction.
 * @param mask DAIF_* bits or'ed together, a constant from 0 to 15; bits not in it are left as they are.
 */
daif_clear : fn[mask](mask: u8) : ---

// Barriers

/**
 * Make a data synchronization barrier (dsb): every access before it, in domain, completes before anything after it,
 * TLB and cache maintenance included.
 *
 * @tparam domain The domain, as a compile-time value, since it's part of the instruction.
 * @param domain Which CPUs and accesses it waits for; a constant, like .ISH.
 */
dsb : fn[domain](domain: BarrierDomain) : ---
/**
 * Make a data memory barrier (dmb): accesses before it, in domain, are seen before the ones after it.
 *
 * @tparam domain The domain, as a compile-time value, since it's part of the instruction.
 * @param domain Which CPUs and accesses it orders; a constant, like .ISH.
 */
dmb : fn[domain](domain: BarrierDomain) : ---
/**
 * Make an instruction synchronization barrier (isb): instructions after it are fetched again, seeing system register
 * changes.
 */
isb : fn() : ---

/**
 * Leave a bootloader for what it loaded, never to come back: the memory attributes, the translation control and both
 * tables loaded, the TLB flushed, the stack pointer set to stack, and entry branched to with argument in x0 and zero
 * frame and link registers.
 *
 * @param mair The value for MAIR_EL1.
 * @param tcr The value for TCR_EL1.
 * @param ttbr0 The value for TTBR0_EL1, the lower half's table, which has to map this code.
 * @param ttbr1 The value for TTBR1_EL1, the upper half's table.
 * @param stack The top of the new stack, 16-byte aligned.
 * @param entry The address to branch to, under the new tables.
 * @param argument What entry gets in x0.
 */
enter : fn(mair: u64, tcr: u64, ttbr0: u64, ttbr1: u64, stack: u64, entry: u64, argument: u64) #never_returns : ---

/**
 * Call the hypervisor (hvc #0), as PSCI does under one: function in w0 and its arguments in x1 to x3.
 *
 * @param function The function's ID, like a PSCI function's.
 * @param a The first argument, in x1; 0 when it takes fewer.
 * @param b The second argument, in x2.
 * @param c The third argument, in x3.
 * @return x0 as it comes back; for PSCI, 0 for success or a negative error code.
 */
hvc : fn(function: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0) -> u64 : ---
/**
 * Call the secure firmware (smc #0), as PSCI does without a hypervisor: function in w0 and its arguments in x1 to x3.
 *
 * @param function The function's ID, like a PSCI function's.
 * @param a The first argument, in x1; 0 when it takes fewer.
 * @param b The second argument, in x2.
 * @param c The third argument, in x3.
 * @return x0 as it comes back; for PSCI, 0 for success or a negative error code.
 */
smc : fn(function: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0) -> u64 : ---

// Waiting

/** Wait for an interrupt (wfi); a masked one ends the wait too, without being taken. */
wfi : fn() : ---
/** Wait for an event, or an interrupt (wfe); returns at once if the event register was already set. */
wfe : fn() : ---
/** Send an event to every CPU (sev), ending their wfe. */
sev : fn() : ---
/** Send an event to this CPU only (sevl), so its next wfe returns at once. */
sevl : fn() : ---

/*
 * TLB maintenance, each named after its instruction. The operand of those that take one is the page's
 * address shifted right by 12, with the ASID in bits 48 to 63, or the ASID alone in those bits for aside1.
 * The is forms reach every CPU in the inner shareable domain. A dsb(.ISH) and an isb finish them.
 */

/** Invalidate every EL1&0 TLB entry on this CPU (tlbi vmalle1). */
tlbi_vmalle1 : fn() : ---
/** Invalidate every EL1&0 TLB entry on every CPU in the inner shareable domain (tlbi vmalle1is). */
tlbi_vmalle1is : fn() : ---
/**
 * Invalidate one page's TLB entries for one ASID on this CPU (tlbi vae1).
 *
 * @param operand The page's address shifted right by 12, with the ASID in bits 48 to 63.
 */
tlbi_vae1 : fn(operand: u64) : ---
/**
 * Invalidate one page's TLB entries for one ASID on every CPU in the inner shareable domain (tlbi vae1is).
 *
 * @param operand The page's address shifted right by 12, with the ASID in bits 48 to 63.
 */
tlbi_vae1is : fn(operand: u64) : ---
/**
 * Invalidate one page's last-level TLB entry for one ASID on this CPU (tlbi vale1), leaving intermediate tables'
 * cached entries.
 *
 * @param operand The page's address shifted right by 12, with the ASID in bits 48 to 63.
 */
tlbi_vale1 : fn(operand: u64) : ---
/**
 * Invalidate one page's last-level TLB entry for one ASID on every CPU in the inner shareable domain (tlbi vale1is).
 *
 * @param operand The page's address shifted right by 12, with the ASID in bits 48 to 63.
 */
tlbi_vale1is : fn(operand: u64) : ---
/**
 * Invalidate one page's TLB entries for every ASID on this CPU (tlbi vaae1).
 *
 * @param operand The page's address shifted right by 12; the ASID bits are ignored.
 */
tlbi_vaae1 : fn(operand: u64) : ---
/**
 * Invalidate one page's TLB entries for every ASID on every CPU in the inner shareable domain (tlbi vaae1is).
 *
 * @param operand The page's address shifted right by 12; the ASID bits are ignored.
 */
tlbi_vaae1is : fn(operand: u64) : ---
/**
 * Invalidate every TLB entry of one ASID on this CPU (tlbi aside1).
 *
 * @param operand The ASID, in bits 48 to 63.
 */
tlbi_aside1 : fn(operand: u64) : ---
/**
 * Invalidate every TLB entry of one ASID on every CPU in the inner shareable domain (tlbi aside1is).
 *
 * @param operand The ASID, in bits 48 to 63.
 */
tlbi_aside1is : fn(operand: u64) : ---

// Cache maintenance, by the address of a byte in the line

/**
 * Clean data to the point of unification (dc cvau), as code written as data needs before ic_ivau.
 *
 * @param address Any byte of the cache line.
 */
dc_cvau : fn(address: rawptr) : ---
/**
 * Clean data to the point of coherency (dc cvac), as a device without coherent access needs before it reads.
 *
 * @param address Any byte of the cache line.
 */
dc_cvac : fn(address: rawptr) : ---
/**
 * Clean and invalidate data to the point of coherency (dc civac).
 *
 * @param address Any byte of the cache line.
 */
dc_civac : fn(address: rawptr) : ---
/**
 * Invalidate data to the point of coherency (dc ivac), losing anything not written back, as before reading what a
 * device without coherent access wrote.
 *
 * @param address Any byte of the cache line.
 */
dc_ivac : fn(address: rawptr) : ---
/**
 * Invalidate one line of instructions to the point of unification (ic ivau), after code is written.
 *
 * @param address Any byte of the line.
 */
ic_ivau : fn(address: rawptr) : ---
/** Invalidate all of this CPU's instruction cache to the point of unification (ic iallu). */
ic_iallu : fn() : ---
/** Invalidate every CPU's instruction cache in the inner shareable domain to the point of unification (ic ialluis). */
ic_ialluis : fn() : ---

// Address translation: translates address as a read or write at EL1 or EL0 would, into PAR_EL1.
/**
 * Translate an address as a read at EL1 would (at s1e1r), into PAR_EL1. Read PAR_EL1 after an isb.
 *
 * @param address Any virtual address, mapped or not; it isn't accessed, and a fault is reported in PAR_EL1, not taken.
 */
at_s1e1r : fn(address: rawptr) : ---
/**
 * Translate an address as a write at EL1 would (at s1e1w), into PAR_EL1. Read PAR_EL1 after an isb.
 *
 * @param address Any virtual address, mapped or not; it isn't written, and a fault is reported in PAR_EL1, not taken.
 */
at_s1e1w : fn(address: rawptr) : ---
/**
 * Translate an address as a read at EL0 would (at s1e0r), into PAR_EL1, as checking a user pointer does.
 *
 * @param address Any virtual address, like a user pointer; it isn't accessed, and a fault is reported in PAR_EL1, not
 *     taken.
 */
at_s1e0r : fn(address: rawptr) : ---
/**
 * Translate an address as a write at EL0 would (at s1e0w), into PAR_EL1, as checking a user pointer does.
 *
 * @param address Any virtual address, like a user pointer; it isn't written, and a fault is reported in PAR_EL1, not
 *     taken.
 */
at_s1e0w : fn(address: rawptr) : ---

/*
 * Randomness, only on CPUs that have it (FEAT_RNG: ID_AA64ISAR0_EL1 bits 60 to 63); elsewhere the
 * instructions are undefined.
 */
/**
 * Read a value from the CPU's random number generator (rndr).
 *
 * @return 64 random bits, or null when none was ready, in which case try again.
 */
rndr : fn() -> u64? : ---
/**
 * Read a value from the CPU's random number generator, reseeding it from its entropy source first (rndrrs).
 *
 * @return 64 random bits, or null when none was ready, in which case try again later.
 */
rndrrs : fn() -> u64? : ---

// Floating point and SIMD

/**
 * Save v0 to v31, then FPCR and FPSR, to area. Written as the instructions' encodings, so code built without floating
 * point, like a kernel, can save a thread's. It traps unless CPACR_EL1 lets EL1 use floating point.
 *
 * @param area Where they go: FP_SIMD_STATE_SIZE bytes, 16-byte aligned.
 */
save_fp_simd : fn(area: rawptr) : ---
/**
 * Restore v0 to v31, then FPCR and FPSR, from what save_fp_simd wrote. It traps unless CPACR_EL1 lets EL1 use
 * floating point.
 *
 * @param area What save_fp_simd saved: FP_SIMD_STATE_SIZE bytes, 16-byte aligned.
 */
restore_fp_simd : fn(area: rawptr) : ---
/** How many bytes save_fp_simd writes: 32 16-byte registers, then FPCR and FPSR, padded to 16 bytes. */
FP_SIMD_STATE_SIZE : usize : 528

// Debugging

/**
 * Take a breakpoint exception (brk).
 *
 * @tparam immediate The immediate, as a compile-time value, since it's part of the instruction.
 * @param immediate What the handler sees in ESR_EL1's low 16 bits; a constant.
 */
brk : fn[immediate](immediate: u16) : ---

/**
 * Make a semihosting call (hlt #0xf000), for code running under a debugger or QEMU's -semihosting.
 *
 * Without a debugger or semihosting enabled, the instruction faults.
 *
 * @param operation The operation, in x0. SYS_EXIT (0x18) ends QEMU, with parameter pointing at two words:
 *     0x20026 (ADP_Stopped_ApplicationExit) and the exit code.
 * @param parameter The operation's parameter, in x1, usually a pointer to its block of arguments.
 * @return x0 after the call, the operation's result.
 */
semihosting : fn(operation: u64, parameter: rawptr) -> u64 : ---

// Entry and return

/**
 * Give the vector table for handler, an entry function (#calling_convention(.entry)), for VBAR_EL1.
 *
 * Each of its 16 entries makes room for a RegisterFrame on the stack, saves x0 and x1, records which entry it is, and
 * enters handler's generated code, which saves the rest. handler may return: the frame is restored and the
 * exception returns with eret, to wherever the frame says then (docs/calling_convention.md, AArch64).
 *
 * @tparam handler The entry function, as a compile-time value; the table is generated once for each handler this is
 *     called with.
 * @param handler The entry function. It's also the generic parameter, so it must be known at compile time.
 * @return The table, 2 KiB-aligned, read-only, in the program for its whole run.
 */
vector_table : fn[handler](handler: (fn(frame: ptr[mut RegisterFrame]))) -> ptr[VectorTable] : ---

/**
 * Set SP_EL1, the stack exceptions taken to EL1 run on, while running on SP_EL0 (PSTATE.SP clear), as code a
 * bootloader entered that way does: msr spsel, #1, then mov sp, then msr spsel, #0, touching no stack.
 *
 * @param stack The top of the exceptions' stack, 16-byte aligned. On SP_EL1 this would move the caller's own stack,
 *     so it isn't for that.
 */
write_sp_el1 : fn(stack: rawptr) : ---

/**
 * Restore every register from frame and return with eret to where the frame says, usually user mode. Interrupts must
 * stay masked until then.
 *
 * @param frame The registers to return with, from an entry function or kept in a thread's structures.
 * @param kernel_stack Where SP_EL1 is put for the next exception (selected first, so this works from code running on
 *     SP_EL0 too): AArch64 has no TSS, so the stack pointer at eret is where the next exception's frame goes.
 */
return_to_user #never_returns : fn(frame: ptr[RegisterFrame], kernel_stack: rawptr) : ---
