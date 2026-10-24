package aarch64

/*
 * System instructions for AArch64, for the runtime and for kernels and other freestanding code.
 *
 * Each function is one instruction, named after it, or one of a family that takes what the
 * instruction encodes as a compile-time argument (a system register, a barrier's domain). Most of
 * them fault at EL0. Only exists when TARGET_ARCH == .arm64, where intrinsics' platform.hsc imports
 * it, so use it from architecture-specific code only.
 */

/*
 * The system registers read_system_register and write_system_register reach by name, each the
 * register's encoding: op0 << 14 | op1 << 11 | CRn << 7 | CRm << 3 | op2, as in the instruction.
 * Others are reached with read_system_register_encoded and write_system_register_encoded.
 */
SystemRegister :: enum #backed_by(u32) {
    // Which CPU this is: implementer, part and revision
    MIDR_EL1 = 0xc000,
    // This CPU's affinity levels, for telling CPUs apart
    MPIDR_EL1 = 0xc005,
    ID_AA64PFR0_EL1 = 0xc020,
    // Instruction set features: atomics, CRC, AES, SHA, and RNDR (bits 60 to 63)
    ID_AA64ISAR0_EL1 = 0xc030,
    ID_AA64ISAR1_EL1 = 0xc031,
    // Memory model features: physical address size, granules and ASID bits
    ID_AA64MMFR0_EL1 = 0xc038,
    ID_AA64MMFR1_EL1 = 0xc039,
    // System control: the MMU (bit 0), alignment checks, caches, WXN
    SCTLR_EL1 = 0xc080,
    // Whether floating point and SIMD trap (FPEN, bits 20 and 21)
    CPACR_EL1 = 0xc082,
    // The lower half's translation table, and its ASID
    TTBR0_EL1 = 0xc100,
    // The upper half's translation table
    TTBR1_EL1 = 0xc101,
    // Translation control: each half's size, granule, cacheability and shareability
    TCR_EL1 = 0xc102,
    SPSR_EL1 = 0xc200,
    ELR_EL1 = 0xc201,
    SP_EL0 = 0xc208,
    SPSel = 0xc210,
    // The exception level, in bits 2 and 3
    CurrentEL = 0xc212,
    // The interrupt masks: debug, SError, IRQ and FIQ (bits 9 to 6)
    DAIF = 0xda11,
    // GICv3: the priority mask
    ICC_PMR_EL1 = 0xc230,
    FPCR = 0xda20,
    FPSR = 0xda21,
    // Why the last exception was taken
    ESR_EL1 = 0xc290,
    // The address that faulted
    FAR_EL1 = 0xc300,
    // The result of an address translation instruction (at_*)
    PAR_EL1 = 0xc3a0,
    // The memory attributes translation table entries index
    MAIR_EL1 = 0xc510,
    // The exception vector table (vector_table)
    VBAR_EL1 = 0xc600,
    // Which interrupts are pending
    ISR_EL1 = 0xc608,
    ICC_DIR_EL1 = 0xc659,
    ICC_RPR_EL1 = 0xc65b,
    // GICv3: sends a software-generated interrupt to other CPUs
    ICC_SGI1R_EL1 = 0xc65d,
    // GICv3: acknowledges the highest-priority pending interrupt, giving its ID
    ICC_IAR1_EL1 = 0xc660,
    // GICv3: ends an interrupt
    ICC_EOIR1_EL1 = 0xc661,
    ICC_BPR1_EL1 = 0xc663,
    ICC_CTLR_EL1 = 0xc664,
    // GICv3: enables the system register interface
    ICC_SRE_EL1 = 0xc665,
    // GICv3: enables group 1 interrupts
    ICC_IGRPEN1_EL1 = 0xc667,
    CONTEXTIDR_EL1 = 0xc681,
    // Free for the kernel, like a per-CPU pointer
    TPIDR_EL1 = 0xc684,
    // Free for user code, like its thread pointer
    TPIDR_EL0 = 0xde82,
    // Read-only to user code
    TPIDRRO_EL0 = 0xde83,
    // Which timer registers user code may read
    CNTKCTL_EL1 = 0xc708,
    // The generic timer's frequency
    CNTFRQ_EL0 = 0xdf00,
    // The physical count
    CNTPCT_EL0 = 0xdf01,
    // The virtual count
    CNTVCT_EL0 = 0xdf02,
    CNTP_TVAL_EL0 = 0xdf10,
    CNTP_CTL_EL0 = 0xdf11,
    CNTP_CVAL_EL0 = 0xdf12,
    CNTV_TVAL_EL0 = 0xdf18,
    CNTV_CTL_EL0 = 0xdf19,
    CNTV_CVAL_EL0 = 0xdf1a,
    MDSCR_EL1 = 0x8012,
}

/*
 * The domains of dsb and dmb, each its CRm value: the full system (SY), or the inner shareable (ISH),
 * outer shareable (OSH) or non-shareable (NSH) domain, for all accesses or only stores (ST) or loads (LD).
 */
BarrierDomain :: enum #backed_by(u8) {
    OSHLD = 1,
    OSHST = 2,
    OSH = 3,
    NSHLD = 5,
    NSHST = 6,
    NSH = 7,
    ISHLD = 9,
    ISHST = 10,
    ISH = 11,
    LD = 13,
    ST = 14,
    SY = 15,
}

/*
 * The interrupted code's registers, saved by the generated code of entry functions
 * (#calling_convention(.entry), through vector_table) and restored by return_to_user, from the lowest
 * address up. Its layout is part of the calling convention version.
 */
RegisterFrame :: struct {
    x : u64[31],
    sp_el0 : u64,
    // Where the exception returns to, and the PSTATE it returns with
    elr : u64,
    spsr : u64,
    // Why it was taken, and the address that faulted, for the exceptions that have one
    esr : u64,
    far : u64,
    // Which of the vector table's 16 entries it came through: a VECTOR_* plus an ExceptionKind
    vector : u64,
    padding : u64,
}

// RegisterFrame.vector: where the exception came from, plus its ExceptionKind.
VECTOR_CURRENT_SP0 : u64 : 0
VECTOR_CURRENT_SPX : u64 : 4
VECTOR_LOWER_AARCH64 : u64 : 8
VECTOR_LOWER_AARCH32 : u64 : 12

ExceptionKind :: enum #backed_by(u8) {
    Synchronous = 0,
    Irq = 1,
    Fiq = 2,
    SError = 3,
}

// ESR_EL1's exception class (bits 26 to 31) for the exceptions a kernel sees most.
ESR_CLASS_SVC : u64 : 0x15
ESR_CLASS_INSTRUCTION_ABORT_LOWER : u64 : 0x20
ESR_CLASS_INSTRUCTION_ABORT : u64 : 0x21
ESR_CLASS_DATA_ABORT_LOWER : u64 : 0x24
ESR_CLASS_DATA_ABORT : u64 : 0x25
ESR_CLASS_BRK : u64 : 0x3c

// The 2 KiB-aligned vector table vector_table makes, for VBAR_EL1: 16 entries of 32 instructions.
VectorTable :: struct {
    instructions : u32[512],
}

// daif_set and daif_clear's mask bits.
DAIF_FIQ : u8 : 1
DAIF_IRQ : u8 : 2
DAIF_SERROR : u8 : 4
DAIF_DEBUG : u8 : 8

// System calls, from user mode

/*
 * A system call with Linux's AArch64 convention: svc #0, the number in x8, up to six arguments in x0 to
 * x5, and the result in x0, where -4095 to -1 are errors (-errno). It doesn't use the stack, so it works on
 * a fiber's small one.
 */
syscall : fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> u64 : ---

/*
 * Linux's clone for a new thread, which starts on stack (its top) by calling entry(argument), with the C
 * convention; entry must end the thread with the exit system call rather than return. The kernel stores
 * the new thread's ID through parent_tid before this returns, and clears it through child_tid, waking futex
 * waiters there, once the thread has exited (with CLONE_PARENT_SETTID and CLONE_CHILD_CLEARTID in flags).
 * Returns the new thread's ID, or -errno.
 */
clone_thread : fn(flags: u64, stack: rawptr, parent_tid: ptr[mut u32], child_tid: ptr[mut u32], entry: rawptr,
    argument: rawptr) -> i64 : ---

// System registers

// mrs: a system register's value.
read_system_register : fn[system_register](system_register: SystemRegister) -> u64 : ---
// msr: sets a system register. Changes that affect the instructions after it need an isb.
write_system_register : fn[system_register](system_register: SystemRegister, value: u64) : ---
// The same for a register SystemRegister doesn't name, by its encoding's parts.
read_system_register_encoded : fn[op0, op1, crn, crm, op2](op0: u8, op1: u8, crn: u8, crm: u8, op2: u8) -> u64 : ---
write_system_register_encoded : fn[op0, op1, crn, crm, op2](op0: u8, op1: u8, crn: u8, crm: u8, op2: u8, value: u64) : ---

// Interrupt masks: set or clear the DAIF bits in mask (DAIF_*), as msr daifset and daifclr do.
daif_set : fn[mask](mask: u8) : ---
daif_clear : fn[mask](mask: u8) : ---

// Barriers

// Data synchronization barrier: every access before it, in domain, completes before anything after it.
dsb : fn[domain](domain: BarrierDomain) : ---
// Data memory barrier: accesses before it, in domain, are seen before the ones after it.
dmb : fn[domain](domain: BarrierDomain) : ---
// Instruction synchronization barrier: instructions after it are fetched again, seeing system register changes.
isb : fn() : ---

// Waiting

// Wait for an interrupt.
wfi : fn() : ---
// Wait for an event, or an interrupt.
wfe : fn() : ---
// Send an event to every CPU, or only this one (sevl).
sev : fn() : ---
sevl : fn() : ---

/*
 * TLB maintenance, each named after its instruction. The operand of those that take one is the page's
 * address shifted right by 12, with the ASID in bits 48 to 63, or the ASID alone in those bits for aside1.
 * The is forms reach every CPU in the inner shareable domain. A dsb(.ISH) and an isb finish them.
 */

tlbi_vmalle1 : fn() : ---
tlbi_vmalle1is : fn() : ---
tlbi_vae1 : fn(operand: u64) : ---
tlbi_vae1is : fn(operand: u64) : ---
// Only the last level's entry, leaving intermediate tables' cached entries
tlbi_vale1 : fn(operand: u64) : ---
tlbi_vale1is : fn(operand: u64) : ---
// Every ASID's entry for the page
tlbi_vaae1 : fn(operand: u64) : ---
tlbi_vaae1is : fn(operand: u64) : ---
tlbi_aside1 : fn(operand: u64) : ---
tlbi_aside1is : fn(operand: u64) : ---

// Cache maintenance, by the address of a byte in the line

// Clean data to the point of unification, as code written as data needs before ic_ivau.
dc_cvau : fn(address: rawptr) : ---
// Clean data to the point of coherency, as a device without coherent access needs.
dc_cvac : fn(address: rawptr) : ---
// Clean and invalidate data to the point of coherency.
dc_civac : fn(address: rawptr) : ---
// Invalidate data to the point of coherency, losing anything not written back.
dc_ivac : fn(address: rawptr) : ---
// Invalidate instructions to the point of unification: one line, all of this CPU's (iallu), or every CPU's (ialluis).
ic_ivau : fn(address: rawptr) : ---
ic_iallu : fn() : ---
ic_ialluis : fn() : ---

// Address translation: translates address as a read or write at EL1 or EL0 would, into PAR_EL1.
at_s1e1r : fn(address: rawptr) : ---
at_s1e1w : fn(address: rawptr) : ---
at_s1e0r : fn(address: rawptr) : ---
at_s1e0w : fn(address: rawptr) : ---

/*
 * Randomness: a value from the CPU's random number generator (rndr), or from its entropy source, reseeding
 * first (rndrrs), or null when none was ready. Only on CPUs that have them (FEAT_RNG: ID_AA64ISAR0_EL1 bits
 * 60 to 63).
 */
rndr : fn() -> u64? : ---
rndrrs : fn() -> u64? : ---

// Debugging

// A breakpoint exception, with immediate in ESR_EL1's low 16 bits.
brk : fn[immediate](immediate: u16) : ---

/*
 * A semihosting call (hlt #0xf000), for code running under a debugger or QEMU's -semihosting: operation in
 * x0, parameter in x1, and the result in x0. SYS_EXIT (0x18) ends QEMU, with parameter pointing at two
 * words: 0x20026 (ADP_Stopped_ApplicationExit) and the exit code.
 */
semihosting : fn(operation: u64, parameter: rawptr) -> u64 : ---

// Entry and return

/*
 * The vector table for handler, an entry function (#calling_convention(.entry)), for VBAR_EL1: each of its
 * 16 entries makes room for a RegisterFrame on the stack, saves x0 and x1, records which entry it is, and
 * enters handler's generated code, which saves the rest. handler may return: the frame is restored and the
 * exception returns with eret, to wherever the frame says then.
 *
 * handler is also a generic parameter, so it must be known at compile time, and the table is generated once
 * for each handler this is called with.
 */
vector_table : fn[handler](handler: (fn(frame: ptr[mut RegisterFrame]))) -> ptr[VectorTable] : ---

/*
 * Restore every register from frame, with the stack pointer at kernel_stack for the next exception, and
 * return with eret to where the frame says, usually user mode. Interrupts must stay masked until then.
 */
return_to_user #never_returns : fn(frame: ptr[RegisterFrame], kernel_stack: rawptr) : ---
