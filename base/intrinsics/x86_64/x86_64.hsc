package x86_64

/*
 * Privileged and system instructions for x86-64, for kernels and other freestanding code.
 *
 * Each function is one instruction, named after it. Most of them fault outside ring 0.
 * Only exists when TARGET_ARCH == .x86_64, where intrinsics' platform.hsc imports it,
 * so use it from architecture-specific code only.
 */

/** The operand of lgdt and lidt: where a descriptor table is and how large. */
DescriptorTablePointer :: struct #packed {
    /** Size of the table in bytes, minus one, so a table of n 8-byte descriptors has 8n - 1. */
    limit : u16,
    /** The table's linear (virtual) address. */
    base : u64,
}

/**
 * What the CPU pushes when entering an interrupt function (#calling_convention(.interrupt)),
 * from the lowest address up.
 */
InterruptFrame :: struct {
    /** Where the interrupted code continues: the faulting instruction for a fault, the next one for a trap. */
    rip : u64,
    /** The interrupted code's code segment selector; its low two bits are the privilege level it ran at. */
    cs : u64,
    /** The interrupted code's flags register. */
    rflags : u64,
    /** The interrupted code's stack pointer. */
    rsp : u64,
    /** The interrupted code's stack segment selector. */
    ss : u64,
}

/**
 * The interrupted code's registers, saved by the generated code of entry functions
 * (#calling_convention(.entry) and .syscall_entry) and restored by return_to_user, from the lowest address up.
 * Its layout is part of the calling convention version (docs/calling_convention.md, Entry Functions).
 *
 * The frame is the entry function's to change: one that returns, or a return_to_user with it, resumes with whatever
 * it holds then.
 */
RegisterFrame :: struct {
    r15 : u64, /**< The interrupted code's r15. */
    r14 : u64, /**< The interrupted code's r14. */
    r13 : u64, /**< The interrupted code's r13. */
    r12 : u64, /**< The interrupted code's r12. */
    r11 : u64, /**< The interrupted code's r11; after a SYSCALL, its rflags, which the CPU put there. */
    r10 : u64, /**< The interrupted code's r10, a system call's fourth argument. */
    r9 : u64, /**< The interrupted code's r9. */
    r8 : u64, /**< The interrupted code's r8. */
    rbp : u64, /**< The interrupted code's rbp. */
    rdi : u64, /**< The interrupted code's rdi, a system call's first argument. */
    rsi : u64, /**< The interrupted code's rsi. */
    rdx : u64, /**< The interrupted code's rdx. */
    rcx : u64, /**< The interrupted code's rcx; after a SYSCALL, its rip, which the CPU put there. */
    rbx : u64, /**< The interrupted code's rbx. */
    rax : u64, /**< The interrupted code's rax, a system call's number. */
    /** The vector that arrived, 0 to 255, or SYSCALL_VECTOR for a SYSCALL. */
    vector : u64,
    /** The CPU's error code, or 0 for vectors without one. */
    error_code : u64,
    /*
     * The rest are pushed by the CPU, or filled in by a .syscall_entry function's generated code, as
     * InterruptFrame's fields are.
     */
    /** Where the interrupted code continues. */
    rip : u64,
    /** The interrupted code's code segment selector; its low two bits are the privilege level it ran at. */
    cs : u64,
    /** The interrupted code's flags register. */
    rflags : u64,
    /** The interrupted code's stack pointer. */
    rsp : u64,
    /** The interrupted code's stack segment selector. */
    ss : u64,
}

/** RegisterFrame.vector for a frame saved by a .syscall_entry function: no interrupt vector is this large. */
SYSCALL_VECTOR :: 0xffff_ffff_ffff_ffff

/**
 * What the gs base must point at while in the kernel, at offset 0, for .syscall_entry functions:
 * their generated code saves the user's stack pointer here, and loads kernel_stack.
 */
SyscallScratch :: struct {
    /** The top of the stack SYSCALL entry switches to, which the kernel sets for the thread about to run. */
    kernel_stack : u64,
    /** Where the entry saves the user's stack pointer; the kernel reads it, not writes it. */
    user_stack : u64,
}

/** Addresses for the 256 interrupt descriptor table entries, from entry_points. */
EntryPoints :: struct {
    /** Each vector's stub, indexed by vector, to put in that IDT entry. */
    addresses : u64[256],
}

/** The registers cpuid answers in, each as the CPU left it; what their bits mean depends on the leaf. */
CpuidResult :: struct {
    eax : u32, /**< The eax register after cpuid. */
    ebx : u32, /**< The ebx register after cpuid. */
    ecx : u32, /**< The ecx register after cpuid. */
    edx : u32, /**< The edx register after cpuid. */
}

// Interrupts

/** Disable maskable interrupts (cli). NMIs and exceptions still arrive. */
cli : fn() : ---
/** Enable maskable interrupts (sti), starting after the next instruction, so sti then hlt can't miss one. */
sti : fn() : ---
/** Wait for the next interrupt (hlt); with interrupts disabled, only an NMI or a reset ends it. */
hlt : fn() : ---
/** Hint that this is a spin-wait loop (pause), saving power and the pipeline's flush on leaving it. */
pause : fn() : ---
/**
 * Read the flags register.
 *
 * @return The whole of rflags: interrupts are enabled when bit 9 (IF) is set.
 */
read_rflags : fn() -> u64 : ---

// Descriptor tables

/**
 * Load the global descriptor table register (lgdt). The segment registers keep what they had until load_segments.
 *
 * @param table Where the table is and its size; only read during the instruction, so it can be a local.
 */
lgdt : fn(table: ptr[DescriptorTablePointer]) : ---
/**
 * Load the interrupt descriptor table register (lidt).
 *
 * @param table Where the table is and its size; only read during the instruction, so it can be a local. The table
 *     itself has to stay where it is while it's loaded.
 */
lidt : fn(table: ptr[DescriptorTablePointer]) : ---
/**
 * Load the task register (ltr), which marks the TSS descriptor busy.
 *
 * @param selector The selector of an available TSS descriptor in the GDT.
 */
ltr : fn(selector: u16) : ---
/**
 * Load cs with a far return, and ds, es, fs, gs and ss with data_selector, after lgdt.
 * fs and gs bases set through MSRs are reset, so set them after this.
 *
 * @param code_selector The 64-bit code segment's selector in the GDT.
 * @param data_selector The data segment's selector in the GDT.
 */
load_segments : fn(code_selector, data_selector: u16) : ---
/** Swap the gs base with the IA32_KERNEL_GS_BASE MSR (swapgs), on entering or leaving the kernel. */
swapgs : fn() : ---

// I/O ports

/**
 * Read a byte from an I/O port (in).
 *
 * @param port The port, 0 to 65535.
 * @return What the device gave.
 */
in_u8  : fn(port: u16) -> u8  : ---
/**
 * Read two bytes from an I/O port (in).
 *
 * @param port The port, 0 to 65535.
 * @return What the device gave.
 */
in_u16 : fn(port: u16) -> u16 : ---
/**
 * Read four bytes from an I/O port (in).
 *
 * @param port The port, 0 to 65535.
 * @return What the device gave.
 */
in_u32 : fn(port: u16) -> u32 : ---
/**
 * Write a byte to an I/O port (out).
 *
 * @param port The port, 0 to 65535.
 * @param value What to write.
 */
out_u8  : fn(port: u16, value: u8 ) : ---
/**
 * Write two bytes to an I/O port (out).
 *
 * @param port The port, 0 to 65535.
 * @param value What to write.
 */
out_u16 : fn(port: u16, value: u16) : ---
/**
 * Write four bytes to an I/O port (out).
 *
 * @param port The port, 0 to 65535.
 * @param value What to write.
 */
out_u32 : fn(port: u16, value: u32) : ---

// System calls, from user mode

/**
 * Make a system call with Linux's x86-64 convention: the number in rax, up to six arguments in rdi,
 * rsi, rdx, r10, r8 and r9, and the result in rax. rcx and r11 are clobbered. It doesn't use the
 * stack, so it works on a fiber's small one.
 *
 * @param number The system call's number, in rax.
 * @param a The first argument, in rdi; 0 when the call takes fewer.
 * @param b The second argument, in rsi.
 * @param c The third argument, in rdx.
 * @param d The fourth argument, in r10.
 * @param e The fifth argument, in r8.
 * @param f The sixth argument, in r9.
 * @return rax after the call: -4095 to -1, as an i64, are errors (-errno), and anything else is the call's result.
 */
syscall : fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> u64 : ---

/** What system_call gives: rax, rdx and r8 after the call, whose meaning is the kernel's. */
SystemCallResult :: struct {
    rax : u64, /**< rax after the call. */
    rdx : u64, /**< rdx after the call. */
    r8 : u64, /**< r8 after the call. */
}

/**
 * Make a system call that answers in up to three registers, like SlopOS's: the number in rax, up to six
 * arguments in rdi, rsi, rdx, r10, r8 and r9, and rax, rdx and r8 after it. rcx and r11 are clobbered,
 * and every other register is kept. It doesn't use the stack.
 *
 * @param number The system call's number, in rax.
 * @param a The first argument, in rdi; 0 when the call takes fewer.
 * @param b The second argument, in rsi.
 * @param c The third argument, in rdx.
 * @param d The fourth argument, in r10.
 * @param e The fifth argument, in r8.
 * @param f The sixth argument, in r9.
 * @return The three registers the kernel answered in.
 */
system_call : fn(number: u64, a: u64 = 0, b: u64 = 0, c: u64 = 0, d: u64 = 0, e: u64 = 0, f: u64 = 0) -> SystemCallResult : ---

/**
 * Start a thread with Linux's clone, which starts on stack by calling entry(argument), with the C convention.
 *
 * @param flags clone's flags. With CLONE_PARENT_SETTID and CLONE_CHILD_CLEARTID, the kernel stores the new thread's ID
 *     through parent_tid, and clears it through child_tid once the thread has exited.
 * @param stack The top of the new thread's stack, which the caller allocated and keeps until the thread has exited.
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

// Model-specific registers

/**
 * Read a model-specific register (rdmsr).
 *
 * @param msr The register's number, like 0xC000_0080 for IA32_EFER; one the CPU doesn't have faults.
 * @return Its 64 bits.
 */
rdmsr : fn(msr: u32) -> u64 : ---
/**
 * Write a model-specific register (wrmsr).
 *
 * @param msr The register's number; one the CPU doesn't have faults.
 * @param value Its 64 bits; reserved bits set fault.
 */
wrmsr : fn(msr: u32, value: u64) : ---

// Control registers and paging

/**
 * Read CR0.
 *
 * @return Its bits, like PE (0), WP (16) and PG (31).
 */
read_cr0 : fn() -> u64 : ---
/**
 * Write CR0.
 *
 * @param value Its new bits; changing PG or PE changes how every address is read from the next instruction on.
 */
write_cr0 : fn(value: u64) : ---
/**
 * Read CR2, in a page fault's handler.
 *
 * @return The linear address of the last page fault; the next fault replaces it.
 */
read_cr2 : fn() -> u64 : ---
/**
 * Read CR3.
 *
 * @return The physical address of the top-level page table, and its flags or PCID in the low 12 bits.
 */
read_cr3 : fn() -> u64 : ---
/**
 * Switch page tables, flushing non-global TLB entries unless PCID says otherwise.
 *
 * @param value The physical address of the top-level page table, 4 KiB-aligned, with its flags or PCID in the low 12
 *     bits; with PCIDs on, bit 63 keeps that PCID's TLB entries.
 */
write_cr3 : fn(value: u64) : ---
/**
 * Read CR4.
 *
 * @return Its bits, like PAE (5), PCIDE (17) and OSXSAVE (18).
 */
read_cr4 : fn() -> u64 : ---
/**
 * Write CR4.
 *
 * @param value Its new bits; setting one the CPU doesn't support faults.
 */
write_cr4 : fn(value: u64) : ---
/**
 * Read a debug register: DR0 to DR3, the breakpoints' linear addresses.
 *
 * @return Its address.
 */
read_dr0 : fn() -> u64 : ---
/** Read DR1, as read_dr0. */
read_dr1 : fn() -> u64 : ---
/** Read DR2, as read_dr0. */
read_dr2 : fn() -> u64 : ---
/** Read DR3, as read_dr0. */
read_dr3 : fn() -> u64 : ---
/**
 * Read DR6, the debug status.
 *
 * @return Its bits: B0 to B3 (0 to 3) for the breakpoints that matched, BS (14) for a single step.
 */
read_dr6 : fn() -> u64 : ---
/**
 * Read DR7, the debug control.
 *
 * @return Its bits: each breakpoint's local enable (bit 2n), and its condition and length (bits 16 + 4n on).
 */
read_dr7 : fn() -> u64 : ---
/**
 * Write a debug register: DR0 to DR3, the breakpoints' linear addresses.
 *
 * @param value The address.
 */
write_dr0 : fn(value: u64) : ---
/** Write DR1, as write_dr0. */
write_dr1 : fn(value: u64) : ---
/** Write DR2, as write_dr0. */
write_dr2 : fn(value: u64) : ---
/** Write DR3, as write_dr0. */
write_dr3 : fn(value: u64) : ---
/**
 * Write DR6, the debug status, which the CPU never clears itself.
 *
 * @param value Its new bits; 0xffff0ff0 clears what a debug exception set.
 */
write_dr6 : fn(value: u64) : ---
/**
 * Write DR7, the debug control.
 *
 * @param value Its new bits; 0x400 (bit 10 is always 1) turns every breakpoint off.
 */
write_dr7 : fn(value: u64) : ---
/**
 * Leave a bootloader for what it loaded, never to come back: page_table loaded into CR3, the stack pointer set to
 * stack, and entry jumped to with argument as its first argument in the C convention of ELF programs (rdi), and a
 * zero return address above it.
 *
 * @param page_table The physical address for CR3, which has to map this code, stack and entry.
 * @param stack The top of the new stack, 16-byte aligned.
 * @param entry The address to jump to, under the new page table.
 * @param argument What entry gets in rdi.
 */
enter : fn(page_table: u64, stack: u64, entry: u64, argument: u64) #never_returns : ---
/**
 * Flush the TLB entry for one page (invlpg), after changing its mapping.
 *
 * @param address Any address in the page, under the current page table. Only this CPU's TLB is flushed.
 */
invlpg : fn(address: rawptr) : ---
/**
 * Write the cache line containing address back to memory, if it's dirty, and drop it from every cache, for a
 * device that reads memory without snooping caches.
 *
 * @param address Any address in the line. Order it against later accesses with mfence.
 */
clflush : fn(address: rawptr) : ---
/** Order every load and store before it before every one after it, clflush's among them (mfence). */
mfence : fn() : ---

// Entry and return

/**
 * Give one entry point per vector for handler, an entry function (#calling_convention(.entry)).
 *
 * The compiler generates a small stub per vector that records the vector number (and an error code of 0
 * where the CPU doesn't push one), then enters handler. handler may return, for NMIs: the frame is
 * restored and the interrupted code resumes (docs/calling_convention.md, Entry Functions).
 *
 * @tparam handler The entry function, as a compile-time value; the stubs are generated once for each handler this
 *     is called with.
 * @param handler The entry function. It's also the generic parameter, so it must be known at compile time.
 * @return The 256 stubs' addresses, read-only, in the program for its whole run.
 */
entry_points : fn[handler](handler: (fn(frame: ptr[mut RegisterFrame]))) -> ptr[EntryPoints] : ---

/**
 * Restore every register from frame and return to user mode: swapgs, then sysretq when
 * rcx == rip, r11 == rflags and rip is canonical, otherwise iretq.
 *
 * @param frame The registers to return with, from an entry function or kept in a thread's structures; its rip, cs, ss
 *     and rflags have to be user mode's.
 */
return_to_user #never_returns : fn(frame: ptr[RegisterFrame]) : ---

/**
 * Read the current gs base: rdgsbase if FSGSBASE is enabled, otherwise the IA32_GS_BASE MSR.
 *
 * @return The gs base, like a pointer to this CPU's data in the kernel after swapgs.
 */
read_gs_base : fn() -> rawptr : ---

// Vector state

/**
 * Save the state components selected by mask (xsave), in the standard format.
 *
 * @param area Where they go: 64-byte aligned, and as large as CPUID leaf 0xD says for the components enabled.
 * @param mask Which components, as XCR0's bits; only those also enabled in XCR0 are saved.
 */
xsave : fn(area: rawptr, mask: u64) : ---
/**
 * Save the state components selected by mask in the compacted format (xsavec), leaving out components in their
 * initial state.
 *
 * @param area Where they go: 64-byte aligned, and as large as CPUID leaf 0xD says for the compacted format.
 * @param mask Which components, as XCR0's bits.
 */
xsavec : fn(area: rawptr, mask: u64) : ---
/**
 * Save the state components selected by mask (xsaveopt), skipping components unchanged since the last xrstor from the
 * same area.
 *
 * @param area Where they go, as for xsave; it has to be the area last restored from for the skipping to be right.
 * @param mask Which components, as XCR0's bits.
 */
xsaveopt : fn(area: rawptr, mask: u64) : ---
/**
 * Restore the state components selected by mask (xrstor), from an area one of the xsave functions wrote.
 *
 * @param area What was saved, 64-byte aligned; a malformed header faults.
 * @param mask Which components, as XCR0's bits; those selected that the area holds no state for are set to their
 *     initial state.
 */
xrstor : fn(area: rawptr, mask: u64) : ---
/**
 * Read an extended control register (xgetbv).
 *
 * @param register Which one; 0 is XCR0, the enabled state components.
 * @return Its 64 bits.
 */
xgetbv : fn(register: u32) -> u64 : ---
/**
 * Write an extended control register (xsetbv), in ring 0.
 *
 * @param register Which one; 0 is XCR0.
 * @param value Its new bits; a combination the CPU doesn't support faults.
 */
xsetbv : fn(register: u32, value: u64) : ---

// Identification and timing

/**
 * Ask the CPU what it is and what it has (cpuid).
 *
 * @param leaf Which question, in eax, like 1 for feature bits or 7 for extended ones.
 * @param subleaf A further choice for leaves that take one, in ecx; ignored by the rest.
 * @return The four registers it answered in.
 */
cpuid : fn(leaf: u32, subleaf: u32 = 0) -> CpuidResult : ---
/**
 * Read the time-stamp counter (rdtsc). Not serializing, so it may run before earlier instructions finish.
 *
 * @return The count of reference cycles since reset, at a rate that's constant on CPUs with an invariant TSC.
 */
rdtsc : fn() -> u64 : ---
/**
 * Read a value from the CPU's entropy source (rdseed).
 *
 * @return 64 random bits, or null when none was ready (the carry flag was clear), in which case try again later.
 */
rdseed : fn() -> u64? : ---
/**
 * Read a value from the CPU's random number generator, seeded from its entropy source (rdrand).
 *
 * @return 64 random bits, or null when none was ready (the carry flag was clear), in which case try again.
 */
rdrand : fn() -> u64? : ---

/*
 * AES and carryless multiplication (AES-NI and PCLMULQDQ). Neither is in every x86-64 CPU, so a
 * function using them is marked #target_features("aes,pclmul") and only called once cpuid says the
 * CPU has them (leaf 1: ecx bit 25 for AES, bit 1 for PCLMULQDQ). A round constant or selector is a
 * constant, since it's part of the instruction.
 */

/**
 * Do one AES encryption round (aesenc): ShiftRows, SubBytes and MixColumns, then round_key xor'ed in.
 *
 * @param state The 16-byte block so far.
 * @param round_key This round's key.
 * @return The block after the round.
 */
aes_encrypt_round : fn(state: v128, round_key: v128) -> v128 : ---
/**
 * Do the last encryption round (aesenclast), without MixColumns.
 *
 * @param state The 16-byte block so far.
 * @param round_key The last round's key.
 * @return The block after the last round: the ciphertext, when the earlier rounds used the same key schedule.
 */
aes_encrypt_last : fn(state: v128, round_key: v128) -> v128 : ---
/**
 * Do one AES decryption round (aesdec).
 *
 * @param state The 16-byte block so far.
 * @param round_key This round's key, made for decryption by aes_inverse_mix.
 * @return The block after the round.
 */
aes_decrypt_round : fn(state: v128, round_key: v128) -> v128 : ---
/**
 * Do the last decryption round (aesdeclast).
 *
 * @param state The 16-byte block so far.
 * @param round_key The first encryption round key, as it is, not through aes_inverse_mix.
 * @return The block after the last round: the plaintext, when the earlier rounds used the decryption schedule.
 */
aes_decrypt_last : fn(state: v128, round_key: v128) -> v128 : ---
/**
 * Apply InvMixColumns to a round key (aesimc), to use an encryption round key for decryption.
 *
 * @param round_key An encryption round key, other than the first and last.
 * @return The key for aes_decrypt_round.
 */
aes_inverse_mix : fn(round_key: v128) -> v128 : ---
/**
 * Work out what expanding a key's next round key needs (aeskeygenassist).
 *
 * @param key The last round key, or the part of it the expansion uses.
 * @param round_constant The round's constant, 0x01, 0x02, 0x04 and so on; a compile-time constant, since it's part of
 *     the instruction.
 * @return The substituted and rotated words, with round_constant xor'ed in, that the expansion mixes in.
 */
aes_key_assist : fn(key: v128, round_constant: u8) -> v128 : ---
/**
 * Multiply one 64-bit half of a by one of b without carries (pclmulqdq), as polynomials over GF(2), as GHASH does.
 *
 * @param a The first operand's two halves.
 * @param b The second operand's two halves.
 * @param selector Which halves: bit 0 picks a's (0 low, 1 high), and bit 4 b's; a compile-time constant.
 * @return The 128-bit product.
 */
carryless_multiply : fn(a: v128, b: v128, selector: u8) -> v128 : ---

/*
 * SHA-256 (the SHA extensions), on 32-bit lanes. Not in every x86-64 CPU, so a function using them is marked
 * #target_features("sha") and only called once cpuid says the CPU has them (leaf 7: ebx bit 29). They hold the
 * state as A, B, E and F in one vector and C, D, G and H in another, highest lane first.
 */

/**
 * Do two SHA-256 rounds (sha256rnds2).
 *
 * @param cdgh The state's C, D, G and H, highest lane first.
 * @param abef The state's A, B, E and F, highest lane first.
 * @param message The next two rounds' message words, each plus its round constant, in lanes 0 and 1; the others are
 *     ignored.
 * @return The new A, B, E and F; the old A, B, E and F are the new C, D, G and H.
 */
sha256_rounds2 : fn(cdgh: vector[u32, 4], abef: vector[u32, 4], message: vector[u32, 4]) -> vector[u32, 4] : ---
/**
 * Do the first half of working out the next four message words from the last eight (sha256msg1).
 *
 * @param earlier The oldest four of the eight words.
 * @param later The four words after earlier; only its lowest lane, the fifth oldest word, is used.
 * @return The partial sums, to add words 7 back to and give sha256_message2.
 */
sha256_message1 : fn(earlier: vector[u32, 4], later: vector[u32, 4]) -> vector[u32, 4] : ---
/**
 * Do the second half of working out the next four message words (sha256msg2).
 *
 * @param partial What sha256_message1 gave, plus the words 7 back.
 * @param last The last four words.
 * @return The next four message words.
 */
sha256_message2 : fn(partial: vector[u32, 4], last: vector[u32, 4]) -> vector[u32, 4] : ---
