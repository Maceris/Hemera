package riscv64

/*
 * Instructions for 64-bit RISC-V, for the runtime and for kernels and other freestanding code.
 *
 * Each function is one instruction, named after it, or a short sequence the runtime needs whole; those that take what
 * the instruction encodes, like a control and status register, take it as a compile-time argument. Most of the
 * supervisor's fault in user mode. Only exists when TARGET_ARCH == .riscv64, where intrinsics' platform.hsc imports it,
 * so use it from architecture-specific code only.
 */

// System calls, from user mode

/**
 * Make a Linux system call: ecall, the number in a7, up to six arguments in a0 to a5, the result in a0. Every other
 * register is kept.
 *
 * @param number The system call's number, in a7.
 * @param a The first argument, in a0; 0 when the call takes fewer.
 * @param b The second argument, in a1.
 * @param c The third argument, in a2.
 * @param d The fourth argument, in a3.
 * @param e The fifth argument, in a4.
 * @param f The sixth argument, in a5.
 * @return a0 after the call: -4095 to -1, as an i64, are errors (-errno), and anything else is the call's result.
 */
syscall : fn(number : u64, a : u64 = 0, b : u64 = 0, c : u64 = 0, d : u64 = 0, e : u64 = 0, f : u64 = 0) -> u64 : ---

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
clone_thread : fn(
    flags : u64,
    stack : rawptr,
    parent_tid : ptr[mut u32],
    child_tid : ptr[mut u32],
    entry : rawptr,
    argument : rawptr
) -> i64 : ---

/** What system_call gives: a0, a1 and a2 after the call, whose meaning is the kernel's. */
SystemCallResult :: struct {
    a0 : u64, /**< a0 after the call. */
    a1 : u64, /**< a1 after the call. */
    a2 : u64, /**< a2 after the call. */
}

/**
 * Make a system call that answers in up to three registers, like SlopOS's: ecall, the number in a7, up to six
 * arguments in a0 to a5, and a0, a1 and a2 after it. Every other register is kept. It doesn't use the stack.
 *
 * @param number The system call's number, in a7.
 * @param a The first argument, in a0; 0 when the call takes fewer.
 * @param b The second argument, in a1.
 * @param c The third argument, in a2.
 * @param d The fourth argument, in a3.
 * @param e The fifth argument, in a4.
 * @param f The sixth argument, in a5.
 * @return The three registers the kernel answered in.
 */
system_call : fn(
    number : u64,
    a : u64 = 0,
    b : u64 = 0,
    c : u64 = 0,
    d : u64 = 0,
    e : u64 = 0,
    f : u64 = 0
) -> SystemCallResult : ---

// Control and status registers

/**
 * The control and status registers the csr functions reach, each its 12-bit number, as in the instruction. Most are
 * the supervisor's, which fault in user mode; the counters, floating point and vector ones user mode reaches too,
 * where scounteren and sstatus allow. The entropy source is read with seed instead, since only a read and write
 * reaches it.
 */
Csr :: enum #backed_by(u16) {
    /** Floating point's accrued exception flags, the low 5 bits of fcsr. */
    FFLAGS = 0x001,
    /** Floating point's dynamic rounding mode, bits 5 to 7 of fcsr. */
    FRM = 0x002,
    /** Floating point's control and status: frm, then fflags. */
    FCSR = 0x003,
    /** The first vector element an interrupted vector instruction resumes at. */
    VSTART = 0x008,
    /** Whether a fixed-point vector instruction saturated. */
    VXSAT = 0x009,
    /** Fixed-point vector instructions' rounding mode. */
    VXRM = 0x00a,
    /** vxrm and vxsat together. */
    VCSR = 0x00f,
    /** The shadow stack pointer (Zicfiss), where the shadow stack is enabled for the current mode. */
    SSP = 0x011,
    /** The supervisor's status: interrupts enabled (SIE), the mode trapped from (SPP), SUM, MXR, and FS and VS. */
    SSTATUS = 0x100,
    /** Which interrupts are enabled, by bit: 1 software, 5 timer, 9 external, 13 counter overflow. */
    SIE = 0x104,
    /** Where traps go: the entry's address, its low 2 bits the mode, 0 for direct. */
    STVEC = 0x105,
    /** Which counters user mode can read: bit 0 cycle, 1 time, 2 instret. */
    SCOUNTEREN = 0x106,
    /** User mode's environment: fences, cache block instructions, landing pads and shadow stacks. */
    SENVCFG = 0x10a,
    /** A word for the trap entry: 0 in supervisor mode, the hart's TrapScratch in user mode. */
    SSCRATCH = 0x140,
    /** Where the trap was taken, and where sret returns to. */
    SEPC = 0x141,
    /** Why the trap was taken: CAUSE_INTERRUPT for an interrupt, plus a CAUSE_* code. */
    SCAUSE = 0x142,
    /** What the trap was about, like the faulting address or the instruction; 0 when nothing. */
    STVAL = 0x143,
    /** Which interrupts are pending, by bit, as sie numbers them. */
    SIP = 0x144,
    /** When the timer interrupt is next pending, compared with time (Sstc). */
    STIMECMP = 0x14d,
    /** Which of the indirect registers sireg reaches (Smcsrind and the AIA). */
    SISELECT = 0x150,
    /** The indirect register siselect selects. */
    SIREG = 0x151,
    /** The highest-priority pending external interrupt from the IMSIC (AIA); a write claims it. */
    STOPEI = 0x15c,
    /**
     * Address translation: the mode (8 for Sv39, 9 for Sv48, 10 for Sv57) in bits 60 to 63, the ASID in bits 44 to 59,
     * and the root table's page number.
     */
    SATP = 0x180,
    /** Cycles counted since some time in the past. */
    CYCLE = 0xc00,
    /** The real-time clock, at the frequency the device tree's timebase-frequency gives. */
    TIME = 0xc01,
    /** Instructions retired. */
    INSTRET = 0xc02,
    /** The vector length the last vsetvl set. */
    VL = 0xc20,
    /** The vector type the last vsetvl set. */
    VTYPE = 0xc21,
    /** The vector registers' length in bytes. */
    VLENB = 0xc22,
    /** The highest-priority pending interrupt, read only (AIA). */
    STOPI = 0xdb0,
}

// sstatus's bits.
/** Supervisor interrupts are enabled. */
SSTATUS_SIE : u64 : 1 << 1
/** Supervisor interrupts were enabled before the trap; sret sets SIE from it. */
SSTATUS_SPIE : u64 : 1 << 5
/** The trap came from supervisor mode, and sret returns to it; clear for user mode. */
SSTATUS_SPP : u64 : 1 << 8
/** Vector state, 2 bits: off, initial, clean or dirty; off makes vector instructions trap. */
SSTATUS_VS : u64 : 3 << 9
/** Floating point state, 2 bits: off, initial, clean or dirty; off makes floating point instructions trap. */
SSTATUS_FS : u64 : 3 << 13
/** The supervisor can read and write user pages; the trap entry clears it. */
SSTATUS_SUM : u64 : 1 << 18
/** Loads can read executable pages that aren't readable. */
SSTATUS_MXR : u64 : 1 << 19

// scause: an interrupt, with its number, or an exception, with its code.
/** Set in scause for an interrupt; clear for an exception. */
CAUSE_INTERRUPT : u64 : 1 << 63
/** An interrupt: another hart's IPI, through sip's bit 1. */
CAUSE_SUPERVISOR_SOFTWARE : u64 : 1
/** An interrupt: the timer reached stimecmp. */
CAUSE_SUPERVISOR_TIMER : u64 : 5
/** An interrupt: a device's, through the PLIC or the IMSIC. */
CAUSE_SUPERVISOR_EXTERNAL : u64 : 9
/** An exception: an instruction fetch that wasn't aligned. */
CAUSE_INSTRUCTION_MISALIGNED : u64 : 0
/** An exception: an instruction fetch the PMP or the bus refused. */
CAUSE_INSTRUCTION_ACCESS : u64 : 1
/** An exception: an instruction that isn't one, or isn't allowed here; stval may hold it. */
CAUSE_ILLEGAL_INSTRUCTION : u64 : 2
/** An exception: ebreak, like a stack check's trap. */
CAUSE_BREAKPOINT : u64 : 3
/** An exception: a load that wasn't aligned. */
CAUSE_LOAD_MISALIGNED : u64 : 4
/** An exception: a load the PMP or the bus refused. */
CAUSE_LOAD_ACCESS : u64 : 5
/** An exception: a store or atomic that wasn't aligned. */
CAUSE_STORE_MISALIGNED : u64 : 6
/** An exception: a store or atomic the PMP or the bus refused. */
CAUSE_STORE_ACCESS : u64 : 7
/** An exception: ecall from user mode, a system call. */
CAUSE_USER_ECALL : u64 : 8
/** An exception: ecall from supervisor mode. */
CAUSE_SUPERVISOR_ECALL : u64 : 9
/** An exception: an instruction fetch the page tables didn't allow; stval is the address. */
CAUSE_INSTRUCTION_PAGE_FAULT : u64 : 12
/** An exception: a load the page tables didn't allow; stval is the address. */
CAUSE_LOAD_PAGE_FAULT : u64 : 13
/** An exception: a store or atomic the page tables didn't allow; stval is the address. */
CAUSE_STORE_PAGE_FAULT : u64 : 15
/** An exception: a control flow check failed, a missing landing pad or a shadow stack mismatch; stval says which. */
CAUSE_SOFTWARE_CHECK : u64 : 18

/**
 * Read a control and status register (csrr).
 *
 * @tparam csr The register, as a compile-time value, since it's part of the instruction.
 * @param csr The register; a constant, like .SCAUSE.
 * @return Its 64 bits.
 */
csrr : fn[csr](csr : Csr) -> u64 : ---
/**
 * Set a control and status register (csrw). Changing satp needs an sfence_vma after it.
 *
 * @tparam csr The register, as a compile-time value, since it's part of the instruction.
 * @param csr The register; a constant, like .STVEC.
 * @param value Its new 64 bits; bits the register doesn't have are ignored.
 */
csrw : fn[csr](csr : Csr, value : u64) : ---
/**
 * Swap a control and status register's value for another (csrrw).
 *
 * @tparam csr The register, as a compile-time value, since it's part of the instruction.
 * @param csr The register; a constant, like .SSCRATCH.
 * @param value Its new 64 bits.
 * @return Its 64 bits before.
 */
csrrw : fn[csr](csr : Csr, value : u64) -> u64 : ---
/**
 * Set bits in a control and status register (csrrs), leaving the others.
 *
 * @tparam csr The register, as a compile-time value, since it's part of the instruction.
 * @param csr The register; a constant, like .SSTATUS.
 * @param bits The bits to set; 0 only reads it.
 * @return Its 64 bits before.
 */
csrrs : fn[csr](csr : Csr, bits : u64) -> u64 : ---
/**
 * Clear bits in a control and status register (csrrc), leaving the others.
 *
 * @tparam csr The register, as a compile-time value, since it's part of the instruction.
 * @param csr The register; a constant, like .SSTATUS.
 * @param bits The bits to clear; 0 only reads it.
 * @return Its 64 bits before.
 */
csrrc : fn[csr](csr : Csr, bits : u64) -> u64 : ---

/**
 * Read the entropy source, Zkr's seed, with csrrw, the only way to read it. Supervisor mode reaches it only where the
 * machine's firmware allows it (mseccfg.SSEED); elsewhere it's an illegal instruction.
 *
 * @return OPST in bits 30 and 31, and the entropy in bits 0 to 15 when OPST is SEED_ES16; otherwise none was ready,
 *     or with SEED_DEAD, the source has failed.
 */
seed : fn() -> u64 : ---
/** seed's OPST, bits 30 and 31: bits 0 to 15 are 16 bits of entropy. */
SEED_ES16 : u64 : 2 << 30
/** seed's OPST, bits 30 and 31: the source has failed for good. */
SEED_DEAD : u64 : 3 << 30

/**
 * Read the thread pointer, tp, which Hemera's code doesn't use otherwise.
 *
 * @return tp: in a kernel, its per-hart data, which a trap from user mode leaves it pointing at (TrapScratch); in
 *     user mode, its thread-local storage.
 */
read_tp : fn() -> rawptr : ---
/**
 * Set the thread pointer, tp.
 *
 * @param value What tp holds from now on, until a trap from user mode or return_to_user changes it.
 */
write_tp : fn(value : rawptr) : ---

// Fences and waiting

// fence's kinds of access, or'ed together.
/** Device input: reads from I/O. */
FENCE_INPUT : u8 : 8
/** Device output: writes to I/O. */
FENCE_OUTPUT : u8 : 4
/** Memory reads. */
FENCE_READ : u8 : 2
/** Memory writes. */
FENCE_WRITE : u8 : 1

/**
 * Order accesses (fence): those of predecessor's kinds before it are seen before those of successor's kinds after it.
 *
 * @tparam predecessor The kinds before, as a compile-time value, since they're part of the instruction.
 * @tparam successor The kinds after, as a compile-time value.
 * @param predecessor FENCE_* bits or'ed together, a constant from 1 to 15.
 * @param successor FENCE_* bits or'ed together, a constant from 1 to 15.
 */
fence : fn[predecessor, successor](predecessor : u8, successor : u8) : ---
/** Make this hart's instruction fetches see its own earlier stores (fence.i), after writing code. */
fence_i : fn() : ---
/**
 * Make translation see page table changes (sfence.vma) for one page in one address space, on this hart only; others
 * are reached by IPIs.
 *
 * @param address Any address in the page.
 * @param asid The address space's ID; global mappings aren't affected.
 */
sfence_vma : fn(address : rawptr, asid : u64) : ---
/**
 * Make translation see page table changes for one page in every address space, global mappings included
 * (sfence.vma address, zero), on this hart only.
 *
 * @param address Any address in the page.
 */
sfence_vma_address : fn(address : rawptr) : ---
/**
 * Make translation see page table changes for every page of one address space, except global mappings
 * (sfence.vma zero, asid), on this hart only.
 *
 * @param asid The address space's ID.
 */
sfence_vma_asid : fn(asid : u64) : ---
/** Make translation see every page table change (sfence.vma zero, zero), on this hart only. */
sfence_vma_all : fn() : ---
/** Wait for an interrupt (wfi); a pending one sstatus.SIE doesn't let be taken ends the wait too. */
wfi : fn() : ---
/** Tell the hart a spin loop is waiting (Zihintpause's pause), so it can save power or give way to another. */
pause : fn() : ---
/** Take a breakpoint exception (ebreak). */
ebreak : fn() : ---

// A thread's floating-point and vector registers, for a kernel switching threads

/**
 * Save the floating-point registers, f0 to f31, then fcsr, into an area: 264 bytes. They're reached with D's
 * instructions whatever the target's features, as a kernel is built without them; sstatus.FS has to be on (not Off).
 *
 * @param area Where they go, 8-byte aligned: f0 at 0 to f31 at 248, fcsr at 256.
 */
save_floating : fn(area : rawptr) : ---
/**
 * Load the floating-point registers and fcsr from an area save_floating wrote, or one laid out as it lays them out.
 * sstatus.FS has to be on.
 *
 * @param area Where they are, 8-byte aligned.
 */
restore_floating : fn(area : rawptr) : ---
/**
 * Save the vector registers, v0 to v31, vlenb bytes each, then vstart, vtype, vl and vcsr, 8 bytes each, into an area:
 * 32 * vlenb + 32 bytes. They're reached with V's instructions whatever the target's features; sstatus.VS has to be on.
 *
 * @param area Where they go, 16-byte aligned.
 */
save_vector : fn(area : rawptr) : ---
/**
 * Load the vector registers from an area save_vector wrote, or one laid out as it lays them out, then vtype and vl
 * with vsetvl, then vstart and vcsr. sstatus.VS has to be on.
 *
 * @param area Where they are, 16-byte aligned; a vtype with vill set leaves the vector unit unconfigured, as at reset.
 */
restore_vector : fn(area : rawptr) : ---

// The supervisor binary interface, to the machine's firmware, like OpenSBI

/** What sbi_call gives: the SBI's a0 and a1. */
SbiResult :: struct {
    /** 0 for success, or a negative SBI error: -1 failed, -2 not supported, -3 an invalid parameter, and on. */
    error : i64,
    /** The call's result, where it has one. */
    value : u64,
}

/**
 * Call the machine's firmware through the SBI (ecall from supervisor mode): the extension in a7, the function in a6,
 * up to six arguments in a0 to a5. Every register but a0 and a1 is kept.
 *
 * @param extension The extension's ID, like 0x48534d ("HSM") or 0x53525354 ("SRST").
 * @param function The function's ID within the extension.
 * @param a The first argument, in a0; 0 when it takes fewer.
 * @param b The second argument, in a1.
 * @param c The third argument, in a2.
 * @param d The fourth argument, in a3.
 * @param e The fifth argument, in a4.
 * @param f The sixth argument, in a5.
 * @return The error and the value, from a0 and a1.
 */
sbi_call : fn(
    extension : u64,
    function : u64,
    a : u64 = 0,
    b : u64 = 0,
    c : u64 = 0,
    d : u64 = 0,
    e : u64 = 0,
    f : u64 = 0
) -> SbiResult : ---

/**
 * Leave a bootloader for what it loaded, never to come back: satp set, every translation flushed, the stack pointer set
 * to stack, and entry jumped to with argument in a0 and a zero frame pointer and return address.
 *
 * @param satp The value for satp: the mode, ASID and root table, whose mappings have to include this code.
 * @param stack The top of the new stack, 16-byte aligned.
 * @param entry The address to jump to, under the new tables.
 * @param argument What entry gets in a0.
 */
enter : fn(satp : u64, stack : u64, entry : u64, argument : u64) #never_returns : ---

// Debugging

/**
 * Make a semihosting call, for code running under a debugger or QEMU's -semihosting: ebreak between the two
 * instructions that mark it as one. Without a debugger or semihosting enabled, it's a breakpoint exception.
 *
 * @param operation The operation, in a0. SYS_EXIT (0x18) ends QEMU, with parameter pointing at two words:
 *     0x20026 (ADP_Stopped_ApplicationExit) and the exit code.
 * @param parameter The operation's parameter, in a1, usually a pointer to its block of arguments.
 * @return a0 after the call, the operation's result.
 */
semihosting : fn(operation : u64, parameter : rawptr) -> u64 : ---

// Entry and return

/**
 * The interrupted code's registers, saved by the generated code of an entry function (#calling_convention(.entry),
 * whose address goes in stvec) and restored by return_to_user, from the lowest address up: 288 bytes. Its layout is
 * part of the calling convention version.
 */
RegisterFrame :: struct {
    /**
     * x0 to x31, by number: x[0] is 0, x[2] the stack pointer, x[4] tp, x[17] a system call's number and x[10] to x[15]
     * its arguments.
     */
    x : u64[32],
    /** Where the trap was taken, and where it returns to, sepc. */
    sepc : u64,
    /** The status it returns with, sstatus; SSTATUS_SPP says which mode. */
    sstatus : u64,
    /** Why it was taken, scause: CAUSE_INTERRUPT for an interrupt, plus a CAUSE_* code. */
    scause : u64,
    /** What it was about, stval, like the faulting address; 0 when nothing. */
    stval : u64,
}

/**
 * What sscratch points at while a hart runs in user mode: what a trap needs to leave user mode's stack. In supervisor
 * mode sscratch is 0. A kernel may make it the start of its per-hart data, since a trap from user mode leaves tp
 * pointing at it.
 */
TrapScratch :: struct {
    /** The top of the stack a trap from user mode runs on, 16-byte aligned, which the kernel sets for each thread. */
    kernel_stack : u64,
    /** Where the trap entry keeps user mode's stack pointer for a moment; nothing else uses it. */
    user_sp : u64,
    /**
     * Where ssp starts in the kernel, a trap from user mode putting it there: the top of the hart's kernel shadow stack
     * (Zicfiss), which the kernel sets; 0 when the kernel has none, and then a trap leaves ssp alone, as it may not
     * exist.
     */
    kernel_shadow_stack : u64,
    /**
     * User mode's ssp, with a kernel_shadow_stack: kept here by a trap from user mode, and put back by a return to it,
     * from the entry or return_to_user. The kernel sets it for the thread it returns to; unused without a
     * kernel_shadow_stack.
     */
    user_shadow_stack : u64,
}

/**
 * Restore every register from frame and return with sret to where the frame says, user mode. Interrupts must stay
 * disabled until then.
 *
 * @param frame The registers to return with, from an entry function or kept in a thread's structures. Its sstatus has
 *     SSTATUS_SPP and SSTATUS_SIE clear; SSTATUS_SPIE enables interrupts in user mode.
 * @param scratch What sscratch is set to, for the next trap from user mode, whose kernel_stack that trap runs on; the
 *     hart's own, kept as long as the kernel runs.
 */
return_to_user #never_returns : fn(frame : ptr[RegisterFrame], scratch : ptr[mut TrapScratch]) : ---
